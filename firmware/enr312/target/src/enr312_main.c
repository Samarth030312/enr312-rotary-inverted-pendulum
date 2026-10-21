/**
 * @file    enr312_main.c
 * @brief   ENR312 rotary inverted pendulum -- target application entry point.
 *
 * TARGET: ENR312.  This is NOT the vehicle firmware.
 * No micro-ROS, no FreeRTOS, no vehicle project message types, no BNO085.
 * See docs/ARCHITECTURE.md.
 *
 * WHAT THIS FIRMWARE DOES ON POWER-UP: nothing mechanical. It configures the
 * pins, holds the L6474 in reset, starts the encoder counter, prints a banner,
 * and waits for a command. The motor is not energised until the operator types
 * 'a', and it cannot move until they then type 's'. That is the whole design
 * intent -- see the state machine in enr312_safety.h.
 *
 * The control core under ../src/ is unchanged and hardware-independent; this
 * file is the adapter that gives it a timer, a pin and a counter.
 */

#include "enr312_board.h"
#include "enr312_safety.h"
#include "enr312_l6474.h"
#include "enr312_stepgen.h"
#include "enr312_encoder_hw.h"
#include "enr312_telemetry.h"

#include "enr312_rig_config.h"
#include "enr312_encoder.h"
#include "enr312_rotor.h"
#include "enr312_runner.h"
#include "enr312_cmd.h"

#include <math.h>
#include <stdlib.h>

/* ---------------------------------------------------------------- state --- */

static ENR312_Encoder_t g_enc;
static ENR312_Rotor_t   g_rotor;

static volatile uint32_t g_ctrl_ticks       = 0;
static volatile uint32_t g_ctrl_overruns    = 0;
static volatile bool     g_ctrl_busy        = false;
static volatile double   g_pend_angle_deg   = 0.0;
static volatile double   g_pend_vel_rad_s   = 0.0;

/* First-motion parameters. Deliberately timid: see
 * docs/experiments/EXP001/FIRST_MOTION.md. */
#define FIRST_MOTION_DEG      5.0
#define FIRST_MOTION_RATE_HZ  200u

/* Streaming telemetry for the MATLAB live viewer (matlab/hardware/).
 * One CSV line every STREAM_DIV control ticks: 10 x 2 ms = 50 Hz.
 * Sent from the main loop, never from the ISR, so it cannot delay sampling. */
#define STREAM_DIV            10u

static bool     g_stream           = false;
static uint32_t g_stream_last_tick = 0;

/* Closed-loop experiments (Tutorials 2-5), configured by '$' line commands.
 * The runner is ticked from the control ISR; the main loop only configures,
 * starts, stops and reports. */
static ENR312_Runner_t       g_run;
static ENR312_RunnerConfig_t g_cfg;
static volatile uint32_t     g_last_rx_tick   = 0;
static volatile uint32_t     g_isr_cycles_max = 0;
static char                  g_line[64];
static int                   g_line_len = -1;          /* -1: not in a '$' line */

/* While an experiment runs, the host must send something (MATLAB sends '.')
 * at least once a second, or the run is aborted and the driver de-energised. */
#define HOST_WATCHDOG_TICKS   (ENR312_CONTROL_RATE_HZ * 1u)
#define USTEP_PER_DEG         ((double)ENR312_ROTOR_MICROSTEPS_PER_REV / 360.0)

/* Rotor angle from the step generator's exact signed pulse count. */
static double rotor_deg_now(void)
{
    return (double)ENR312_ROTOR_POLARITY * (double)ENR312_StepGen_Position() / USTEP_PER_DEG;
}

/* ---------------------------------------------------------- control tick --- */

/**
 * @brief 500 Hz control ISR: sample, supervise, and (when an experiment runs)
 *        close the loop.
 *
 * Supervision runs every tick regardless of the main loop. When the runner is
 * active its commanded velocity drives the step generator; the host watchdog
 * and the safety state can stop it at any tick. Worst-case ISR time is
 * measured with the DWT cycle counter and reported ('t', stream) -- the
 * first hardware evidence for loop timing (OI-10).
 */
void ENR312_ControlTick(void)
{
    double ang_deg;
    uint32_t c0 = DWT->CYCCNT;

    if (g_ctrl_busy) {
        g_ctrl_overruns++;
        ENR312_Safety_RaiseFault(ENR312_FAULT_CTRL_OVERRUN);
        return;
    }
    g_ctrl_busy = true;
    g_ctrl_ticks++;

    ENR312_EncoderHw_Sample(&g_enc);
    ang_deg = ENR312_Encoder_GetAngleDeg(&g_enc);
    g_pend_angle_deg = ang_deg;
    g_pend_vel_rad_s = ENR312_Encoder_GetVelocityRadS(&g_enc, ENR312_CONTROL_PERIOD_S);

    bool running = ENR312_Runner_IsMoving(&g_run);

    /* +/-120 deg is a SUSPENDED-mode bound: active during counted moves and
     * suspended runs. Inverted runs (5, 6-8, 23) keep the pendulum near 180 deg
     * and have their own bound around upright inside the core. */
    if ((ENR312_StepGen_Busy() || ENR312_Runner_SuspendedLimit(&g_run)) &&
        fabs(ang_deg) > ENR312_PENDULUM_ABORT_DEG) {
        ENR312_Safety_RaiseFault(ENR312_FAULT_PENDULUM_ABORT);
    }
    double rot = rotor_deg_now();
    if (fabs(rot) > ENR312_ROTOR_LIMIT_DEG) {
        ENR312_Safety_RaiseFault(ENR312_FAULT_ROTOR_LIMIT);
    }

    if (running) {
        if (!ENR312_Safety_MotionPermitted()) {
            ENR312_Runner_Abort(&g_run, ENR312_RUN_ABORT_OPERATOR);
        } else if ((uint32_t)(g_ctrl_ticks - g_last_rx_tick) > HOST_WATCHDOG_TICKS) {
            ENR312_Runner_Abort(&g_run, ENR312_RUN_ABORT_WATCHDOG);
            ENR312_Safety_RaiseFault(ENR312_FAULT_OPERATOR_ABORT);
        } else {
            double v = ENR312_Runner_Tick(&g_run, rot, ang_deg);
            (void)ENR312_StepGen_SetVelocity((double)ENR312_ROTOR_POLARITY * v * USTEP_PER_DEG);
        }
        if (!ENR312_Runner_IsMoving(&g_run) && ENR312_Safety_MotionPermitted()) {
            (void)ENR312_StepGen_SetVelocity(0.0);
        }
    }

    uint32_t dc = DWT->CYCCNT - c0;
    if (dc > g_isr_cycles_max) { g_isr_cycles_max = dc; }
    g_ctrl_busy = false;
}

/* --------------------------------------------------------------- motion --- */

/**
 * @brief Command a relative rotor move. Returns false if it was not issued.
 *
 * The rotor model is updated with the microsteps ACTUALLY accepted after
 * limit clamping, and the step generator is then asked for exactly that many
 * pulses. Those two numbers must never diverge -- that identity is EXP001
 * assumption A2, and it is the reason this function exists rather than the
 * caller poking the step generator directly.
 */
static bool move_degrees(double deg, uint32_t rate_hz)
{
    int64_t  actual = 0;
    uint32_t arr    = 0;
    double   got_hz = 0.0;
    ENR312_RotorStatus_t st;

    if (!ENR312_Safety_MotionPermitted()) {
        ENR312_Telemetry_Write("  refused: not RUNNING\r\n");
        return false;
    }
    if (ENR312_StepGen_Busy()) {
        ENR312_Telemetry_Write("  refused: move in progress\r\n");
        return false;
    }
    if (ENR312_Runner_IsMoving(&g_run)) {
        ENR312_Telemetry_Write("  refused: an experiment is running ('$stop' or 'x')\r\n");
        return false;
    }
    g_rotor.position_microsteps = ENR312_StepGen_Position();

    st = ENR312_Rotor_MoveDegrees(&g_rotor, deg, &actual);
    if (st == ENR312_ROTOR_REJECTED || actual == 0) {
        ENR312_Telemetry_Write("  refused: rejected by rotor model\r\n");
        return false;
    }
    if (st == ENR312_ROTOR_CLAMPED_TO_LIMIT) {
        ENR312_Telemetry_Write("  NOTE: clamped at travel limit\r\n");
    }

    (void)ENR312_Rotor_ComputeStepTimerARR(&g_rotor, rate_hz, &arr, &got_hz);

    {
        uint32_t n = (uint32_t)((actual < 0) ? -actual : actual);
        ENR312_StepDir_t d = (actual > 0) ? ENR312_STEP_DIR_POSITIVE
                                          : ENR312_STEP_DIR_NEGATIVE;
        ENR312_Telemetry_Printf("  %ld microsteps, dir %s, ARR %lu (%d.%02d Hz)\r\n",
                                (long)actual, (actual > 0) ? "+" : "-",
                                (unsigned long)arr,
                                (int)got_hz, (int)((got_hz - (int)got_hz) * 100));
        return ENR312_StepGen_Start(d, n, arr);
    }
}

/* ------------------------------------------------------------ reporting --- */

/* Degrees -> signed millidegrees, rounded. Printing the integer and fractional
 * parts separately loses the sign for -1 < x < 0 ("-0.5" printed as "0.50"),
 * so every angle goes out as one signed integer instead. */
static long to_mdeg(double deg)
{
    return (long)(deg * 1000.0 + ((deg >= 0.0) ? 0.5 : -0.5));
}

static void print_status(void)
{
    long rot = to_mdeg(rotor_deg_now());
    long pen = to_mdeg(g_pend_angle_deg);

    ENR312_Telemetry_Printf(
        "state=%s faults=0x%02lX  rotor=%s%ld.%03ld deg  pend=%s%ld.%03ld deg  "
        "raw=%u  pulses=%lu  ticks=%lu  ovr=%lu  isr_max_us=%lu  rxerr=%lu  run=%s/%s\r\n",
        ENR312_Safety_StateName(ENR312_Safety_GetState()),
        (unsigned long)ENR312_Safety_GetFaults(),
        (rot < 0) ? "-" : "", labs(rot) / 1000, labs(rot) % 1000,
        (pen < 0) ? "-" : "", labs(pen) / 1000, labs(pen) % 1000,
        (unsigned)ENR312_EncoderHw_ReadRaw(),
        (unsigned long)ENR312_StepGen_TotalPulses(),
        (unsigned long)g_ctrl_ticks,
        (unsigned long)g_ctrl_overruns,
        (unsigned long)(g_isr_cycles_max / 84u),
        (unsigned long)ENR312_Telemetry_RxErrors(),
        ENR312_Runner_IsMoving(&g_run) ? "ACTIVE" : "IDLE",
        ENR312_Runner_PhaseName(&g_run));
}

/* Protocol 2 stream line (the first 7 fields are protocol 1, unchanged):
 * D,<ticks>,<rotor mdeg>,<pendulum mdeg>,<encoder raw>,<faults>,<state>,
 *   <run exp or 0>,<phase>,<u deg/s^2>,<reference mdeg>,<isr max us> */
static void print_stream(void)
{
    bool running = ENR312_Runner_IsMoving(&g_run);
    double u = g_run.u;
    ENR312_Telemetry_Printf("D,%lu,%ld,%ld,%u,%lu,%s,%u,%u,%ld,%ld,%lu\r\n",
        (unsigned long)g_ctrl_ticks,
        to_mdeg(rotor_deg_now()),
        to_mdeg(g_pend_angle_deg),
        (unsigned)ENR312_EncoderHw_ReadRaw(),
        (unsigned long)ENR312_Safety_GetFaults(),
        ENR312_Safety_StateName(ENR312_Safety_GetState()),
        running ? (unsigned)g_run.cfg.exp : 0u,
        (unsigned)g_run.phase,
        (long)(u + ((u >= 0.0) ? 0.5 : -0.5)),
        to_mdeg(g_run.ref_deg),
        (unsigned long)(g_isr_cycles_max / 84u));
}

static void process_line(void)
{
    char reply[320];
    double mv = 0.0;
    ENR312_CmdAction_t a = ENR312_Cmd_Line(g_line, &g_cfg, &mv, reply, (int)sizeof reply);
    switch (a) {
    case ENR312_CMD_GO:
        if (!ENR312_Safety_MotionPermitted()) {
            ENR312_Telemetry_Write("ERR not RUNNING: ARM ('a') then START ('s') first\r\n");
        } else if (ENR312_Runner_IsMoving(&g_run)) {
            ENR312_Telemetry_Write("ERR an experiment is already running\r\n");
        } else if (ENR312_StepGen_Busy()) {
            ENR312_Telemetry_Write("ERR a move is in progress\r\n");
        } else {
            bool ok;
            __disable_irq();
            g_last_rx_tick = g_ctrl_ticks;
            ok = ENR312_Runner_Start(&g_run, &g_cfg);
            __enable_irq();
            if (ok) {
                ENR312_Telemetry_Printf("GO EXP%03u\r\n", (unsigned)g_cfg.exp);
            } else {
                ENR312_Telemetry_Write("ERR configuration invalid ('$cfg')\r\n");
            }
        }
        break;
    case ENR312_CMD_STOP:
        __disable_irq();
        ENR312_Runner_Stop(&g_run);
        __enable_irq();
        ENR312_Telemetry_Write("STOPPING (decelerating)\r\n");
        break;
    case ENR312_CMD_MOVE:
        ENR312_Telemetry_Write("MOVE:\r\n");
        (void)move_degrees(mv, FIRST_MOTION_RATE_HZ);
        break;
    case ENR312_CMD_REF: {
        bool ok;
        __disable_irq();
        ok = ENR312_Runner_SetRef(&g_run, mv);
        __enable_irq();
        if (ok) {
            char v[24];
            (void)ENR312_Cmd_FormatFixed(v, (int)sizeof v, mv);
            ENR312_Telemetry_Printf("REF %s\r\n", v);
        } else {
            ENR312_Telemetry_Write("ERR ref needs a running experiment 6..23\r\n");
        }
        break;
    }
    case ENR312_CMD_REPLY:
    default:
        if (reply[0] == 'C' && reply[1] == ',') {
            /* an accepted change: a running general-core experiment takes it now */
            __disable_irq();
            ENR312_Runner_ApplyLive(&g_run, &g_cfg);
            __enable_irq();
        }
        ENR312_Telemetry_Printf("%s\r\n", reply);
        break;
    }
}

/* Report runner transitions from the main loop (never from the ISR). */
static void report_runner(void)
{
    static ENR312_RunState_t last_state = ENR312_RUN_IDLE;
    static uint8_t           last_phase = 0xFFu;
    ENR312_RunState_t st = g_run.state;
    uint8_t ph = g_run.phase;
    if (st == last_state && ph == last_phase) { return; }
    if (st == ENR312_RUN_ABORTED && last_state != ENR312_RUN_ABORTED) {
        ENR312_Telemetry_Printf("RUN ABORTED EXP%03u reason=%s\r\n",
                                (unsigned)g_run.cfg.exp, ENR312_Runner_AbortName(&g_run));
    } else if (st == ENR312_RUN_FINISHED && last_state != ENR312_RUN_FINISHED) {
        ENR312_Telemetry_Printf("RUN FINISHED EXP%03u\r\n", (unsigned)g_run.cfg.exp);
    } else if (st == ENR312_RUN_ACTIVE) {
        ENR312_Telemetry_Printf("RUN EXP%03u phase=%s\r\n",
                                (unsigned)g_run.cfg.exp, ENR312_Runner_PhaseName(&g_run));
    }
    last_state = st; last_phase = ph;
}

static void print_help(void)
{
    ENR312_Telemetry_Write(
        "\r\n--- ENR312 commands ---------------------------------------\r\n"
        /* the version again: a host that connects after boot (the ST-LINK VCP
         * does not reset the MCU) learns the protocol by sending '?' */
        " Firmware:      " ENR312_FW_VERSION "\r\n"
        "  ?  help            t  status\r\n"
        "  r  toggle 50 Hz CSV stream for MATLAB (D,ticks,rotor,pend,raw,faults,state)\r\n"
        "  a  ARM   (energise L6474; motor holds, does not move)\r\n"
        "  s  START (permit motion; requires ARMED)\r\n"
        "  x  ABORT (immediate SAFE; always available)\r\n"
        "  c  clear latched fault -> SAFE\r\n"
        "  z  zero both angle datums here\r\n"
        "  +  first motion  +5 deg @ 200 steps/s\r\n"
        "  -  first motion  -5 deg @ 200 steps/s\r\n"
        "  q  read L6474 STATUS register\r\n"
        "  p  SPI probe in SAFE (reads L6474 registers, never energises)\r\n"
        "  P  scan the 4 CS/SCK resistor routings (SAFE only, never energises)\r\n"
        "  M  electrical self-test: reset line, MISO, FLAG (SAFE only, never energises)\r\n"
        "  .  keep-alive (send at least once a second while an experiment runs)\r\n"
        "  $exp=N (2..10, 21..23)  $kp= $ki= $kd= $kpp= $kdp= $step= $dist= $ulim= $vmax=\r\n"
        "  $fdr= $fdp= $k1..$k4= $bv= $imp= $uon= $db= $rrate= $div= $ma=\r\n"
        "  $cfg  $defaults  $go  $stop  $move=D  $ref=D (live set-point)\r\n"
        "-----------------------------------------------------------\r\n");
}

/* ------------------------------------------------------------------ main --- */

int main(void)
{
    HAL_Init();
    ENR312_Board_SystemClockConfig();
    ENR312_Board_Init();          /* L6474 goes into reset inside here */

    ENR312_Telemetry_Init();
    ENR312_L6474_SpiInit();
    ENR312_StepGen_Init();

    ENR312_EncoderHw_Init(&g_enc, ENR312_ENCODER_POLARITY);
    ENR312_Rotor_Init(&g_rotor, ENR312_ROTOR_POLARITY);
    ENR312_Runner_Defaults(&g_cfg, 5u);
    g_run.state = ENR312_RUN_IDLE;

    /* DWT cycle counter: measures the control ISR (reported as isr_max_us). */
    CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
    DWT->CYCCNT = 0u;
    DWT->CTRL  |= DWT_CTRL_CYCCNTENA_Msk;

    ENR312_Safety_EnterSafe();

    ENR312_Telemetry_Write(
        "\r\n===========================================================\r\n"
        " ENR312 ROTARY INVERTED PENDULUM -- target firmware\r\n"
        " NUCLEO-F401RE + X-NUCLEO-IHM01A1 (L6474) + LPD3806 encoder\r\n"
        " Parameter set: " ENR312_PARAMETER_SET_ID "\r\n"
        " Firmware:      " ENR312_FW_VERSION "\r\n"
        "\r\n"
        " THIS IS NOT THE VEHICLE FIRMWARE.\r\n"
        " State: SAFE. L6474 held in reset. No motion possible.\r\n"
        "===========================================================\r\n");
    print_help();

    /* Control tick last, so nothing supervises a half-built system. */
    ENR312_CTRL_TIM->CR1 |= TIM_CR1_CEN;

    for (;;) {
        char c = ENR312_Telemetry_ReadChar();

        if (c != '\0') {
            g_last_rx_tick = g_ctrl_ticks;          /* any byte feeds the watchdog */
        }
        if (g_line_len >= 0) {                     /* inside a '$' line */
            if (c == '\r' || c == '\n') {
                g_line[g_line_len] = '\0';
                process_line();
                g_line_len = -1;
            } else if (c != '\0' && g_line_len < (int)sizeof g_line - 1) {
                g_line[g_line_len++] = c;
            }
            c = '\0';
        }

        switch (c) {
        case '\0':
        case '.':                                  /* keep-alive */
        case '\r':
        case '\n':
            break;

        case '$':
            g_line_len = 0;
            break;

        case '?':
            print_help();
            break;

        case 't':
            print_status();
            break;

        case 'r':
            g_stream = !g_stream;
            g_stream_last_tick = g_ctrl_ticks;
            ENR312_Telemetry_Write(g_stream ? "STREAM ON\r\n" : "STREAM OFF\r\n");
            break;

        case 'a':
            ENR312_Telemetry_Write("ARM: configuring L6474 over SPI...\r\n");
            if (ENR312_Safety_Arm()) {
                ENR312_Telemetry_Write("  ARMED. Motor is energised and holding.\r\n");
            } else {
                ENR312_Telemetry_Printf("  ARM FAILED. faults=0x%02lX\r\n",
                                        (unsigned long)ENR312_Safety_GetFaults());
            }
            break;

        case 's':
            ENR312_Telemetry_Write(ENR312_Safety_Start()
                ? "RUNNING. Motion permitted.\r\n"
                : "  refused: must be ARMED first.\r\n");
            break;

        case 'x':
            __disable_irq();
            ENR312_Runner_Abort(&g_run, ENR312_RUN_ABORT_OPERATOR);
            __enable_irq();
            ENR312_Safety_EnterSafe();
            ENR312_Telemetry_Write("ABORT -> SAFE.\r\n");
            break;

        case 'c':
            ENR312_Safety_ClearFault();
            ENR312_Telemetry_Write("Faults cleared -> SAFE.\r\n");
            break;

        case 'z':
            if (ENR312_Runner_IsMoving(&g_run) || ENR312_StepGen_Busy()) {
                ENR312_Telemetry_Write("  refused: rotor is moving\r\n");
                break;
            }
            ENR312_Encoder_SetOriginHere(&g_enc);
            ENR312_Rotor_SetOriginHere(&g_rotor);
            ENR312_StepGen_SetOrigin();
            ENR312_Telemetry_Write("Datums zeroed here.\r\n");
            break;

        case '+':
            ENR312_Telemetry_Write("FIRST MOTION +5 deg:\r\n");
            (void)move_degrees(+FIRST_MOTION_DEG, FIRST_MOTION_RATE_HZ);
            break;

        case '-':
            ENR312_Telemetry_Write("FIRST MOTION -5 deg:\r\n");
            (void)move_degrees(-FIRST_MOTION_DEG, FIRST_MOTION_RATE_HZ);
            break;

        case 'p':
            /* SPI probe, motor-safe: only in SAFE; release reset, read three
             * registers, reset again. ENABLE is never sent, so the bridges stay
             * high-impedance. Power-on defaults: CONFIG 0x2E88; 0x0000 or
             * 0xFFFF means the L6474 is not answering (12 V, wiring, CS/SCK). */
            if (ENR312_Safety_GetState() != ENR312_STATE_SAFE) {
                ENR312_Telemetry_Write("  probe refused: only in SAFE (clear fault first)\r\n");
                break;
            }
            HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_SET);
            HAL_Delay(10);
            {
                unsigned st = (unsigned)ENR312_L6474_GetStatus();
                unsigned sm = (unsigned)ENR312_L6474_GetParam(L6474_REG_STEP_MODE);
                unsigned cf = (unsigned)ENR312_L6474_GetParam(L6474_REG_CONFIG);
                unsigned fl = ENR312_L6474_FlagAsserted() ? 1u : 0u;
                HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_RESET);
                ENR312_Telemetry_Printf("PROBE status=0x%04X step_mode=0x%02X config=0x%04X flag_low=%u  (%s)\r\n",
                    st, sm, cf, fl, (cf == 0x2E88u) ? "SPI OK: L6474 answers" :
                    (cf == 0x0000u || cf == 0xFFFFu) ? "NO ANSWER: check 12 V, shield seating, CS/SCK resistors" :
                    "unexpected value");
            }
            break;

        case 'P':
            /* Routing scan, motor-safe (SAFE only, ENABLE never sent): try the
             * four CS/SCK resistor options of UM1857 Tables 3/4 and report which
             * one the L6474 answers on. Restores the default afterwards. */
            if (ENR312_Safety_GetState() != ENR312_STATE_SAFE) {
                ENR312_Telemetry_Write("  scan refused: only in SAFE (clear fault first)\r\n");
                break;
            }
            for (unsigned k = 0; k < 4u; k++) {
                bool csa = (k & 1u) != 0u, scka = (k & 2u) != 0u;
                ENR312_L6474_UsePins(csa, scka);
                HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_SET);
                HAL_Delay(10);
                unsigned st = (unsigned)ENR312_L6474_GetStatus();
                unsigned cf = (unsigned)ENR312_L6474_GetParam(L6474_REG_CONFIG);
                HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_RESET);
                HAL_Delay(2);
                ENR312_Telemetry_Printf("SCAN CS=%s SCK=%s  status=0x%04X config=0x%04X  %s\r\n",
                    csa ? "PA4/A2 (R15)" : "PB6/D10 (R25, default)",
                    scka ? "PB3/D3 (R24)" : "PA5/D13 (R23, default)",
                    st, cf, (cf == 0x2E88u) ? "<-- ANSWERS" : "");
            }
            ENR312_L6474_UsePins(false, false);
            ENR312_Telemetry_Write("SCAN done; default pins restored. Faults raised by FLAG edges here are expected: 'c'.\r\n");
            break;

        case 'M':
            /* Electrical self-test, motor-safe (SAFE only, ENABLE never sent).
             * Reads back the reset line and samples MISO (PA6/D12) as a GPIO
             * with pull-up, then pull-down, with the L6474 in and out of reset:
             * a line that follows the pull is not driven by anything. */
            if (ENR312_Safety_GetState() != ENR312_STATE_SAFE) {
                ENR312_Telemetry_Write("  self-test refused: only in SAFE (clear fault first)\r\n");
                break;
            }
            {
                GPIO_InitTypeDef g = {0};
                unsigned r[2][4];
                for (unsigned rel = 0; rel < 2u; rel++) {
                    HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN,
                                      rel ? GPIO_PIN_SET : GPIO_PIN_RESET);
                    HAL_Delay(10);
                    r[rel][0] = (unsigned)HAL_GPIO_ReadPin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN);
                    /* SDO is high-Z while CS is high: sample with CS asserted. */
                    HAL_GPIO_WritePin(ENR312_CS_PORT, ENR312_CS_PIN, GPIO_PIN_RESET);
                    g.Pin = GPIO_PIN_6; g.Mode = GPIO_MODE_INPUT;
                    g.Pull = GPIO_PULLUP;   HAL_GPIO_Init(GPIOA, &g); HAL_Delay(2);
                    r[rel][1] = (unsigned)HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_6);
                    g.Pull = GPIO_PULLDOWN; HAL_GPIO_Init(GPIOA, &g); HAL_Delay(2);
                    r[rel][2] = (unsigned)HAL_GPIO_ReadPin(GPIOA, GPIO_PIN_6);
                    HAL_GPIO_WritePin(ENR312_CS_PORT, ENR312_CS_PIN, GPIO_PIN_SET);
                    r[rel][3] = (unsigned)HAL_GPIO_ReadPin(ENR312_FLAG_PORT, ENR312_FLAG_PIN);
                }
                HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_RESET);
                ENR312_L6474_SpiInit();                      /* MISO back to SPI */
                for (unsigned rel = 0; rel < 2u; rel++) {
                    ENR312_Telemetry_Printf("SELFTEST %s: reset_pin_reads=%u  MISO(CS low) pull-up=%u pull-down=%u (%s)  FLAG=%u\r\n",
                        rel ? "reset RELEASED" : "reset HELD   ", r[rel][0], r[rel][1], r[rel][2],
                        (r[rel][1] == 1u && r[rel][2] == 0u) ? "floating: nothing drives MISO" :
                        (r[rel][1] == 0u && r[rel][2] == 0u) ? "driven LOW" :
                        (r[rel][1] == 1u && r[rel][2] == 1u) ? "driven HIGH" : "odd", r[rel][3]);
                }
                ENR312_Telemetry_Write("SELFTEST done (driver back in reset). FLAG edges may latch 0x01: 'c'.\r\n");
            }
            break;

        case 'q':
            ENR312_Telemetry_Printf("L6474 STATUS = 0x%04X\r\n",
                                    (unsigned)ENR312_L6474_GetStatus());
            break;

        default:
            ENR312_Telemetry_Write("? unknown -- '?' for help\r\n");
            break;
        }

        report_runner();

        if (g_stream && (uint32_t)(g_ctrl_ticks - g_stream_last_tick) >= STREAM_DIV) {
            g_stream_last_tick = g_ctrl_ticks;     /* no burst catch-up */
            print_stream();
        }
    }
}

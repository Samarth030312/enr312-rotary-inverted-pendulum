/**
 * @file    enr312_host_rig.c
 * @brief   HOST ONLY: the ENR312 rig EMULATOR.
 *
 * Runs the REAL firmware control code (src/: runner, tutorial cores, PD,
 * command parser) against the nonlinear plant (host/enr312_plant.c), behind
 * the same console protocol as target/src/enr312_main.c. It is the firmware's
 * logic without the hardware -- not the hardware, and not a measurement.
 *
 *   enr312_host_rig --pty            print the pty path, then serve it in real time
 *   enr312_host_rig --batch [k=v...] run one experiment as fast as possible, CSV out
 *        k: exp kp kd kpp kdp step dist ulim vmax  seconds  upright(0/1)
 *
 * Emulator-only console keys (the real firmware answers '? unknown'):
 *   !  pluck the hanging pendulum by 30 deg
 *   ^  hold the pendulum upright (an operator's hand) until EXP005 captures it
 *
 * Mirrors main.c: state SAFE/ARMED/RUNNING/FAULT, faults bits, 500 Hz tick with
 * supervision, host watchdog, '$' lines, 50 Hz protocol-2 stream.
 */
#define _DEFAULT_SOURCE
#define _XOPEN_SOURCE 700
#include "enr312_runner.h"
#include "enr312_cmd.h"
#include "enr312_plant.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/select.h>
#include <signal.h>
#include <errno.h>

#define TS        ENR312_CONTROL_PERIOD_S
#define SUB       4
#define USTEP_PER_DEG ((double)ENR312_ROTOR_MICROSTEPS_PER_REV / 360.0)
#define WATCHDOG_TICKS (ENR312_CONTROL_RATE_HZ * 1u)

enum { SAFE, ARMED, RUNNING, FAULT };
static const char *const STATE_NAME[] = {"SAFE", "ARMED", "RUNNING", "FAULT"};
#define F_ROTOR_LIMIT  (1u << 3)
#define F_PEND_ABORT   (1u << 4)
#define F_OPERATOR     (1u << 6)

typedef struct {
    ENR312_Plant_t p;
    ENR312_Runner_t run;
    ENR312_RunnerConfig_t cfg;
    int state; unsigned faults;
    uint32_t ticks, last_rx;
    double enc_zero;              /* deg */
    int64_t rot_zero;             /* microsteps */
    int64_t move_left; int move_dir;
    double v_cmd;                 /* microsteps/s actually being emitted */
    int hold_upright;             /* '^' : hand holds until captured */
    int hold_after;               /* batch release=S: ticks the hand keeps holding after capture */
    int stream;
    char line[64]; int line_len;
    int fd;                       /* output; -1 = stdout batch */
} Rig;

static void out(Rig *r, const char *fmt, ...)
{
    char b[512]; va_list ap; va_start(ap, fmt);
    int n = vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    if (n <= 0) { return; }
    /* non-blocking, like the MCU's UART: if the host stops reading, bytes are
     * dropped and the rig keeps running (a blocking write froze the emulator) */
    if (r->fd >= 0) { ssize_t w = write(r->fd, b, (size_t)n); (void)w; }
}

static long mdeg(double d) { return (long)(d * 1000.0 + (d >= 0 ? 0.5 : -0.5)); }
static double rotor_deg(const Rig *r) { return (double)(r->p.pos - r->rot_zero) / USTEP_PER_DEG; }
static double pend_deg(const Rig *r)  { return ENR312_Plant_EncoderDeg(&r->p) - r->enc_zero; }

static void fault(Rig *r, unsigned bit)
{
    r->faults |= bit; r->state = FAULT; r->move_left = 0; r->v_cmd = 0.0;
    ENR312_Runner_Abort(&r->run, ENR312_RUN_ABORT_OPERATOR);
}

static void control_tick(Rig *r)
{
    r->ticks++;
    double ang = pend_deg(r), rot = rotor_deg(r);
    int running = ENR312_Runner_IsMoving(&r->run);
    if ((r->move_left > 0 || (running && r->run.cfg.exp != 5u)) && fabs(ang) > ENR312_PENDULUM_ABORT_DEG) {
        fault(r, F_PEND_ABORT);
    }
    if (fabs(rot) > ENR312_ROTOR_LIMIT_DEG) { fault(r, F_ROTOR_LIMIT); }
    running = ENR312_Runner_IsMoving(&r->run);
    if (running) {
        if (r->state != RUNNING) {
            ENR312_Runner_Abort(&r->run, ENR312_RUN_ABORT_OPERATOR);
        } else if (r->fd >= 0 && (uint32_t)(r->ticks - r->last_rx) > WATCHDOG_TICKS) {
            ENR312_Runner_Abort(&r->run, ENR312_RUN_ABORT_WATCHDOG);
            fault(r, F_OPERATOR);
        } else {
            double v = ENR312_Runner_Tick(&r->run, rot, ang);
            double rate = v * USTEP_PER_DEG;
            r->v_cmd = (fabs(rate) < 2.0) ? 0.0 : rate;   /* StepGen minimum rate */
        }
        if (!ENR312_Runner_IsMoving(&r->run)) { r->v_cmd = 0.0; }
    } else if (r->move_left <= 0) {
        r->v_cmd = 0.0;
    }
    /* operator's hand: holds the pendulum upright until the capture gate passes */
    if (r->hold_upright) {
        r->p.held = 1;
        if (running && r->run.cfg.exp == 5u && r->run.phase != EXP005_PHASE_WAIT_CAPTURE) {
            if (r->hold_after > 0) { r->hold_after--; }
            else { r->hold_upright = 0; r->p.held = 0; }
        }
    }
    for (int i = 0; i < SUB; ++i) {
        double rate = r->v_cmd;
        if (r->move_left > 0) { rate = 200.0 * r->move_dir; }
        int64_t before = r->p.pos;
        ENR312_Plant_Step(&r->p, rate, TS / SUB);
        if (r->move_left > 0) {
            int64_t d = r->p.pos - before; r->move_left -= (d < 0 ? -d : d);
            if (r->move_left <= 0) {
                r->p.pos -= (int64_t)r->move_dir * (-r->move_left);    /* exact count */
                r->move_left = 0;
            }
        }
    }
}

static void stream_line(Rig *r)
{
    int running = ENR312_Runner_IsMoving(&r->run);
    out(r, "D,%u,%ld,%ld,%u,%u,%s,%u,%u,%ld,%ld,%u\r\n", r->ticks, mdeg(rotor_deg(r)), mdeg(pend_deg(r)),
        (unsigned)((long)lround(pend_deg(r) / 0.15) & 0xFFFF), r->faults, STATE_NAME[r->state],
        running ? (unsigned)r->run.cfg.exp : 0u, (unsigned)r->run.phase,
        lround(r->run.u), mdeg(r->run.ref_deg), 25u);
}

static void report_runner(Rig *r)
{
    static ENR312_RunState_t ls = ENR312_RUN_IDLE; static uint8_t lp = 0xFF;
    if (r->run.state == ls && r->run.phase == lp) { return; }
    if (r->run.state == ENR312_RUN_ABORTED && ls != ENR312_RUN_ABORTED) {
        out(r, "RUN ABORTED EXP00%u reason=%s\r\n", r->run.cfg.exp, ENR312_Runner_AbortName(&r->run));
    } else if (r->run.state == ENR312_RUN_FINISHED && ls != ENR312_RUN_FINISHED) {
        out(r, "RUN FINISHED EXP00%u\r\n", r->run.cfg.exp);
    } else if (r->run.state == ENR312_RUN_ACTIVE) {
        out(r, "RUN EXP00%u phase=%s\r\n", r->run.cfg.exp, ENR312_Runner_PhaseName(&r->run));
    }
    ls = r->run.state; lp = r->run.phase;
}

static void process_line(Rig *r)
{
    char reply[96]; double mv = 0.0;
    ENR312_CmdAction_t a = ENR312_Cmd_Line(r->line, &r->cfg, &mv, reply, (int)sizeof reply);
    if (a == ENR312_CMD_GO) {
        if (r->state != RUNNING) { out(r, "ERR not RUNNING: ARM ('a') then START ('s') first\r\n"); }
        else if (ENR312_Runner_IsMoving(&r->run)) { out(r, "ERR an experiment is already running\r\n"); }
        else if (r->move_left > 0) { out(r, "ERR a move is in progress\r\n"); }
        else if (ENR312_Runner_Start(&r->run, &r->cfg)) { r->last_rx = r->ticks; out(r, "GO EXP00%u\r\n", r->cfg.exp); }
        else { out(r, "ERR configuration invalid ('$cfg')\r\n"); }
    } else if (a == ENR312_CMD_STOP) {
        ENR312_Runner_Stop(&r->run); out(r, "STOPPING (decelerating)\r\n");
    } else if (a == ENR312_CMD_MOVE) {
        out(r, "MOVE:\r\n");
        if (r->state != RUNNING) { out(r, "  refused: not RUNNING\r\n"); }
        else if (ENR312_Runner_IsMoving(&r->run) || r->move_left > 0) { out(r, "  refused: busy\r\n"); }
        else {
            r->move_left = llround(fabs(mv) * USTEP_PER_DEG); r->move_dir = mv >= 0 ? 1 : -1;
            out(r, "  %ld microsteps, dir %s, ARR 410 (200.07 Hz)\r\n", (long)(r->move_dir * r->move_left), mv >= 0 ? "+" : "-");
        }
    } else {
        out(r, "%s\r\n", reply);
    }
}

static const char *HELP =
    "\r\n--- ENR312 commands ---------------------------------------\r\n"
    "  ?  help   t  status   a  ARM   s  START   x  ABORT   c  clear fault\r\n"
    "  z  zero datums   +/-  first motion 5 deg   q  L6474 STATUS   r  stream\r\n"
    "  .  keep-alive (send at least once a second while an experiment runs)\r\n"
    "  $exp=N (2..5)  $kp= $kd= $kpp= $kdp= $step= $dist= $ulim= $vmax=\r\n"
    "  $cfg  $defaults  $go  $stop  $move=D   (closed-loop Tutorials 2-5)\r\n"
    "  EMULATOR ONLY:  !  pluck 30 deg    ^  hold the pendulum upright\r\n"
    "-----------------------------------------------------------\r\n";

static void key(Rig *r, char c)
{
    r->last_rx = r->ticks;
    if (r->line_len >= 0) {
        if (c == '\r' || c == '\n') { r->line[r->line_len] = '\0'; process_line(r); r->line_len = -1; }
        else if (r->line_len < (int)sizeof r->line - 1) { r->line[r->line_len++] = c; }
        return;
    }
    switch (c) {
    case '.': case '\r': case '\n': break;
    case '$': r->line_len = 0; break;
    case '?': out(r, "%s", HELP); break;
    case 't':
        out(r, "state=%s faults=0x%02X  rotor=%.3f deg  pend=%.3f deg  raw=0  pulses=0  ticks=%u  ovr=0  isr_max_us=25  run=%s/%s\r\n",
            STATE_NAME[r->state], r->faults, rotor_deg(r), pend_deg(r), r->ticks,
            ENR312_Runner_IsMoving(&r->run) ? "ACTIVE" : "IDLE", ENR312_Runner_PhaseName(&r->run));
        break;
    case 'a':
        out(r, "ARM: configuring L6474 over SPI...\r\n");
        if (r->state == SAFE) { r->state = ARMED; out(r, "  ARMED. Motor is energised and holding.\r\n"); }
        else { out(r, "  ARM FAILED. faults=0x%02X\r\n", r->faults); }
        break;
    case 's':
        if (r->state == ARMED) { r->state = RUNNING; out(r, "RUNNING. Motion permitted.\r\n"); }
        else { out(r, "  refused: must be ARMED first.\r\n"); }
        break;
    case 'x':
        ENR312_Runner_Abort(&r->run, ENR312_RUN_ABORT_OPERATOR);
        r->move_left = 0; r->v_cmd = 0.0;
        if (r->state != FAULT) { r->state = SAFE; }
        out(r, "ABORT -> SAFE.\r\n");
        break;
    case 'c': r->faults = 0; r->state = SAFE; out(r, "Faults cleared -> SAFE.\r\n"); break;
    case 'z':
        if (ENR312_Runner_IsMoving(&r->run) || r->move_left > 0) { out(r, "  refused: rotor is moving\r\n"); break; }
        r->enc_zero = ENR312_Plant_EncoderDeg(&r->p); r->rot_zero = r->p.pos; out(r, "Datums zeroed here.\r\n");
        break;
    case '+': case '-':
        out(r, "FIRST MOTION %c5 deg:\r\n", c);
        if (r->state != RUNNING) { out(r, "  refused: not RUNNING\r\n"); }
        else if (r->move_left > 0 || ENR312_Runner_IsMoving(&r->run)) { out(r, "  refused: move in progress\r\n"); }
        else { r->move_left = 44; r->move_dir = (c == '+') ? 1 : -1; out(r, "  %d microsteps, dir %c, ARR 410 (200.07 Hz)\r\n", 44 * r->move_dir, c); }
        break;
    case 'q': out(r, "L6474 STATUS = 0x%04X\r\n", (r->state == ARMED || r->state == RUNNING) ? 0x7E03 : 0x7E02); break;
    case 'r': r->stream = !r->stream; out(r, r->stream ? "STREAM ON\r\n" : "STREAM OFF\r\n"); break;
    case '!': r->p.psi += 30.0 * 3.14159265358979323846 / 180.0; out(r, "EMULATOR: pendulum plucked 30 deg.\r\n"); break;
    case '^':
        r->p.psi = (180.0 - 0.6) * 3.14159265358979323846 / 180.0 + r->enc_zero * 3.14159265358979323846 / 180.0;
        r->p.psid = 0.0; r->hold_upright = 1; r->p.held = 1;
        out(r, "EMULATOR: pendulum held upright by hand (released when EXP005 captures it).\r\n");
        break;
    default: out(r, "? unknown -- '?' for help\r\n"); break;
    }
}

static void rig_init(Rig *r, int fd)
{
    memset(r, 0, sizeof *r);
    ENR312_Plant_Init(&r->p, 56.4, 24.0, 0.803);   /* emulator "truth": deliberately not the Tutorial values */
    r->p.psi = 0.4 * 3.14159265358979323846 / 180.0;
    ENR312_Runner_Defaults(&r->cfg, 5u);
    r->run.state = ENR312_RUN_IDLE;
    r->line_len = -1; r->fd = fd; r->state = SAFE;
}

/* --parent PID: exit when that process (the MATLAB app) is gone. The emulator
 * holds its own pty slave open, so it never sees EIO when MATLAB crashes. */
static int run_pty(long parent)
{
    int m = posix_openpt(O_RDWR | O_NOCTTY);
    if (m < 0 || grantpt(m) || unlockpt(m)) { perror("pty"); return 1; }
    fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK);
    const char *sn = ptsname(m);
    int s = open(sn, O_RDWR | O_NOCTTY);                 /* keep the slave open: no EIO */
    struct termios t; tcgetattr(s, &t); cfmakeraw(&t); tcsetattr(s, TCSANOW, &t);
    printf("%s\n", sn); fflush(stdout);
    Rig r; rig_init(&r, m);
    out(&r, "\r\n===========================================================\r\n"
            " *** ENR312 RIG EMULATOR -- firmware logic, NOT HARDWARE *** \r\n"
            " ENR312 ROTARY INVERTED PENDULUM -- target firmware\r\n"
            " Firmware:      enr312-target-2.0.8 (protocol 2: closed-loop Tutorials 2-5, 115200 baud)\r\n"
            "\r\n THIS IS NOT THE VEHICLE FIRMWARE.\r\n"
            " State: SAFE. L6474 held in reset. No motion possible.\r\n"
            "===========================================================\r\n");
    out(&r, "%s", HELP);
    struct timespec t0; clock_gettime(CLOCK_MONOTONIC, &t0);
    uint32_t last_stream = 0;
    for (;;) {
        fd_set fs; FD_ZERO(&fs); FD_SET(m, &fs);
        struct timeval tv = {0, 1000};
        if (select(m + 1, &fs, NULL, NULL, &tv) > 0) {
            char b[128]; ssize_t n = read(m, b, sizeof b);
            if (n < 0 && errno != EAGAIN && errno != EINTR) { break; }
            for (ssize_t i = 0; i < n; ++i) { key(&r, b[i]); }
        }
        struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        double el = (double)(now.tv_sec - t0.tv_sec) + 1e-9 * (double)(now.tv_nsec - t0.tv_nsec);
        while ((double)r.ticks * TS < el) {
            control_tick(&r);
            if (r.stream && r.ticks - last_stream >= 10u) { last_stream = r.ticks; stream_line(&r); }
        }
        report_runner(&r);
        if (parent > 0 && (r.ticks % 250u) == 0u && kill((pid_t)parent, 0) != 0 && errno == ESRCH) { break; }
    }
    return 0;
}

static int run_batch(int argc, char **argv)
{
    Rig r; rig_init(&r, -1);
    double seconds = 20.0; int upright = 0, exp = 5;
    for (int i = 2; i < argc; ++i) {                     /* exp first, so defaults load */
        if (strncmp(argv[i], "exp=", 4) == 0) { exp = atoi(argv[i] + 4); }
    }
    ENR312_Runner_Defaults(&r.cfg, (uint8_t)exp);
    for (int i = 2; i < argc; ++i) {
        char rep[96]; double mv;
        if (strncmp(argv[i], "seconds=", 8) == 0) { seconds = atof(argv[i] + 8); continue; }
        if (strncmp(argv[i], "upright=", 8) == 0) { upright = atoi(argv[i] + 8); continue; }
        if (strncmp(argv[i], "release=", 8) == 0) { r.hold_after = (int)(atof(argv[i] + 8) / TS); continue; }
        if (strncmp(argv[i], "wg2=", 4) == 0) { r.p.wg2 = atof(argv[i] + 4); r.p.gamma = sqrt(r.p.wg2) / 24.0; continue; }
        if (strncmp(argv[i], "exp=", 4) == 0) { continue; }
        ENR312_Cmd_Line(argv[i], &r.cfg, &mv, rep, (int)sizeof rep);
        if (strncmp(rep, "ERR", 3) == 0) { fprintf(stderr, "%s: %s\n", argv[i], rep); return 2; }
    }
    if (exp == 2) { r.p.wr2 = 0.0; }                     /* pendulum removed */
    r.state = RUNNING;
    if (upright || exp == 5) { key(&r, '^'); }
    if (!ENR312_Runner_Start(&r.run, &r.cfg)) { fprintf(stderr, "invalid configuration\n"); return 2; }
    printf("t_s,rotor_deg,psi_deg,u,ref_deg,phase,run_state,abort\n");
    uint32_t n = (uint32_t)(seconds / TS);
    for (uint32_t i = 0; i < n; ++i) {
        printf("%.3f,%.4f,%.4f,%.3f,%.4f,%u,%d,%s\n", (double)r.ticks * TS, rotor_deg(&r), pend_deg(&r),
               r.run.u, r.run.ref_deg, r.run.phase, (int)r.run.state, ENR312_Runner_AbortName(&r.run));
        control_tick(&r);
        if (!ENR312_Runner_IsMoving(&r.run) && r.run.state != ENR312_RUN_ACTIVE) {
            if (r.run.state == ENR312_RUN_ABORTED || r.run.state == ENR312_RUN_FINISHED) {
                printf("%.3f,%.4f,%.4f,0,0,%u,%d,%s\n", (double)r.ticks * TS, rotor_deg(&r), pend_deg(&r),
                       r.run.phase, (int)r.run.state, ENR312_Runner_AbortName(&r.run));
                break;
            }
        }
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 2 && strcmp(argv[1], "--pty") == 0) {
        long parent = (argc >= 4 && strcmp(argv[2], "--parent") == 0) ? atol(argv[3]) : 0;
        return run_pty(parent);
    }
    if (argc >= 2 && strcmp(argv[1], "--batch") == 0) { return run_batch(argc, argv); }
    fprintf(stderr, "usage: %s --pty [--parent PID] | --batch [exp=N kp=.. kd=.. kpp=.. kdp=.. step=.. dist=.. ulim=.. vmax=.. seconds=..]\n", argv[0]);
    return 2;
}

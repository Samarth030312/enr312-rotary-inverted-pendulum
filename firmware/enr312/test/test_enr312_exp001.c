/**
 * @file test_enr312_exp001.c
 * @brief Host integration tests for the EXP001 sequencer, driven against a
 *        simulated encoder source.
 *
 * The sequencer is HAL-free specifically so that the entire experiment
 * sequence -- including its abort paths -- can be executed thousands of times
 * on a workstation before it is ever allowed to move a real motor. Every abort
 * branch below is exercised here, so no safety path reaches the rig having
 * never run.
 *
 * Covers acceptance criteria AC-7 and AC-8 (experiments/EXP001/VALIDATION.md).
 */

#include "enr312_exp001.h"
#include "test_harness.h"
#include <string.h>

/* --- Simulated encoder source ---------------------------------------------
 * Not a plant model. EXP001 has no plant model, by design (FIRST_PRINCIPLES
 * section 6). This is a programmable counter that lets the sequencer's logic
 * and safety behaviour be exercised deterministically. */
typedef struct {
    double   angle_deg;
    double   rate_deg_per_tick;
    uint16_t raw;
} SimEncoder_t;

static void sim_init(SimEncoder_t *s, uint16_t raw0, double rate_deg_per_tick)
{
    s->angle_deg = 0.0;
    s->rate_deg_per_tick = rate_deg_per_tick;
    s->raw = raw0;
}

static uint16_t sim_step(SimEncoder_t *s)
{
    s->angle_deg += s->rate_deg_per_tick;
    /* Convert absolute simulated angle to a raw 16-bit counter value. */
    long counts = (long)(s->angle_deg / ENR312_ENCODER_DEG_PER_COUNT);
    s->raw = (uint16_t)counts;
    return s->raw;
}

/* --- Dry run: the sequence must complete and command nothing --------------- */
static void test_dry_run_commands_no_motion(void)
{
    ENR312_Exp001_t x;
    SimEncoder_t s;
    ENR312_Exp001_Init(&x, 0u, /*armed=*/false);
    sim_init(&s, 0u, 0.0);

    uint32_t guard = 0u;
    while (!ENR312_Exp001_IsFinished(&x) && guard < 2000000u) {
        ENR312_Exp001_Tick(&x, sim_step(&s));
        guard++;
    }

    CHECK(guard < 2000000u, "dry run terminates (did not hit the guard)");
    CHECK_EQ_I(x.phase, EXP001_PHASE_DONE, "dry run reaches DONE, not ABORTED");
    CHECK_EQ_I(x.rotor.position_microsteps, 0,
               "dry run issues zero commanded motion");
    CHECK_EQ_I(x.abort_reason, EXP001_ABORT_NONE, "dry run does not abort");
    CHECK_EQ_I(x.p3_cycle, x.p3_cycles_target, "all P3 cycles completed");
}

/* --- Armed run against a still pendulum ----------------------------------- */
static void test_armed_run_reaches_all_setpoints(void)
{
    ENR312_Exp001_t x;
    SimEncoder_t s;
    ENR312_Exp001_Init(&x, 0u, /*armed=*/true);
    sim_init(&s, 0u, 0.0);

    /* Track which commanded arm angles were actually visited. */
    int saw_plus45 = 0, saw_minus90 = 0, saw_plus90 = 0, saw_minus90_p3 = 0;
    uint32_t guard = 0u;

    while (!ENR312_Exp001_IsFinished(&x) && guard < 2000000u) {
        const ENR312_Exp001Sample_t *r = ENR312_Exp001_Tick(&x, sim_step(&s));
        if (r->phase == EXP001_PHASE_STEP_P1) {
            if (r->rotor_cmd_microsteps ==  400) saw_plus45  = 1;
            if (r->rotor_cmd_microsteps == -800) saw_minus90 = 1;
        }
        if (r->phase == EXP001_PHASE_RETURN_P3) {
            if (r->rotor_cmd_microsteps ==  800) saw_plus90     = 1;
            if (r->rotor_cmd_microsteps == -800) saw_minus90_p3 = 1;
        }
        guard++;
    }

    CHECK_EQ_I(x.phase, EXP001_PHASE_DONE, "armed run reaches DONE");
    CHECK(saw_plus45,     "P1 visited +45 deg (400 microsteps)");
    CHECK(saw_minus90,    "P1 visited -90 deg (-800 microsteps)");
    CHECK(saw_plus90,     "P3 visited +90 deg (800 microsteps)");
    CHECK(saw_minus90_p3, "P3 visited -90 deg (-800 microsteps)");

    /* The decisive software check for P3: a closed sequence must leave the
     * commanded position at exactly zero. */
    CHECK_EQ_I(x.rotor.position_microsteps, 0,
               "commanded position returns to exactly zero after P3");
    CHECK_EQ_I(x.rotor.clamp_events, 0, "no travel limit was reached");
}

/* --- Safety: pendulum abort ------------------------------------------------ */
static void test_pendulum_limit_aborts(void)
{
    ENR312_Exp001_t x;
    SimEncoder_t s;
    ENR312_Exp001_Init(&x, 0u, /*armed=*/true);
    /* Rotate the simulated pendulum steadily past the +/-120 deg abort bound. */
    sim_init(&s, 0u, 0.05);   /* 0.05 deg/tick -> 120 deg after 2400 ticks */

    uint32_t guard = 0u;
    while (!ENR312_Exp001_IsFinished(&x) && guard < 2000000u) {
        ENR312_Exp001_Tick(&x, sim_step(&s));
        guard++;
    }

    CHECK_EQ_I(x.phase, EXP001_PHASE_ABORTED, "excursion aborts the run");
    CHECK_EQ_I(x.abort_reason, EXP001_ABORT_PENDULUM_LIMIT, "abort reason recorded");
    CHECK(fabs(x.last.pendulum_deg) > ENR312_PENDULUM_ABORT_DEG,
          "abort fired past the bound (%.2f deg)", x.last.pendulum_deg);
    /* The abort must be sticky: further ticks must not resurrect the sequence. */
    ENR312_Exp001_Tick(&x, sim_step(&s));
    CHECK_EQ_I(x.phase, EXP001_PHASE_ABORTED, "abort is sticky");
}

/* --- Safety: abort is checked even while idle and even when disarmed ------- */
static void test_abort_active_in_dry_run(void)
{
    ENR312_Exp001_t x;
    SimEncoder_t s;
    ENR312_Exp001_Init(&x, 0u, /*armed=*/false);
    sim_init(&s, 0u, 1.0);   /* 1 deg/tick: crosses 120 deg in 120 ticks */

    for (int i = 0; i < 500 && !ENR312_Exp001_IsFinished(&x); ++i) {
        ENR312_Exp001_Tick(&x, sim_step(&s));
    }
    CHECK_EQ_I(x.phase, EXP001_PHASE_ABORTED,
               "safety check runs during a dry run too");
    CHECK_EQ_I(x.abort_reason, EXP001_ABORT_PENDULUM_LIMIT, "reason recorded");
}

/* --- Safety: operator abort ------------------------------------------------ */
static void test_operator_abort(void)
{
    ENR312_Exp001_t x;
    SimEncoder_t s;
    ENR312_Exp001_Init(&x, 0u, true);
    sim_init(&s, 0u, 0.0);

    for (int i = 0; i < 100; ++i) { ENR312_Exp001_Tick(&x, sim_step(&s)); }
    CHECK_EQ_I(x.phase, EXP001_PHASE_IDLE, "still in IDLE after 100 ticks");

    ENR312_Exp001_Abort(&x);
    CHECK_EQ_I(x.phase, EXP001_PHASE_ABORTED, "operator abort takes effect");
    CHECK_EQ_I(x.abort_reason, EXP001_ABORT_OPERATOR, "operator reason recorded");

    int64_t frozen = x.rotor.position_microsteps;
    for (int i = 0; i < 10000; ++i) { ENR312_Exp001_Tick(&x, sim_step(&s)); }
    CHECK_EQ_I(x.rotor.position_microsteps, frozen,
               "no motion is commanded after abort");
}

/* --- Phase ordering -------------------------------------------------------- */
static void test_phase_order(void)
{
    ENR312_Exp001_t x;
    SimEncoder_t s;
    ENR312_Exp001_Init(&x, 0u, true);
    sim_init(&s, 0u, 0.0);

    uint8_t seen[8]; int n = 0;
    uint8_t prev = 255u;
    uint32_t guard = 0u;

    while (!ENR312_Exp001_IsFinished(&x) && guard < 2000000u) {
        const ENR312_Exp001Sample_t *r = ENR312_Exp001_Tick(&x, sim_step(&s));
        if (r->phase != prev) {
            if (n < 8) { seen[n++] = r->phase; }
            prev = r->phase;
        }
        guard++;
    }

    /* Five, not four: the tick that completes RETURN_P3 also emits a telemetry
     * record already tagged DONE, so DONE is an observed phase. */
    CHECK_EQ_I(n, 5, "exactly five distinct phases were observed");
    if (n >= 5) {
        CHECK_EQ_I(seen[0], EXP001_PHASE_IDLE,        "phase 0 = IDLE");
        CHECK_EQ_I(seen[1], EXP001_PHASE_SENSE_ONLY,  "phase 1 = SENSE_ONLY");
        CHECK_EQ_I(seen[2], EXP001_PHASE_STEP_P1,     "phase 2 = STEP_P1");
        CHECK_EQ_I(seen[3], EXP001_PHASE_RETURN_P3,   "phase 3 = RETURN_P3");
        CHECK_EQ_I(seen[4], EXP001_PHASE_DONE,        "phase 4 = DONE");
    }

    /* SENSE_ONLY must command nothing -- the operator is handling the pendulum
     * during that phase, so any arm motion there would be a hazard. */
    ENR312_Exp001_t y;
    SimEncoder_t t;
    ENR312_Exp001_Init(&y, 0u, true);
    sim_init(&t, 0u, 0.0);
    for (uint32_t i = 0; i < EXP001_IDLE_TICKS + EXP001_SENSE_ONLY_TICKS; ++i) {
        ENR312_Exp001_Tick(&y, sim_step(&t));
    }
    CHECK_EQ_I(y.rotor.position_microsteps, 0,
               "no arm motion commanded during IDLE or SENSE_ONLY");
}

/* --- Telemetry ------------------------------------------------------------- */
static void test_csv_format(void)
{
    ENR312_Exp001_t x;
    SimEncoder_t s;
    ENR312_Exp001_Init(&x, 0u, true);
    sim_init(&s, 0u, 0.0);
    const ENR312_Exp001Sample_t *r = ENR312_Exp001_Tick(&x, sim_step(&s));

    char buf[256];
    int n = ENR312_Exp001_FormatCsv(r, buf, (int)sizeof buf);
    CHECK(n > 0 && n < (int)sizeof buf, "CSV line fits the buffer (n=%d)", n);

    /* Field count must match the header, or the analysis script silently
     * mis-parses every column. */
    int header_commas = 0, line_commas = 0;
    const char *h = ENR312_Exp001_CsvHeader();
    for (const char *p = h;   *p; ++p) if (*p == ',') header_commas++;
    for (const char *p = buf; *p; ++p) if (*p == ',') line_commas++;
    CHECK_EQ_I(line_commas, header_commas, "CSV line field count matches header");
    CHECK_EQ_I(header_commas, 8, "header declares 9 fields");
}

int main(void)
{
    printf("EXP001 sequencer integration tests (parameter set %s)\n",
           ENR312_PARAMETER_SET_ID);

    test_dry_run_commands_no_motion();
    test_armed_run_reaches_all_setpoints();
    test_pendulum_limit_aborts();
    test_abort_active_in_dry_run();
    test_operator_abort();
    test_phase_order();
    test_csv_format();

    TEST_REPORT("test_enr312_exp001");
    return enr312_tests_failed == 0 ? 0 : 1;
}

/**
 * @file test_enr312_exp002.c
 * @brief Host integration tests for the EXP002 sensitivity sequencer.
 *
 * Every abort path is exercised here so that none first executes on hardware.
 */

#include "enr312_exp002.h"
#include "test_harness.h"

typedef struct { double y, v; } Plant_t;
static void plant_step(Plant_t *p, double u, double ts)
{
    p->y += ts * p->v + 0.5 * ts * ts * u;
    p->v += ts * u;
}

/* Run the sequencer against the discrete 1/s^2 plant model. */
static void run(ENR312_Exp002_t *x, uint32_t max_ticks, int *saw_ref, int *saw_dist)
{
    Plant_t p = {0.0, 0.0};
    const double ts = ENR312_CONTROL_PERIOD_S;
    if (saw_ref)  { *saw_ref = 0; }
    if (saw_dist) { *saw_dist = 0; }
    for (uint32_t i = 0; i < max_ticks && !ENR312_Exp002_IsFinished(x); ++i) {
        const ENR312_Exp002Sample_t *r = ENR312_Exp002_Tick(x, p.y, 0.0);
        if (saw_ref  && r->reference_deg != 0.0) { *saw_ref = 1; }
        if (saw_dist && r->disturbance   != 0.0) { *saw_dist = 1; }
        plant_step(&p, x->armed ? r->u : 0.0, ts);
    }
}

static void test_phase_order_and_completion(void)
{
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 5.0, 2.5, true);

    uint8_t seen[8]; int n = 0; uint8_t prev = 255u;
    Plant_t p = {0.0, 0.0};
    const double ts = ENR312_CONTROL_PERIOD_S;
    for (uint32_t i = 0; i < 200000u && !ENR312_Exp002_IsFinished(&x); ++i) {
        const ENR312_Exp002Sample_t *r = ENR312_Exp002_Tick(&x, p.y, 0.0);
        if (r->phase != prev) { if (n < 8) { seen[n++] = r->phase; } prev = r->phase; }
        plant_step(&p, r->u, ts);
    }

    CHECK_EQ_I(x.phase, EXP002_PHASE_DONE, "armed run reaches DONE");
    CHECK_EQ_I(x.abort_reason, EXP002_ABORT_NONE, "no abort on a nominal run");
    CHECK_EQ_I(n, 6, "six distinct phases observed");
    if (n >= 6) {
        CHECK_EQ_I(seen[0], EXP002_PHASE_IDLE,        "0 IDLE");
        CHECK_EQ_I(seen[1], EXP002_PHASE_REF_STEP,    "1 REF_STEP");
        CHECK_EQ_I(seen[2], EXP002_PHASE_REF_SETTLE,  "2 REF_SETTLE");
        CHECK_EQ_I(seen[3], EXP002_PHASE_DIST_STEP,   "3 DIST_STEP");
        CHECK_EQ_I(seen[4], EXP002_PHASE_DIST_SETTLE, "4 DIST_SETTLE");
        CHECK_EQ_I(seen[5], EXP002_PHASE_DONE,        "5 DONE");
    }
}

/* R and D must NEVER be non-zero at the same time, or T(s) and SD(s) cannot be
 * separated from one record. This is the single most important structural
 * property of the experiment. */
static void test_excitations_are_exclusive(void)
{
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 5.0, 2.5, true);
    Plant_t p = {0.0, 0.0};
    int both = 0, saw_r = 0, saw_d = 0;
    for (uint32_t i = 0; i < 200000u && !ENR312_Exp002_IsFinished(&x); ++i) {
        const ENR312_Exp002Sample_t *r = ENR312_Exp002_Tick(&x, p.y, 0.0);
        if (r->reference_deg != 0.0 && r->disturbance != 0.0) { both++; }
        if (r->reference_deg != 0.0) { saw_r = 1; }
        if (r->disturbance   != 0.0) { saw_d = 1; }
        plant_step(&p, r->u, ENR312_CONTROL_PERIOD_S);
    }
    CHECK_EQ_I(both, 0, "R and D are never simultaneously non-zero");
    CHECK(saw_r, "a reference step was actually applied");
    CHECK(saw_d, "a disturbance step was actually applied");
}

static void test_dry_run_commands_nothing(void)
{
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 5.0, 2.5, /*armed=*/false);
    int r = 0, d = 0;
    run(&x, 200000u, &r, &d);
    CHECK_EQ_I(x.phase, EXP002_PHASE_DONE, "dry run completes");
    CHECK(r && d, "dry run still exercises both excitations");
    CHECK_EQ_I(x.rotor.position_microsteps, 0, "dry run commands no rotor motion");
}

static void test_saturation_abort(void)
{
    /* Absurd gain with a tiny output limit -> sustained saturation -> abort. */
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 1e6, 0.0, true);
    ENR312_PD_SetOutputLimit(&x.pd, 1.0);
    ENR312_Exp002_SetExcitation(&x, 10.0, 0.0);
    Plant_t p = {0.0, 0.0};
    for (uint32_t i = 0; i < 200000u && !ENR312_Exp002_IsFinished(&x); ++i) {
        const ENR312_Exp002Sample_t *s = ENR312_Exp002_Tick(&x, p.y, 0.0);
        plant_step(&p, s->u, ENR312_CONTROL_PERIOD_S);
    }
    CHECK_EQ_I(x.phase, EXP002_PHASE_ABORTED, "sustained saturation aborts");
    CHECK_EQ_I(x.abort_reason, EXP002_ABORT_SATURATION, "reason recorded");
}

static void test_rotor_limit_abort(void)
{
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 5.0, 2.5, true);
    /* Feed a measured rotor angle beyond the travel limit. */
    for (int i = 0; i < 10 && !ENR312_Exp002_IsFinished(&x); ++i) {
        ENR312_Exp002_Tick(&x, ENR312_ROTOR_LIMIT_DEG + 5.0, 0.0);
    }
    CHECK_EQ_I(x.phase, EXP002_PHASE_ABORTED, "rotor limit aborts");
    CHECK_EQ_I(x.abort_reason, EXP002_ABORT_ROTOR_LIMIT, "reason recorded");
}

static void test_operator_abort_is_sticky_and_zeroes_output(void)
{
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 5.0, 2.5, true);
    for (int i = 0; i < 100; ++i) { ENR312_Exp002_Tick(&x, 0.0, 0.0); }
    ENR312_Exp002_Abort(&x);
    CHECK_EQ_I(x.phase, EXP002_PHASE_ABORTED, "operator abort takes effect");
    CHECK_EQ_I(x.abort_reason, EXP002_ABORT_OPERATOR, "reason recorded");
    const ENR312_Exp002Sample_t *s = ENR312_Exp002_Tick(&x, 5.0, 0.0);
    CHECK_NEAR(s->u, 0.0, 1e-12, "plant input is zeroed after abort");
    CHECK_EQ_I(x.phase, EXP002_PHASE_ABORTED, "abort is sticky");
}

static void test_abort_active_when_disarmed(void)
{
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 5.0, 2.5, /*armed=*/false);
    for (int i = 0; i < 10 && !ENR312_Exp002_IsFinished(&x); ++i) {
        ENR312_Exp002_Tick(&x, ENR312_ROTOR_LIMIT_DEG + 5.0, 0.0);
    }
    CHECK_EQ_I(x.phase, EXP002_PHASE_ABORTED,
               "safety checks run during a dry run too");
}

static void test_csv_format(void)
{
    ENR312_Exp002_t x;
    ENR312_Exp002_Init(&x, 5.0, 2.5, true);
    const ENR312_Exp002Sample_t *r = ENR312_Exp002_Tick(&x, 0.0, 0.0);
    char buf[256];
    int n = ENR312_Exp002_FormatCsv(r, buf, (int)sizeof buf);
    CHECK(n > 0 && n < (int)sizeof buf, "CSV line fits (n=%d)", n);
    int hc = 0, lc = 0;
    for (const char *p = ENR312_Exp002_CsvHeader(); *p; ++p) { if (*p == ',') hc++; }
    for (const char *p = buf; *p; ++p) { if (*p == ',') lc++; }
    CHECK_EQ_I(lc, hc, "CSV field count matches header");
    CHECK_EQ_I(hc, 9, "header declares 10 fields");
}

int main(void)
{
    printf("EXP002 sequencer integration tests (parameter set %s)\n",
           ENR312_PARAMETER_SET_ID);
    test_phase_order_and_completion();
    test_excitations_are_exclusive();
    test_dry_run_commands_nothing();
    test_saturation_abort();
    test_rotor_limit_abort();
    test_operator_abort_is_sticky_and_zeroes_output();
    test_abort_active_when_disarmed();
    test_csv_format();
    TEST_REPORT("test_enr312_exp002");
    return enr312_tests_failed == 0 ? 0 : 1;
}

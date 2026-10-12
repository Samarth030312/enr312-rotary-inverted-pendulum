/**
 * @file test_enr312_runner.c
 * @brief Host tests: the closed-loop runner around a NONLINEAR plant driven by
 *        the step train (host/enr312_plant.c), at the firmware's 500 Hz.
 *
 * What this proves: the same runner code that will run on the STM32 closes the
 * loop for Tutorials 2, 3 and 5, reproduces the Tutorial predictions within
 * tolerance, never drops the inverted pendulum at the end of the sequence,
 * and aborts on the faults that matter (wrong pendulum sign, speed ceiling).
 * What it does NOT prove: anything about the real rig.
 */
#include "enr312_runner.h"
#include "enr312_plant.h"
#include "test_harness.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

#define TS      ENR312_CONTROL_PERIOD_S
#define SUB     4
#define USTEP_PER_DEG ((double)ENR312_ROTOR_MICROSTEPS_PER_REV / 360.0)

/* One control period: measure, runner, then the plant evolves for Ts. */
static double run_tick(ENR312_Runner_t *r, ENR312_Plant_t *p, double psi_sign)
{
    double v = ENR312_Runner_Tick(r, ENR312_Plant_RotorDeg(p),
                                  psi_sign * ENR312_Plant_EncoderDeg(p));
    for (int i = 0; i < SUB; ++i) {
        ENR312_Plant_Step(p, v * USTEP_PER_DEG, TS / SUB);
    }
    return v;
}

static void test_defaults_and_validation(void)
{
    ENR312_RunnerConfig_t c;
    for (uint8_t e = 2; e <= 5; ++e) {
        ENR312_Runner_Defaults(&c, e);
        CHECK(ENR312_Runner_Validate(&c) == NULL, "defaults for EXP00%u valid", e);
    }
    ENR312_Runner_Defaults(&c, 5); c.kp = 200.0;
    CHECK(ENR312_Runner_Validate(&c) != NULL, "kp 200 rejected");
    ENR312_Runner_Defaults(&c, 5); c.u_limit = 2000.0;
    CHECK(ENR312_Runner_Validate(&c) != NULL, "EXP005 ulim above 1500 rejected");
    ENR312_Runner_Defaults(&c, 5); c.exp = 6;
    CHECK(ENR312_Runner_Validate(&c) != NULL, "exp 6 rejected");
    ENR312_Runner_t r; ENR312_Runner_Defaults(&c, 2); c.step_deg = 99.0;
    CHECK(!ENR312_Runner_Start(&r, &c), "invalid config does not start");
}

static void test_upright_angle(void)
{
    CHECK_NEAR(ENR312_Runner_UprightAngle(180.0), 0.0, 1e-12, "upright");
    CHECK_NEAR(ENR312_Runner_UprightAngle(178.0), 2.0, 1e-12, "psi 178 -> alpha +2");
    CHECK_NEAR(ENR312_Runner_UprightAngle(182.0), -2.0, 1e-12, "psi 182 -> alpha -2");
    CHECK_NEAR(ENR312_Runner_UprightAngle(-179.0), -1.0, 1e-12, "raised the other way");
    CHECK_NEAR(fabs(ENR312_Runner_UprightAngle(0.0)), 180.0, 1e-12, "hanging = 180");
}

static void test_exp002_tracking_and_disturbance(void)
{
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, 2);
    ENR312_Plant_Init(&p, 57.01, 27.0, 0.0);          /* pendulum removed */
    CHECK(ENR312_Runner_Start(&r, &c), "EXP002 starts");
    double peak = 0.0, dist_end = 0.0;
    uint32_t n = 0;
    while (r.state != ENR312_RUN_FINISHED && r.state != ENR312_RUN_ABORTED && n < 20000u) {
        run_tick(&r, &p, 1.0);
        double th = ENR312_Plant_RotorDeg(&p);
        if (r.phase == EXP002_PHASE_REF_STEP && th > peak) { peak = th; }
        if (r.phase == EXP002_PHASE_DIST_STEP) { dist_end = th; }
        n++;
    }
    CHECK_EQ_I(r.state, ENR312_RUN_FINISHED, "EXP002 completes (abort %s)", ENR312_Runner_AbortName(&r));
    double os = 100.0 * (peak / c.step_deg - 1.0);
    printf("  EXP002: overshoot %.1f %% (Tutorial 2: 26.76 %%), D-step offset %.3f deg (1/Kp = %.3f)\n",
           os, dist_end, c.dist / c.kp);
    CHECK_NEAR(os, 26.76, 8.0, "overshoot near Tutorial 2 within discretisation");
    CHECK_NEAR(dist_end, c.dist / c.kp, 0.12, "load disturbance leaves 1/Kp offset");
    CHECK_NEAR(r.v_deg_s, 0.0, 1e-12, "at rest when finished");
}

static void test_exp003_suspended(void)
{
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, 3);
    ENR312_Plant_Init(&p, 57.01, 27.0, 0.803);
    CHECK(ENR312_Runner_Start(&r, &c), "EXP003 starts");
    uint32_t n = 0;
    double end_of_step = 0.0;
    while (r.state != ENR312_RUN_FINISHED && r.state != ENR312_RUN_ABORTED && n < 20000u) {
        run_tick(&r, &p, 1.0); n++;
        if (r.phase == EXP003_PHASE_ROTOR_STEP) { end_of_step = ENR312_Plant_RotorDeg(&p); }
    }
    printf("  EXP003: rotor at end of step %.3f deg, final %.3f deg, pendulum %.2f deg\n",
           end_of_step, ENR312_Plant_RotorDeg(&p), ENR312_Plant_EncoderDeg(&p));
    CHECK_EQ_I(r.state, ENR312_RUN_FINISHED, "EXP003 completes (abort %s)", ENR312_Runner_AbortName(&r));
    CHECK_NEAR(end_of_step, c.step_deg, 0.3, "rotor reaches the step");
    CHECK_NEAR(ENR312_Plant_RotorDeg(&p), 0.0, 0.3, "reference returns to 0 in SETTLE");
    CHECK(fabs(ENR312_Plant_EncoderDeg(&p)) < 0.6, "pendulum settles near hanging");
}

/* operator holds the pendulum upright until the capture gate releases it */
static int run_exp005(ENR312_Runner_t *r, ENR312_Plant_t *p, const ENR312_RunnerConfig_t *c,
                      double seconds, double psi_sign, double *min_rotor_after_step)
{
    ENR312_Plant_Init(p, 55.85, 20.0, 0.803);
    p->psi = (180.0 - 0.6) * 3.14159265358979323846 / 180.0;   /* alpha = +0.6 deg */
    p->held = true;
    if (!ENR312_Runner_Start(r, c)) { return -1; }
    *min_rotor_after_step = 0.0;
    uint32_t n = (uint32_t)(seconds / TS);
    for (uint32_t i = 0; i < n && ENR312_Runner_IsMoving(r); ++i) {
        if (r->phase != EXP005_PHASE_WAIT_CAPTURE) { p->held = false; }
        run_tick(r, p, psi_sign);
        if (r->phase == EXP005_PHASE_ROTOR_STEP) {
            double th = ENR312_Plant_RotorDeg(p);
            if (th < *min_rotor_after_step) { *min_rotor_after_step = th; }
        }
    }
    return 0;
}

static void test_exp005_balances_and_holds(void)
{
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p; double mn;
    ENR312_Runner_Defaults(&c, 5);
    CHECK(run_exp005(&r, &p, &c, 25.0, 1.0, &mn) == 0, "EXP005 starts");
    double alpha = ENR312_Runner_UprightAngle(ENR312_Plant_EncoderDeg(&p));
    printf("  EXP005: after 25 s state=%s phase=%s alpha=%.2f deg rotor=%.2f deg, min rotor in step %.3f deg\n",
           r.state == ENR312_RUN_ACTIVE ? "ACTIVE" : "stopped", ENR312_Runner_PhaseName(&r),
           alpha, ENR312_Plant_RotorDeg(&p), mn);
    CHECK_EQ_I(r.state, ENR312_RUN_ACTIVE, "still balancing after the sequence (%s)", ENR312_Runner_AbortName(&r));
    CHECK_EQ_I(r.phase, EXP005_PHASE_DONE, "sequence complete, holding");
    CHECK(fabs(alpha) < 2.0, "pendulum upright at the end");
    CHECK(mn < -0.2, "rotor moved the WRONG way first (non-minimum-phase zero)");
    ENR312_Runner_Stop(&r);
    for (int i = 0; i < 2000 && ENR312_Runner_IsMoving(&r); ++i) { run_tick(&r, &p, 1.0); }
    CHECK_EQ_I(r.state, ENR312_RUN_FINISHED, "operator stop decelerates to rest");
}

static void test_exp005_wrong_sign_aborts(void)
{
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p; double mn;
    ENR312_Runner_Defaults(&c, 5);
    /* encoder polarity wrong: alpha is seen with the opposite sign */
    run_exp005(&r, &p, &c, 10.0, -1.0, &mn);
    CHECK_EQ_I(r.state, ENR312_RUN_ABORTED, "wrong pendulum sign aborts");
    CHECK(strcmp(ENR312_Runner_AbortName(&r), "PENDULUM_LOST") == 0, "reason %s", ENR312_Runner_AbortName(&r));
    CHECK_NEAR(r.v_deg_s, 0.0, 1e-12, "velocity zero on abort");
}

static void test_velocity_ceiling_aborts(void)
{
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, 2); c.step_deg = 20.0; c.v_max = 10.0;
    ENR312_Plant_Init(&p, 57.01, 27.0, 0.0);
    ENR312_Runner_Start(&r, &c);
    for (int i = 0; i < 5000 && ENR312_Runner_IsMoving(&r); ++i) { run_tick(&r, &p, 1.0); }
    CHECK_EQ_I(r.state, ENR312_RUN_ABORTED, "held speed ceiling aborts");
    CHECK(strcmp(ENR312_Runner_AbortName(&r), "VELOCITY_LIMIT") == 0, "reason %s", ENR312_Runner_AbortName(&r));
}

static void test_operator_abort(void)
{
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, 3); ENR312_Plant_Init(&p, 57.01, 27.0, 0.803);
    ENR312_Runner_Start(&r, &c);
    for (int i = 0; i < 800; ++i) { run_tick(&r, &p, 1.0); }
    ENR312_Runner_Abort(&r, ENR312_RUN_ABORT_OPERATOR);
    CHECK_EQ_I(r.state, ENR312_RUN_ABORTED, "abort");
    CHECK_NEAR(run_tick(&r, &p, 1.0), 0.0, 1e-12, "no motion after abort");
}

int main(void)
{
    printf("Closed-loop runner tests (nonlinear plant, 500 Hz, step-train arm)\n");
    test_defaults_and_validation();
    test_upright_angle();
    test_exp002_tracking_and_disturbance();
    test_exp003_suspended();
    test_exp005_balances_and_holds();
    test_exp005_wrong_sign_aborts();
    test_velocity_ceiling_aborts();
    test_operator_abort();
    TEST_REPORT("test_enr312_runner");
    return enr312_tests_failed ? 1 : 0;
}

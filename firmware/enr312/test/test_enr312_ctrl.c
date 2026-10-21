/**
 * @file test_enr312_ctrl.c
 * @brief Host tests for the general controller core (Tutorials 6-10, PEND).
 *
 * Unit level: Tutorial gain values, sign conventions, the capture and release
 * wait, Tutorial 7 impulse timing, integral action, anti-windup, the
 * state-feedback law, on-off control, loop decimation, the moving average,
 * live gain and set-point changes.
 * Closed loop: every experiment run by the runner against the nonlinear plant
 * (host/enr312_plant.c) completes its sequence without an abort.
 * What this does NOT prove: anything about the real rig.
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
#define DEG     (3.14159265358979323846 / 180.0)

static void test_tutorial_values(void)
{
    ENR312_CtrlConfig_t c;
    for (uint8_t e = 6; e <= 10; ++e) {
        CHECK(ENR312_Ctrl_Defaults(&c, e) && ENR312_Ctrl_Validate(&c) == NULL, "exp %u defaults valid", e);
    }
    for (uint8_t e = 21; e <= 23; ++e) {
        CHECK(ENR312_Ctrl_Defaults(&c, e) && ENR312_Ctrl_Validate(&c) == NULL, "exp %u defaults valid", e);
    }
    CHECK(!ENR312_Ctrl_Defaults(&c, 24), "exp 24 (swing-up) is not run on the rig");
    ENR312_Ctrl_Defaults(&c, 6);
    /* Tutorial 6 states Ki = Kp/Ti = 5 for Kp 15, Ti 5 s; that is 3 (its own table). */
    CHECK_NEAR(c.ki, c.kp / 5.0, 1e-12, "Tutorial 6: Ki = Kp/Ti = 15/5 = 3");
    CHECK_NEAR(c.kd, c.kp * 0.5, 1e-12, "Tutorial 6: Kd = Kp Td = 7.5");
    ENR312_Ctrl_Defaults(&c, 8);
    CHECK_NEAR(c.ki, 15.0 / 2.0, 1e-12, "Tutorial 8: Ti = 2 s -> Ki 7.5");
    ENR312_Ctrl_Defaults(&c, 7);
    CHECK_NEAR(c.ki, 0.0, 1e-12, "Tutorial 7: rotor Ki fixed at 0");
    CHECK_NEAR(c.imp_deg, 10.0, 1e-12, "Tutorial 7: 10 deg impulse");
    CHECK_NEAR(c.fdr, 50.0, 1e-12, "Tutorial 7: rotor derivative filtered at 50 Hz");
    ENR312_Ctrl_Defaults(&c, 9);
    CHECK(c.k1 == 1.0 && c.k2 == 2.0, "Tutorial 9: wN 1, zeta 1 -> K = [1 2]");
    ENR312_Ctrl_Defaults(&c, 10);
    CHECK_NEAR(c.k2, sqrt(3.0), 1e-4, "Tutorial 10: LQR Q=I R=1 -> k2 = sqrt(3)");
    CHECK(ENR312_Ctrl_Inverted(6) && !ENR312_Ctrl_Inverted(9) && !ENR312_Ctrl_Inverted(21), "modes");
}

static void test_signs(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    /* suspended dual PID, proportional only: e = ref - theta = +1 -> u = +kp */
    ENR312_Ctrl_Defaults(&c, 21); c.kp = 2.0; c.kd = 0.0; c.kpp = 0.0; c.kdp = 0.0;
    ENR312_Ctrl_Init(&x, &c);
    double u = ENR312_Ctrl_Tick(&x, -1.0, 0.0, 0.0);
    CHECK_NEAR(u, 2.0, 1e-12, "suspended: u = +u_rotor");
    /* inverted: same error, rotor branch negated (Tutorial 5 outer-loop sign) */
    ENR312_Ctrl_Defaults(&c, 6); c.kp = 2.0; c.ki = 0.0; c.kd = 0.0; c.kpp = 0.0; c.kdp = 0.0;
    ENR312_Ctrl_Init(&x, &c);
    x.phase = CTRL_PH_HOLD;
    u = ENR312_Ctrl_Tick(&x, -1.0, 0.0, 180.0);
    CHECK_NEAR(u, -2.0, 1e-12, "inverted: u = -u_rotor");
    /* inverted pendulum PD on alpha = 180 - psi: alpha = +1 -> u = -kpp */
    ENR312_Ctrl_Defaults(&c, 6); c.kp = 0.0; c.ki = 0.0; c.kd = 0.0; c.kpp = 100.0; c.kdp = 0.0;
    ENR312_Ctrl_Init(&x, &c);
    x.phase = CTRL_PH_HOLD;
    u = ENR312_Ctrl_Tick(&x, 0.0, 0.0, 179.0);
    CHECK_NEAR(u, -100.0, 1e-9, "inverted pendulum: alpha +1 deg -> u = -kpp");
}

static void test_waits_for_capture_and_release(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 6);
    ENR312_Ctrl_Init(&x, &c);
    double umax = 0.0;
    for (int i = 0; i < 5000; ++i) {                        /* 10 s held at alpha 0.6 */
        double u = ENR312_Ctrl_Tick(&x, 0.0, 0.0, 179.4 + 0.9 * ((i / 50) % 2));
        if (fabs(u) > umax) { umax = fabs(u); }
    }
    CHECK_EQ_I(x.phase, CTRL_PH_WAIT_RELEASE, "captured, now waiting for the hand");
    CHECK_NEAR(umax, 0.0, 1e-12, "motor still while held (max |u| %.3f)", umax);
    ENR312_Ctrl_Tick(&x, 0.0, 0.0, 179.4 - CTRL_RELEASE_DEG);    /* falls on its own */
    CHECK_EQ_I(x.phase, CTRL_PH_BALANCE, "release detected");
}

static void test_impulses(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 7);
    ENR312_Ctrl_Init(&x, &c);
    x.phase = CTRL_PH_IMPULSES; x.phase_tick = 0u;
    int n_ticks = 0, n_edges = 0; double last = 0.0;
    for (int i = 0; i < 25000 && x.phase == CTRL_PH_IMPULSES; ++i) {
        ENR312_Ctrl_Tick(&x, 0.0, 0.0, 180.0);
        if (x.pend_ref != 0.0) { n_ticks++; if (last == 0.0) { n_edges++; } }
        last = x.pend_ref;
    }
    CHECK_EQ_I(n_edges, 8, "Tutorial 7: 8 impulses");
    CHECK_EQ_I(n_ticks, 16, "each impulse lasts 2 ticks = 4 ms");
    CHECK_EQ_I(x.phase, CTRL_PH_HOLD, "then HOLD");
}

/* double integrator theta'' = u + bias, under the suspended dual PID (pendulum
 * gains 0) in REGULATE: integral action removes the steady error of a load */
static double regulate_error(double ki, double bias)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 21); c.kp = 15.0; c.ki = ki; c.kd = 7.5; c.kpp = 0.0; c.kdp = 0.0;
    ENR312_Ctrl_Init(&x, &c);
    double th = 0.0, v = 0.0;
    for (int i = 0; i < 30000; ++i) {
        double u = ENR312_Ctrl_Tick(&x, th, v, 0.0);
        v += (u + bias) * TS; th += v * TS;
    }
    return th;
}

static void test_integral_action(void)
{
    double e0 = regulate_error(0.0, 15.0), e1 = regulate_error(7.5, 15.0);
    CHECK_NEAR(e0, 15.0 / 15.0, 0.02, "PD: load leaves D/Kp = 1 deg (got %.3f)", e0);
    CHECK_NEAR(e1, 0.0, 0.01, "PID: integral action removes it (got %.4f)", e1);
}

static void test_antiwindup(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 21); c.kp = 1.0; c.ki = 50.0; c.kd = 0.0; c.kpp = 0.0; c.kdp = 0.0;
    c.u_limit = 100.0;
    ENR312_Ctrl_Init(&x, &c);
    for (int i = 0; i < 20000; ++i) { ENR312_Ctrl_Tick(&x, -50.0, 0.0, 0.0); }   /* stuck arm */
    CHECK(fabs(x.ir) <= 100.0, "integral bounded by the actuator limit (%.1f)", x.ir);
}

static void test_state_feedback_law(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 9); c.k1 = 1.0; c.k2 = 2.0; c.k3 = 0.0; c.k4 = 0.0; c.bv = 0.5;
    ENR312_Ctrl_Init(&x, &c);
    double u = ENR312_Ctrl_Tick(&x, 2.0, 3.0, 0.0);              /* IDLE: ref 0 */
    CHECK_NEAR(u, -(1.0 * 2.0 + 2.0 * 3.0) - 0.5 * 3.0, 1e-12, "u = -(k1 e + k2 thdot) - b thdot");
}

static void test_on_off(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 22);
    ENR312_Ctrl_Init(&x, &c);
    CHECK_NEAR(ENR312_Ctrl_Tick(&x, -1.0, 0.0, 0.0), c.uon, 1e-12, "error +1 > db: +uon");
    CHECK_NEAR(ENR312_Ctrl_Tick(&x, 0.2, 0.0, 0.0), 0.0, 1e-12, "inside the dead band: 0");
    CHECK_NEAR(ENR312_Ctrl_Tick(&x, 1.0, 0.0, 0.0), -c.uon, 1e-12, "error -1: -uon");
}

static void test_decimation_and_ma(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 21); c.kp = 1.0; c.kd = 0.0; c.kpp = 0.0; c.kdp = 0.0; c.div = 5u;
    ENR312_Ctrl_Init(&x, &c);
    double u0 = ENR312_Ctrl_Tick(&x, -1.0, 0.0, 0.0);
    int same = 1;
    for (int i = 1; i < 5; ++i) { if (ENR312_Ctrl_Tick(&x, -2.0 - i, 0.0, 0.0) != u0) { same = 0; } }
    CHECK(same, "div 5: u held for 5 ticks (zero-order hold at 100 Hz)");
    CHECK(ENR312_Ctrl_Tick(&x, -9.0, 0.0, 0.0) != u0, "updated on the 6th tick");

    ENR312_Ctrl_Defaults(&c, 21); c.ma = 4u;
    ENR312_Ctrl_Init(&x, &c);
    const double ps[] = {4.0, 8.0, 0.0, 4.0, 12.0};
    for (int i = 0; i < 5; ++i) { ENR312_Ctrl_Tick(&x, 0.0, 0.0, ps[i]); }
    CHECK_NEAR(x.a_meas, (8.0 + 0.0 + 4.0 + 12.0) / 4.0, 1e-12, "moving average of the last 4");
}

static void test_live_changes(void)
{
    ENR312_CtrlConfig_t c, d; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 21);
    ENR312_Ctrl_Init(&x, &c);
    d = c; d.kp = 9.0; d.step_deg = 33.0;
    ENR312_Ctrl_SetGains(&x, &d);
    CHECK(x.c.kp == 9.0 && x.c.step_deg == c.step_deg, "gains change live, the sequence does not");
    ENR312_Ctrl_SetRef(&x, 10.0);
    ENR312_Ctrl_Tick(&x, 0.0, 0.0, 0.0);
    CHECK_NEAR(x.ref, c.ref_rate * TS, 1e-12, "set-point slews at ref_rate");
    for (int i = 0; i < 1000; ++i) { ENR312_Ctrl_Tick(&x, 0.0, 0.0, 0.0); }
    CHECK_NEAR(x.ref, 10.0, 1e-9, "and arrives");
}

/* ---- closed loop: runner + nonlinear plant ------------------------------- */
static int run_closed_loop(uint8_t exp, double seconds, double psi0_deg, bool hand, double *alpha_end)
{
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, exp);
    ENR312_Plant_Init(&p, 55.85, 20.0, 0.803);
    p.psi = psi0_deg * DEG;
    p.held = hand;
    if (!ENR312_Runner_Start(&r, &c)) { return -1; }
    uint32_t n = (uint32_t)(seconds / TS);
    for (uint32_t i = 0; i < n && ENR312_Runner_IsMoving(&r); ++i) {
        if (hand && r.phase != CTRL_PH_WAIT_CAPTURE) { p.held = false; }
        double v = ENR312_Runner_Tick(&r, ENR312_Plant_RotorDeg(&p), ENR312_Plant_EncoderDeg(&p));
        for (int k = 0; k < SUB; ++k) { ENR312_Plant_Step(&p, v * USTEP_PER_DEG, TS / SUB); }
    }
    *alpha_end = ENR312_Runner_UprightAngle(ENR312_Plant_EncoderDeg(&p));
    return (r.state == ENR312_RUN_ABORTED) ? 1 : 0;
}

static void test_closed_loop_all(void)
{
    const struct { uint8_t exp; double s, psi0; bool hand, inv; } t[] = {
        {6, 70, 179.4, true, true}, {7, 60, 179.4, true, true}, {8, 70, 179.4, true, true},
        {9, 40, 0.4, false, false}, {10, 40, 0.4, false, false}, {21, 30, 30.0, false, false},
        {22, 40, 0.4, false, false}, {23, 50, 179.4, true, true}};
    for (unsigned i = 0; i < sizeof t / sizeof t[0]; ++i) {
        double a = 0.0;
        int rc = run_closed_loop(t[i].exp, t[i].s, t[i].psi0, t[i].hand, &a);
        CHECK_EQ_I(rc, 0, "exp %u runs its sequence without an abort", t[i].exp);
        if (t[i].inv) { CHECK(fabs(a) < 2.0, "exp %u still balancing at the end (alpha %.2f)", t[i].exp, a); }
    }
}

int main(void)
{
    printf("General controller core tests (Tutorials 6-10, PEND experiments)\n");
    test_tutorial_values();
    test_signs();
    test_waits_for_capture_and_release();
    test_impulses();
    test_integral_action();
    test_antiwindup();
    test_state_feedback_law();
    test_on_off();
    test_decimation_and_ma();
    test_live_changes();
    test_closed_loop_all();
    TEST_REPORT("test_enr312_ctrl");
    return enr312_tests_failed ? 1 : 0;
}

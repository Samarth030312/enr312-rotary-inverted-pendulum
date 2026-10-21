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
    for (uint8_t e = 21; e <= 24; ++e) {
        CHECK(ENR312_Ctrl_Defaults(&c, e) && ENR312_Ctrl_Validate(&c) == NULL, "exp %u defaults valid", e);
    }
    CHECK(!ENR312_Ctrl_Defaults(&c, 25), "exp 25 does not exist");
    ENR312_Ctrl_Defaults(&c, 24);
    CHECK(c.seq == 1u && fabs(c.wg2 - 55.85) < 1e-12, "seq 1, wg2 = Tutorial 5 by default");
    c.seq = 2u; CHECK(ENR312_Ctrl_Validate(&c) != NULL, "seq 2 rejected");
    c.seq = 0u; c.wg2 = 10.0; CHECK(ENR312_Ctrl_Validate(&c) != NULL, "wg2 10 rejected");
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
    /* in HOLD the auto-trim has learnt TS/tau of the angle after one tick */
    CHECK_NEAR(u, -100.0 * (1.0 - TS / CTRL_TRIM_TAU_S), 1e-9, "inverted pendulum: alpha +1 deg -> u = -kpp (alpha - trim)");
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

/* ---- lab mode (seq 0) and swing-up (exp 24), closed loop -------------------- */
static void test_lab_mode(void)
{
    ENR312_CtrlConfig_t c; ENR312_Ctrl_t x;
    ENR312_Ctrl_Defaults(&c, 9); c.seq = 0u;
    ENR312_Ctrl_Init(&x, &c);
    CHECK_EQ_I(x.phase, CTRL_PH_REGULATE, "lab: hanging state feedback regulates at once");
    ENR312_Ctrl_SetRef(&x, 30.0);
    for (int i = 0; i < 2000; ++i) { ENR312_Ctrl_Tick(&x, 0.0, 0.0, 0.0); }
    CHECK_NEAR(x.ref, 30.0, 1e-9, "lab: the set-point is live from the start");
    ENR312_Ctrl_Defaults(&c, 23); c.seq = 0u;
    ENR312_Ctrl_Init(&x, &c);
    for (int i = 0; i < 600; ++i) { ENR312_Ctrl_Tick(&x, 0.0, 0.0, 180.0); }   /* captured */
    CHECK_EQ_I(x.phase, CTRL_PH_WAIT_RELEASE, "lab upright: still waits for the hand");
    ENR312_Ctrl_Tick(&x, 0.0, 0.0, 178.0);
    ENR312_Ctrl_Tick(&x, 0.0, 0.0, 178.0);
    CHECK_EQ_I(x.phase, CTRL_PH_HOLD, "lab upright: release goes straight to HOLD");
}

static void test_full_turn_is_hanging(void)
{
    /* a pendulum that fell over and came to rest after a full turn reads 360 deg */
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, 21);
    ENR312_Plant_Init(&p, 55.85, 20.0, 0.803);
    p.psi = 360.4 * DEG;
    CHECK(ENR312_Runner_Start(&r, &c), "exp 21 starts at psi 360");
    double umax = 0.0;
    for (uint32_t i = 0; i < (uint32_t)(5.0 / TS) && ENR312_Runner_IsMoving(&r); ++i) {
        double v = ENR312_Runner_Tick(&r, ENR312_Plant_RotorDeg(&p), ENR312_Plant_EncoderDeg(&p));
        if (fabs(r.u) > umax) { umax = fabs(r.u); }
        for (int k = 0; k < SUB; ++k) { ENR312_Plant_Step(&p, v * USTEP_PER_DEG, TS / SUB); }
    }
    CHECK(r.state != ENR312_RUN_ABORTED, "psi 360 regulates as hanging, no abort");
    CHECK(umax < 100.0, "and commands almost nothing (|u| max %.1f; a 360 deg error would be ~3600)", umax);
    CHECK_NEAR(ENR312_Runner_HangingAngle(360.4), 0.4, 1e-9, "HangingAngle(360.4) = 0.4");
    CHECK_NEAR(ENR312_Runner_HangingAngle(-719.0), 1.0, 1e-9, "HangingAngle(-719) = 1");
}

static void test_pendulum_target(void)
{
    /* exp 24 with 0 < amp < 179: swing to +/-amp and keep it there; amp 0: stop */
    const double amps[] = {90.0, 45.0, 135.0};
    const double wg2s[] = {55.85, 50.0, 62.0};
    for (unsigned j = 0; j < 3; ++j) {
        ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
        ENR312_Runner_Defaults(&c, 24); c.amp = amps[j];
        ENR312_Plant_Init(&p, wg2s[j], 20.0, 0.803); p.psi = 0.3 * DEG;
        CHECK(ENR312_Runner_Start(&r, &c), "pendulum target starts");
        double pk = 0.0, arm = 0.0;
        for (uint32_t i = 0; i < (uint32_t)(40.0 / TS) && ENR312_Runner_IsMoving(&r); ++i) {
            double v = ENR312_Runner_Tick(&r, ENR312_Plant_RotorDeg(&p), ENR312_Plant_EncoderDeg(&p));
            for (int k = 0; k < SUB; ++k) { ENR312_Plant_Step(&p, v * USTEP_PER_DEG, TS / SUB); }
            double a = fabs(ENR312_Runner_HangingAngle(ENR312_Plant_EncoderDeg(&p)));
            if (i * TS > 30.0 && a > pk) { pk = a; }          /* the last 10 s */
            if (fabs(ENR312_Plant_RotorDeg(&p)) > arm) { arm = fabs(ENR312_Plant_RotorDeg(&p)); }
        }
        CHECK(r.state != ENR312_RUN_ABORTED && r.phase == CTRL_PH_SWINGUP, "amp %.0f: still swinging, no catch", amps[j]);
        CHECK(fabs(pk - amps[j]) < 6.0, "amp %.0f (plant wg2 %.1f): swings to %.1f deg", amps[j], wg2s[j], pk);
        printf("    pendulum target %5.1f deg, plant wg2 %5.2f: swings to %5.1f deg, arm max %5.1f deg\n", amps[j], wg2s[j], pk, arm);
    }
    /* amp 0 stops a 40 deg swing */
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, 24); c.amp = 0.0;
    ENR312_Plant_Init(&p, 55.85, 27.0, 0.803); p.psi = 40.0 * DEG;
    ENR312_Runner_Start(&r, &c);
    double t_stop = -1.0;
    for (uint32_t i = 0; i < (uint32_t)(20.0 / TS); ++i) {
        double v = ENR312_Runner_Tick(&r, ENR312_Plant_RotorDeg(&p), ENR312_Plant_EncoderDeg(&p));
        for (int k = 0; k < SUB; ++k) { ENR312_Plant_Step(&p, v * USTEP_PER_DEG, TS / SUB); }
        if (fabs(ENR312_Runner_HangingAngle(ENR312_Plant_EncoderDeg(&p))) > 4.0) { t_stop = -1.0; }
        else if (t_stop < 0.0) { t_stop = i * TS; }
    }
    CHECK(t_stop > 0.0 && t_stop < 12.0, "amp 0 stops a 40 deg swing (inside 4 deg after %.1f s; free decay ~19 s)", t_stop);
    printf("    pendulum target 0: a 40 deg swing stays inside 4 deg after %.1f s\n", t_stop);
}

static void test_upright_trim(void)
{
    /* encoder datum 0.6 deg off (as measured on the rig 2026-10-21): without the
     * trim the LQR would hold the arm k3/k1 * 0.6 = 23 deg off its set-point */
    ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
    ENR312_Runner_Defaults(&c, 23); c.seq = 0u;
    ENR312_Plant_Init(&p, 55.85, 20.0, 0.803); p.enc_bias = 0.6;
    p.psi = 179.0 * DEG; p.held = true;           /* a hair off upright: it falls away from the hand */
    ENR312_Runner_Start(&r, &c);
    double arm_sum = 0.0; uint32_t n = 0u;
    for (uint32_t i = 0; i < (uint32_t)(60.0 / TS) && ENR312_Runner_IsMoving(&r); ++i) {
        if (r.phase != CTRL_PH_WAIT_CAPTURE) { p.held = false; }
        double v = ENR312_Runner_Tick(&r, ENR312_Plant_RotorDeg(&p), ENR312_Plant_EncoderDeg(&p));
        for (int k = 0; k < SUB; ++k) { ENR312_Plant_Step(&p, v * USTEP_PER_DEG, TS / SUB); }
        if (i * TS > 50.0) { arm_sum += ENR312_Plant_RotorDeg(&p); n++; }
    }
    double arm = n ? arm_sum / n : 99.0;
    CHECK(r.state != ENR312_RUN_ABORTED && fabs(arm) < 3.0, "trim: arm returns to its set-point (mean %.2f deg over 50-60 s; 23 without)", arm);
    CHECK_NEAR(r.ec.trim, -0.6, 0.2, "trim learnt the datum offset (encoder +0.6 -> alpha reads 0.6 low)");
    printf("    upright trim: datum offset 0.6 deg -> learnt %.2f deg, arm at %.2f deg\n", r.ec.trim, arm);
}

static void test_swing_up(void)
{
    /* from hanging almost still, the pump must bring the pendulum up, the LQR
     * must catch it, and it must still balance 20 s later; arm inside +/-240 */
    /* the real pendulum differs from the wg2 the firmware is told, its pivot
     * friction is unknown, the arm coupling wr2 is a Tutorial value; start
     * hanging still or plucked */
    const double wg2s[] = {55.85, 50.0, 62.0, 55.85, 55.85, 55.85, 55.85, 50.0, 62.0};
    const double qs[]   = {20.0,  20.0, 20.0, 12.0,  35.0,  20.0,  20.0,  12.0, 35.0};
    const double wr2s[] = {0.803, 0.803, 0.803, 0.803, 0.803, 0.70, 0.90, 0.90, 0.70};
    const double p0s[]  = {0.3,   0.3,  0.3,  0.3,   0.3,   0.3,   0.3,   25.0, -15.0};
    for (unsigned j = 0; j < 9; ++j) {
        ENR312_RunnerConfig_t c; ENR312_Runner_t r; ENR312_Plant_t p;
        ENR312_Runner_Defaults(&c, 24);
        ENR312_Plant_Init(&p, wg2s[j], qs[j], wr2s[j]);
        p.psi = p0s[j] * DEG;
        CHECK(ENR312_Runner_Start(&r, &c), "swing-up starts");
        double t_catch = -1.0, arm_max = 0.0;
        for (uint32_t i = 0; i < (uint32_t)(60.0 / TS) && ENR312_Runner_IsMoving(&r); ++i) {
            double v = ENR312_Runner_Tick(&r, ENR312_Plant_RotorDeg(&p), ENR312_Plant_EncoderDeg(&p));
            for (int k = 0; k < SUB; ++k) { ENR312_Plant_Step(&p, v * USTEP_PER_DEG, TS / SUB); }
            if (t_catch < 0.0 && r.phase == CTRL_PH_HOLD) { t_catch = i * TS; }
            if (fabs(ENR312_Plant_RotorDeg(&p)) > arm_max) { arm_max = fabs(ENR312_Plant_RotorDeg(&p)); }
        }
        double a = ENR312_Runner_UprightAngle(ENR312_Plant_EncoderDeg(&p));
        CHECK(t_catch > 0.0 && t_catch < 30.0, "plant wg2 %.1f Q %.0f: caught after %.1f s", wg2s[j], qs[j], t_catch);
        CHECK(r.state != ENR312_RUN_ABORTED && r.phase == CTRL_PH_HOLD && fabs(a) < 3.0,
              "plant wg2 %.1f: balancing at 60 s (alpha %.2f, phase %u)", wg2s[j], a, (unsigned)r.phase);
        CHECK(arm_max < 200.0, "plant wg2 %.1f: arm stayed within %.0f deg", wg2s[j], arm_max);
        printf("    swing-up: plant wg2 %5.2f Q %4.1f wr2 %.2f start %5.1f deg: caught %5.2f s, arm max %5.1f deg, end alpha %+.2f\n",
               wg2s[j], qs[j], wr2s[j], p0s[j], t_catch, arm_max, a);
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
    test_lab_mode();
    test_full_turn_is_hanging();
    test_pendulum_target();
    test_upright_trim();
    test_swing_up();
    TEST_REPORT("test_enr312_ctrl");
    return enr312_tests_failed ? 1 : 0;
}

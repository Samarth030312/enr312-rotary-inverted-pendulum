/**
 * @file test_enr312_exp005.c
 * @brief Host tests for EXP005 inverted-mode (unstable) dual-PID control.
 *
 * The closed-loop simulation uses the INVERTED plant, whose pendulum ODE has the
 * gravity term with the opposite sign:
 *     theta'' + (wg/Q) theta' - wg^2 theta = wr^2 u
 * The minus is what makes it unstable, and the tests below verify that the
 * OPEN-loop model really does diverge before asserting that the controller
 * stabilises it -- otherwise "it balanced" would prove nothing.
 */

#include "enr312_exp005.h"
#include "test_harness.h"

/* Inverted-mode parameters, Tutorial 5 section 8. REFERENCE/ASSUMED (OI-9). */
#define WR2   0.803
#define WG2   55.85
#define QF    20.0

typedef struct { double phi, phid, th, thd; } Inv_t;

static void inv_step(Inv_t *p, double u, double ts)
{
    const double gamma = sqrt(WG2) / QF;
    const int SUB = 16;                 /* fast unstable dynamics; sub-step */
    double h = ts / SUB;
    for (int i = 0; i < SUB; ++i) {
        /* NOTE THE SIGN: +WG2*th, i.e. gravity DESTABILISES. */
        double thdd = WR2 * u - gamma * p->thd + WG2 * p->th;
        p->th   += h * p->thd + 0.5 * h * h * thdd;
        p->thd  += h * thdd;
        p->phi  += h * p->phid + 0.5 * h * h * u;
        p->phid += h * u;
    }
}

/* Sanity: the open-loop model must actually be unstable, or nothing that
 * follows means anything. */
static void test_open_loop_is_unstable(void)
{
    Inv_t p = {0.0, 0.0, 0.5, 0.0};     /* 0.5 deg from upright, no control */
    for (int k = 0; k < 500; ++k) { inv_step(&p, 0.0, 0.002); }
    CHECK(fabs(p.th) > 5.0,
          "open-loop inverted pendulum diverges in 1 s (0.5 -> %.2f deg)", p.th);

    /* RHP pole at +7.2888 rad/s -> e-fold in 137 ms. After 1 s, ~e^7.29 = 1470x. */
    CHECK(fabs(p.th) > 100.0,
          "divergence rate is consistent with a 137 ms time constant (%.1f deg)",
          p.th);
}

static void test_supplied_inner_gains_fixed(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 9.0, 9.0, true);
    CHECK_NEAR(x.pd_pend.kp, 300.0, 1e-12, "Tutorial 5 supplies Kp_pend = 300");
    CHECK_NEAR(x.pd_pend.kd, 30.0, 1e-12, "Tutorial 5 supplies Kd_pend = 30");
    CHECK_NEAR(EXP005_KD_PEND, 30.0, 1e-12, "operative Kd_pend = 30 (serial transcript)");
    /* Tutorial 5 states Td = 0.5 s AND Kd = Kp*Td = 30, which is arithmetically
     * impossible (300*0.5 = 150). Kd = 30 wins on two independent pieces of
     * evidence; the implied Td is therefore 0.1 s. */
    CHECK_NEAR(EXP005_TD_PEND, 0.1, 1e-12,
               "implied Td = Kd/Kp = 0.1 s, NOT the 0.5 s the text states");
    CHECK_NEAR(EXP005_KP_PEND * EXP005_TD_PEND, EXP005_KD_PEND, 1e-12,
               "Kp*Td == Kd is now self-consistent");
    /* Thirty times the suspended-mode gain -- it stabilises rather than damps. */
    CHECK(EXP005_KP_PEND / 10.0 == 30.0, "inner gain is 30x the suspended-mode value");
}

static void test_rotor_branch_is_negated(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 1.0, 0.0, true);
    x.pd_pend.kp = 0.0; x.pd_pend.kd = 0.0;
    /* Drive to BALANCE so the controller is live. */
    for (uint32_t i = 0; i < EXP005_CAPTURE_TICKS + 2u; ++i) {
        ENR312_Exp005_Tick(&x, 0.0, 0.0);
    }
    CHECK_EQ_I(x.phase, EXP005_PHASE_BALANCE, "capture completes with pendulum upright");
    ENR312_Exp005_Tick(&x, 0.0, EXP005_RELEASE_DEG);    /* release: pendulum moved 1 deg */

    const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&x, -1.0, EXP005_RELEASE_DEG);
    /* Error = 0 - (-1) = +1, Kp = 1 -> unsaturated +1, but the branch is negated. */
    CHECK_NEAR(s->u_rotor, -1.0, 1e-9,
               "rotor branch is NEGATED in inverted mode (got %.4f)", s->u_rotor);
    CHECK_NEAR(EXP005_ROTOR_SIGN, -1.0, 1e-12, "mode sign constant is -1");
}

/* Held after capture (rig 2026-10-12): the motor must stay still while the
 * operator's hand holds the pendulum, whatever its small offset, and control
 * must start only once the pendulum moves EXP005_RELEASE_DEG on its own. */
static void test_waits_for_release(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 9.0, 9.0, true);
    for (uint32_t i = 0; i < EXP005_CAPTURE_TICKS + 2u; ++i) { ENR312_Exp005_Tick(&x, 0.0, 0.6); }
    CHECK_EQ_I(x.phase, EXP005_PHASE_BALANCE, "captured at 0.6 deg");
    double umax = 0.0;
    for (int i = 0; i < 5000; ++i) {                         /* held 10 s, 0.9 deg hand jitter */
        const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&x, 0.0, 0.6 + 0.9 * ((i / 50) % 2));
        if (fabs(s->u) > umax) { umax = fabs(s->u); }
    }
    CHECK_NEAR(umax, 0.0, 1e-12, "motor still while held (max |u| %.3f)", umax);
    CHECK_EQ_I(x.phase, EXP005_PHASE_BALANCE, "still waiting, not aborted, after 10 s held");
    const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&x, 0.0, 0.6 + EXP005_RELEASE_DEG);   /* falls */
    CHECK(x.released, "release detected when the pendulum moves EXP005_RELEASE_DEG");
    CHECK(fabs(s->u) > 0.0, "control on at release (u %.1f)", s->u);
}

/* Capture gate: the sequencer must not start balancing a pendulum that is not
 * upright. Closing the loop on a falling pendulum throws the arm at a limit. */
static void test_capture_gate(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 9.0, 9.0, true);
    for (int i = 0; i < 5000; ++i) { ENR312_Exp005_Tick(&x, 0.0, 5.0); }  /* 5 deg */
    CHECK_EQ_I(x.phase, EXP005_PHASE_WAIT_CAPTURE,
               "does not leave capture while the pendulum is off-upright");

    /* Now present it upright. */
    for (uint32_t i = 0; i < EXP005_CAPTURE_TICKS + 2u; ++i) {
        ENR312_Exp005_Tick(&x, 0.0, 0.5);
    }
    CHECK_EQ_I(x.phase, EXP005_PHASE_BALANCE, "capture completes once upright");

    /* No actuator command is issued while waiting. */
    ENR312_Exp005_t y;
    ENR312_Exp005_Init(&y, 9.0, 9.0, true);
    const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&y, 0.0, 8.0);
    CHECK_NEAR(s->u, 0.0, 1e-12, "no command while waiting for capture");
}

/* THE decisive test: the supplied controller must stabilise an unstable plant. */
static void test_controller_stabilises_unstable_plant(void)
{
    ENR312_Exp005_t x;
    Inv_t p = {0.0, 0.0, 0.0, 0.0};
    ENR312_Exp005_Init(&x, EXP005_SYS1_KP, EXP005_SYS1_KD, true);
    ENR312_Exp005_SetRotorStep(&x, 2.0);

    double max_pend = 0.0;
    ENR312_Exp005Sample_t eos = {0};
    int let_go = 0;
    for (uint32_t i = 0; i < 200000u && !ENR312_Exp005_IsFinished(&x); ++i) {
        /* the hand lets go at capture, 0.3 deg off upright: it falls from there */
        if (!let_go && x.phase == EXP005_PHASE_BALANCE) { p.th += 0.3; let_go = 1; }
        const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&x, p.phi, p.th);
        if (s->phase == EXP005_PHASE_ROTOR_STEP) { eos = *s; }
        if (fabs(s->pend_deg) > max_pend) { max_pend = fabs(s->pend_deg); }
        inv_step(&p, x.armed ? s->u : 0.0, ENR312_CONTROL_PERIOD_S);
    }

    CHECK_EQ_I(x.phase, EXP005_PHASE_DONE,
               "System 1 balances the INVERTED pendulum to completion");
    CHECK_EQ_I(x.abort_reason, EXP005_ABORT_NONE, "no abort");
    CHECK(max_pend < EXP005_PENDULUM_ABORT_DEG,
          "pendulum stayed inside the linear region (max %.2f deg)", max_pend);
    CHECK_NEAR(eos.rotor_deg, 2.0, 0.30,
               "rotor tracks the 2 deg reference (got %.4f)", eos.rotor_deg);
    CHECK(fabs(x.last.pend_deg) < 2.0,
          "pendulum still near upright at the end (%.3f deg)", x.last.pend_deg);
}

/* Safety: losing the pendulum must abort, and stay aborted. */
static void test_pendulum_lost_abort(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 9.0, 9.0, true);
    for (uint32_t i = 0; i < EXP005_CAPTURE_TICKS + 2u; ++i) {
        ENR312_Exp005_Tick(&x, 0.0, 0.0);
    }
    for (int i = 0; i < 10 && !ENR312_Exp005_IsFinished(&x); ++i) {
        ENR312_Exp005_Tick(&x, 0.0, EXP005_PENDULUM_ABORT_DEG + 1.0);
    }
    CHECK_EQ_I(x.phase, EXP005_PHASE_ABORTED, "departure from upright aborts");
    CHECK_EQ_I(x.abort_reason, EXP005_ABORT_PENDULUM_LOST, "reason recorded");

    const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&x, 0.0, 0.0);
    CHECK_NEAR(s->u, 0.0, 1e-12, "output zeroed after abort, even if it recovers");
    CHECK_EQ_I(x.phase, EXP005_PHASE_ABORTED, "abort is sticky");
}

/* The soft warning band must catch a sustained large deviation BEFORE the hard
 * bound -- converting a fall into a controlled stop. */
static void test_warning_band_aborts_before_hard_limit(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 9.0, 9.0, true);
    for (uint32_t i = 0; i < EXP005_CAPTURE_TICKS + 2u; ++i) {
        ENR312_Exp005_Tick(&x, 0.0, 0.0);
    }
    /* Hold just inside the hard bound but outside the warning band. */
    double held = 0.5 * (EXP005_PEND_WARN_DEG + EXP005_PENDULUM_ABORT_DEG);
    uint32_t n = 0;
    while (!ENR312_Exp005_IsFinished(&x) && n < 10000u) {
        ENR312_Exp005_Tick(&x, 0.0, held);
        n++;
    }
    CHECK_EQ_I(x.phase, EXP005_PHASE_ABORTED, "sustained warning-band deviation aborts");
    CHECK_EQ_I(x.abort_reason, EXP005_ABORT_PENDULUM_LOST, "reason recorded");
    CHECK(n <= EXP005_PEND_WARN_TICKS + 5u,
          "aborted within the warning window (%u ticks)", n);
}

static void test_dry_run_commands_nothing(void)
{
    ENR312_Exp005_t x;
    Inv_t p = {0.0, 0.0, 0.0, 0.0};
    ENR312_Exp005_Init(&x, 9.0, 9.0, /*armed=*/false);
    for (uint32_t i = 0; i < 200000u && !ENR312_Exp005_IsFinished(&x); ++i) {
        /* after capture the measurement shows a release (1 deg), sequencing only */
        double meas = p.th + ((x.phase != EXP005_PHASE_WAIT_CAPTURE) ? EXP005_RELEASE_DEG : 0.0);
        (void)ENR312_Exp005_Tick(&x, p.phi, meas);
        inv_step(&p, 0.0, ENR312_CONTROL_PERIOD_S);   /* disarmed: nothing acts */
    }
    CHECK_EQ_I(x.phase, EXP005_PHASE_DONE, "dry run completes");
    CHECK_NEAR(p.phi, 0.0, 1e-12, "dry run moves nothing");
}

static void test_operator_abort(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 9.0, 9.0, true);
    for (int i = 0; i < 50; ++i) { ENR312_Exp005_Tick(&x, 0.0, 0.0); }
    ENR312_Exp005_Abort(&x);
    CHECK_EQ_I(x.abort_reason, EXP005_ABORT_OPERATOR, "operator abort recorded");
    const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&x, 0.0, 0.0);
    CHECK_NEAR(s->u, 0.0, 1e-12, "output zeroed");
}

static void test_safety_bounds_are_tighter_than_exp003(void)
{
    CHECK(EXP005_PENDULUM_ABORT_DEG < ENR312_PENDULUM_ABORT_DEG,
          "inverted-mode pendulum bound (%.0f deg) is tighter than suspended (%.0f deg)",
          EXP005_PENDULUM_ABORT_DEG, ENR312_PENDULUM_ABORT_DEG);
    CHECK(EXP005_PENDULUM_ABORT_DEG <= 15.0,
          "bound keeps the small-angle linearisation valid (sin error < 1.2 %%)");
    CHECK(EXP005_PEND_WARN_DEG < EXP005_PENDULUM_ABORT_DEG,
          "warning band sits inside the hard bound");
}

static void test_csv(void)
{
    ENR312_Exp005_t x;
    ENR312_Exp005_Init(&x, 9.0, 9.0, true);
    const ENR312_Exp005Sample_t *r = ENR312_Exp005_Tick(&x, 0.0, 0.0);
    char buf[256];
    int n = ENR312_Exp005_FormatCsv(r, buf, (int)sizeof buf);
    CHECK(n > 0 && n < (int)sizeof buf, "CSV fits (n=%d)", n);
    int hc = 0, lc = 0;
    for (const char *p = ENR312_Exp005_CsvHeader(); *p; ++p) { if (*p == ',') hc++; }
    for (const char *p = buf; *p; ++p) { if (*p == ',') lc++; }
    CHECK_EQ_I(lc, hc, "CSV field count matches header");
    CHECK_EQ_I(hc, 9, "header declares 10 fields");
}

int main(void)
{
    printf("EXP005 inverted-mode (unstable) tests (parameter set %s)\n",
           ENR312_PARAMETER_SET_ID);
    test_open_loop_is_unstable();
    test_supplied_inner_gains_fixed();
    test_rotor_branch_is_negated();
    test_waits_for_release();
    test_capture_gate();
    test_controller_stabilises_unstable_plant();
    test_pendulum_lost_abort();
    test_warning_band_aborts_before_hard_limit();
    test_dry_run_commands_nothing();
    test_operator_abort();
    test_safety_bounds_are_tighter_than_exp003();
    test_csv();
    TEST_REPORT("test_enr312_exp005");
    return enr312_tests_failed == 0 ? 0 : 1;
}

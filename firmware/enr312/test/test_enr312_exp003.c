/**
 * @file test_enr312_exp003.c
 * @brief Host tests for EXP003 dual-PID MIMO suspended-mode control.
 *
 * Includes a full closed-loop simulation of BOTH plants. The pendulum ODE is
 * derived rather than assumed: with
 *     G_pend(s) = theta/phi = wr^2 s^2 / (s^2 + gamma s + wg^2)
 * and the rotor plant phi = u/s^2, we have s^2 phi = u, so
 *     theta'' + gamma theta' + wg^2 theta = wr^2 * u
 * i.e. the pendulum is driven directly by the plant input. That makes the
 * simulation exact in structure, with no algebraic loop.
 */

#include "enr312_exp003.h"
#include "test_harness.h"

/* Suspended-mode parameters, Tutorial 12 section 2. REFERENCE/ASSUMED. */
#define WR2   0.803
#define WG2   57.01
#define QF    27.0

typedef struct { double phi, phid, th, thd; } Mimo_t;

static void mimo_step(Mimo_t *p, double u, double ts)
{
    const double gamma = sqrt(WG2) / QF;
    /* Sub-step for accuracy: wg*ts is small, but the derivative transient after
     * a step is not, and a single Euler step visibly distorts the first peak. */
    const int SUB = 8;
    double h = ts / SUB;
    for (int i = 0; i < SUB; ++i) {
        double thdd = WR2 * u - gamma * p->thd - WG2 * p->th;
        p->th  += h * p->thd + 0.5 * h * h * thdd;
        p->thd += h * thdd;
        p->phi += h * p->phid + 0.5 * h * h * u;
        p->phid += h * u;
    }
}

/* ---- Control-effort accumulator ------------------------------------------ */
static void test_control_effort_accumulator(void)
{
    ENR312_ControlEffort_t e;
    ENR312_ControlEffort_Reset(&e);
    CHECK_NEAR(e.ce_total, 0.0, 1e-12, "reset clears the integral");

    /* Constant |u| = 2 for 1 s at 2 ms: trapezoid gives 2*(1 - ts) because the
     * first sample has no predecessor. 500 samples -> 499 intervals. */
    for (int k = 0; k < 501; ++k) { ENR312_ControlEffort_Update(&e, 2.0, 0.002); }
    CHECK_NEAR(e.ce_max, 2.0, 1e-12, "max |u|");
    CHECK_NEAR(e.ce_max_power, 4.0, 1e-12, "max u^2");
    CHECK_NEAR(e.ce_total, 2.0 * 500 * 0.002, 1e-9, "trapezoid over 500 intervals");
    CHECK_EQ_I(e.samples, 501, "sample count");

    /* Sign must not matter for magnitude metrics. */
    ENR312_ControlEffort_Reset(&e);
    ENR312_ControlEffort_Update(&e, -7.0, 0.002);
    CHECK_NEAR(e.ce_max, 7.0, 1e-12, "max uses |u|");
    CHECK_NEAR(e.ce_max_power, 49.0, 1e-12, "power uses u^2, always positive");

    /* A signed integral would cancel; CE_Total must not. */
    ENR312_ControlEffort_Reset(&e);
    for (int k = 0; k < 100; ++k) { ENR312_ControlEffort_Update(&e,  1.0, 0.01); }
    for (int k = 0; k < 100; ++k) { ENR312_ControlEffort_Update(&e, -1.0, 0.01); }
    CHECK(e.ce_total > 1.9, "CE_Total accumulates |u|, it does not cancel (got %.4f)",
          e.ce_total);
}

/* ---- Structure ----------------------------------------------------------- */
static void test_inner_controller_is_fixed(void)
{
    ENR312_Exp003_t x;
    ENR312_Exp003_Init(&x, 6.0, 4.8, true);
    CHECK_NEAR(x.pd_pend.kp, 10.0, 1e-12, "Tutorial 3 supplies Kp_pend = 10");
    CHECK_NEAR(x.pd_pend.kd, 5.0, 1e-12, "Tutorial 3 supplies Kd_pend = 5");
    CHECK_NEAR(x.pd_rotor.kp, 6.0, 1e-12, "outer Kp is the design variable");
    CHECK_NEAR(x.pd_rotor.kd, 4.8, 1e-12, "outer Kd is the design variable");
    CHECK_NEAR(EXP003_KD_PEND, 5.0, 1e-12, "Kd_pend = Kp_pend * Td_pend");
    CHECK_NEAR(EXP003_KD_ROTOR_D1, 4.8, 1e-12, "Design 1 Kd = 6 * 0.8");
}

static void test_summation_and_single_saturation(void)
{
    ENR312_Exp003_t x;
    ENR312_Exp003_Init(&x, 1.0, 0.0, true);
    x.pd_pend.kp = 1.0; x.pd_pend.kd = 0.0;

    /* Rotor error +3, pendulum error -1 (theta_ref = 0, theta = +1).
     * u must be the SUM: 3 + (-1) = 2. */
    const ENR312_Exp003Sample_t *s = ENR312_Exp003_Tick(&x, -3.0, 1.0);
    CHECK_NEAR(s->u_rotor, 3.0, 1e-9, "K_rotor sees phi_ref - phi");
    CHECK_NEAR(s->u_pend, -1.0, 1e-9, "K_pend sees theta_ref - theta");
    CHECK_NEAR(s->u, 2.0, 1e-9, "plant input is the SUM of both controllers");

    /* Saturation is applied once, to the sum -- not per branch. */
    ENR312_Exp003_t y;
    ENR312_Exp003_Init(&y, 1e6, 0.0, true);
    y.pd_pend.kp = 0.0; y.pd_pend.kd = 0.0;
    const ENR312_Exp003Sample_t *t = ENR312_Exp003_Tick(&y, -1.0, 0.0);
    CHECK(t->u_rotor > EXP003_DEFAULT_U_LIMIT,
          "unsaturated branch value is reported (%.1f)", t->u_rotor);
    CHECK_NEAR(t->u, EXP003_DEFAULT_U_LIMIT, 1e-9, "sum is clamped to the limit");
}

/* ---- Closed loop --------------------------------------------------------- */
/* Captures the LAST sample of the excitation phase.
 *
 * The run does not end at the excitation: a SETTLE phase follows in which the
 * reference returns to zero and the rotor is commanded back. Probing the final
 * sample of the whole run therefore measures the return-to-zero, not the
 * tracking -- which is exactly the mistake this helper exists to prevent. */
static void run_mimo(ENR312_Exp003_t *x, Mimo_t *p, uint32_t max_ticks,
                     ENR312_Exp003Sample_t *end_of_step)
{
    const double ts = ENR312_CONTROL_PERIOD_S;
    for (uint32_t i = 0; i < max_ticks && !ENR312_Exp003_IsFinished(x); ++i) {
        const ENR312_Exp003Sample_t *s =
            ENR312_Exp003_Tick(x, p->phi, p->th);
        if (end_of_step != NULL && s->phase == EXP003_PHASE_ROTOR_STEP) {
            *end_of_step = *s;
        }
        mimo_step(p, x->armed ? s->u : 0.0, ts);
    }
}

static void test_closed_loop_tracks_and_settles(void)
{
    ENR312_Exp003_t x;
    Mimo_t p = {0};
    ENR312_Exp003_Init(&x, EXP003_KP_ROTOR_D1, EXP003_KD_ROTOR_D1, true);
    ENR312_Exp003_SetRotorStep(&x, 2.0);
    ENR312_Exp003Sample_t eos = {0};
    run_mimo(&x, &p, 200000u, &eos);

    CHECK_EQ_I(x.phase, EXP003_PHASE_DONE, "Design 1 run completes without abort");
    CHECK_EQ_I(x.abort_reason, EXP003_ABORT_NONE, "no abort");

    /* The rotor must reach the commanded angle BY THE END OF THE STEP PHASE. */
    CHECK_NEAR(eos.rotor_deg, 2.0, 0.10,
               "rotor tracks the 2 deg reference (got %.4f)", eos.rotor_deg);

    /* Suspended pendulum must come back to rest near zero -- it is stable, and
     * the inner loop actively drives it there. */
    CHECK(fabs(eos.pend_deg) < 0.20,
          "pendulum returns near zero (got %.4f deg)", eos.pend_deg);

    /* And after the reference returns to zero, the rotor follows it back. */
    CHECK(fabs(x.last.rotor_deg) < 0.10,
          "rotor returns to zero when the reference does (got %.4f)",
          x.last.rotor_deg);

    /* Control-effort metrics must be finite, positive and correctly ordered. */
    CHECK(x.effort.ce_max > 0.0, "CE_Max positive (%.2f)", x.effort.ce_max);
    CHECK_NEAR(x.effort.ce_max_power, x.effort.ce_max * x.effort.ce_max, 1e-6,
               "CE_Max_Power = CE_Max^2 by definition");
    CHECK(x.effort.ce_total > 0.0, "CE_Total positive (%.3f)", x.effort.ce_total);
    CHECK(isfinite(x.effort.ce_total), "CE_Total finite");
}

/* Lower rotor gain must cost less control effort. This is Tutorial 3's whole
 * thesis -- performance is bought with effort -- so it is asserted, not assumed. */
static void test_lower_gain_costs_less_effort(void)
{
    ENR312_Exp003_t hi, lo;
    Mimo_t ph = {0}, pl = {0};

    ENR312_Exp003_Init(&hi, 6.0, 4.8, true);
    ENR312_Exp003_SetRotorStep(&hi, 2.0);
    run_mimo(&hi, &ph, 200000u, NULL);

    ENR312_Exp003_Init(&lo, 1.5, 1.5, true);
    ENR312_Exp003_SetRotorStep(&lo, 2.0);
    run_mimo(&lo, &pl, 200000u, NULL);

    CHECK(lo.effort.ce_max < hi.effort.ce_max,
          "lower gain -> lower CE_Max (%.1f < %.1f)", lo.effort.ce_max, hi.effort.ce_max);
    CHECK(lo.effort.ce_total < hi.effort.ce_total,
          "lower gain -> lower CE_Total (%.3f < %.3f)",
          lo.effort.ce_total, hi.effort.ce_total);
}

/* ---- Safety -------------------------------------------------------------- */
static void test_dry_run(void)
{
    ENR312_Exp003_t x;
    Mimo_t p = {0};
    ENR312_Exp003_Init(&x, 6.0, 4.8, /*armed=*/false);
    run_mimo(&x, &p, 200000u, NULL);
    CHECK_EQ_I(x.phase, EXP003_PHASE_DONE, "dry run completes");
    CHECK_NEAR(p.phi, 0.0, 1e-12, "dry run moves nothing");
    CHECK(x.effort.ce_total > 0.0, "dry run still measures the WOULD-BE effort");
}

static void test_pendulum_limit_abort(void)
{
    ENR312_Exp003_t x;
    ENR312_Exp003_Init(&x, 6.0, 4.8, true);
    for (int i = 0; i < 10 && !ENR312_Exp003_IsFinished(&x); ++i) {
        ENR312_Exp003_Tick(&x, 0.0, ENR312_PENDULUM_ABORT_DEG + 5.0);
    }
    CHECK_EQ_I(x.phase, EXP003_PHASE_ABORTED, "pendulum excursion aborts");
    CHECK_EQ_I(x.abort_reason, EXP003_ABORT_PENDULUM_LIMIT, "reason recorded");
}

static void test_rotor_limit_abort(void)
{
    ENR312_Exp003_t x;
    ENR312_Exp003_Init(&x, 6.0, 4.8, true);
    for (int i = 0; i < 10 && !ENR312_Exp003_IsFinished(&x); ++i) {
        ENR312_Exp003_Tick(&x, ENR312_ROTOR_LIMIT_DEG + 5.0, 0.0);
    }
    CHECK_EQ_I(x.phase, EXP003_PHASE_ABORTED, "rotor excursion aborts");
    CHECK_EQ_I(x.abort_reason, EXP003_ABORT_ROTOR_LIMIT, "reason recorded");
}

static void test_operator_abort(void)
{
    ENR312_Exp003_t x;
    ENR312_Exp003_Init(&x, 6.0, 4.8, true);
    for (int i = 0; i < 50; ++i) { ENR312_Exp003_Tick(&x, 0.0, 0.0); }
    ENR312_Exp003_Abort(&x);
    CHECK_EQ_I(x.abort_reason, EXP003_ABORT_OPERATOR, "operator abort recorded");
    const ENR312_Exp003Sample_t *s = ENR312_Exp003_Tick(&x, 1.0, 0.0);
    CHECK_NEAR(s->u, 0.0, 1e-12, "output zeroed after abort");
    CHECK_EQ_I(x.phase, EXP003_PHASE_ABORTED, "abort is sticky");
}

static void test_csv(void)
{
    ENR312_Exp003_t x;
    ENR312_Exp003_Init(&x, 6.0, 4.8, true);
    const ENR312_Exp003Sample_t *r = ENR312_Exp003_Tick(&x, 0.0, 0.0);
    char buf[256];
    int n = ENR312_Exp003_FormatCsv(r, buf, (int)sizeof buf);
    CHECK(n > 0 && n < (int)sizeof buf, "CSV fits (n=%d)", n);
    int hc = 0, lc = 0;
    for (const char *p = ENR312_Exp003_CsvHeader(); *p; ++p) { if (*p == ',') hc++; }
    for (const char *p = buf; *p; ++p) { if (*p == ',') lc++; }
    CHECK_EQ_I(lc, hc, "CSV field count matches header");
    CHECK_EQ_I(hc, 10, "header declares 11 fields");
}

int main(void)
{
    printf("EXP003 dual-PID MIMO tests (parameter set %s)\n", ENR312_PARAMETER_SET_ID);
    test_control_effort_accumulator();
    test_inner_controller_is_fixed();
    test_summation_and_single_saturation();
    test_closed_loop_tracks_and_settles();
    test_lower_gain_costs_less_effort();
    test_dry_run();
    test_pendulum_limit_abort();
    test_rotor_limit_abort();
    test_operator_abort();
    test_csv();
    TEST_REPORT("test_enr312_exp003");
    return enr312_tests_failed == 0 ? 0 : 1;
}

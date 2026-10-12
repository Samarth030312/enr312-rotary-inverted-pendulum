/**
 * @file test_enr312_pd.c
 * @brief Host unit tests for the EXP002 rotor PD controller.
 *
 * The strongest test here is not a unit test: it closes the loop around a
 * discrete model of the Tutorial 1 plant P(s) = 1/s^2 and checks that the
 * FIRMWARE reproduces the ANALYTIC closed-loop behaviour predicted by
 * scripts/exp002_sensitivity_design.py. Firmware and model must agree, or one
 * of them is wrong.
 */

#include "enr312_pd.h"
#include "test_harness.h"
#include <string.h>

/* ---- Discrete model of P(s) = 1/s^2 -----------------------------------------
 * Zero-order hold on u over one sample is exact for a double integrator:
 *     y[k+1] = y[k] + Ts*v[k] + (Ts^2/2)*u[k]
 *     v[k+1] = v[k] + Ts*u[k]
 * This is a MODEL used to test the controller. It is not a claim about the rig.
 */
typedef struct { double y, v; } Plant_t;

static void plant_step(Plant_t *p, double u, double ts)
{
    p->y += ts * p->v + 0.5 * ts * ts * u;
    p->v += ts * u;
}

static void test_alpha_from_fc(void)
{
    double ts = 0.002;
    /* a = 1 - exp(-2*pi*10*0.002) = 1 - exp(-0.12566371) = 0.11808862 */
    CHECK_NEAR(ENR312_PD_AlphaFromFc(10.0, ts), 0.11808862, 1e-8, "alpha at 10 Hz");
    /* Noise gain sqrt(a/(2-a)) must reproduce the EXP001 figure 0.254. */
    double a = ENR312_PD_AlphaFromFc(10.0, ts);
    CHECK_NEAR(sqrt(a / (2.0 - a)), 0.2506, 1e-3, "derivative noise gain at 10 Hz");
    /* fc <= 0 disables filtering: alpha = 1 (pass-through). */
    CHECK_NEAR(ENR312_PD_AlphaFromFc(0.0, ts), 1.0, 1e-12, "fc=0 disables filter");
    CHECK_NEAR(ENR312_PD_AlphaFromFc(-5.0, ts), 1.0, 1e-12, "negative fc disables filter");
    /* Very high corner saturates at 1, never above. */
    CHECK(ENR312_PD_AlphaFromFc(1e6, ts) <= 1.0, "alpha never exceeds 1");
}

static void test_proportional_only(void)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, 3.0, 0.0, 0.002, 10.0);
    ENR312_PD_Signals_t s = {0};
    s.reference = 2.0; s.measured = 0.5;
    ENR312_PD_Update(&c, &s);
    CHECK_NEAR(s.error, 1.5, 1e-12, "error = R - (Y+N)");
    CHECK_NEAR(s.u_unsat, 4.5, 1e-12, "Kd=0 -> u = Kp*e");
    CHECK_NEAR(s.u, 4.5, 1e-12, "D=0 -> U = u");
}

static void test_noise_enters_at_sensor(void)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, 1.0, 0.0, 0.002, 10.0);
    ENR312_PD_Signals_t s = {0};
    s.reference = 0.0; s.measured = 0.0; s.noise = 0.25;
    ENR312_PD_Update(&c, &s);
    /* The controller must see Y+N, so N produces an error even at Y=R=0. */
    CHECK_NEAR(s.error, -0.25, 1e-12, "noise enters at the sensor");
}

static void test_disturbance_enters_at_plant_input(void)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, 1.0, 0.0, 0.002, 10.0);
    ENR312_PD_Signals_t s = {0};
    s.reference = 0.0; s.measured = 0.0; s.disturbance = 0.7;
    ENR312_PD_Update(&c, &s);
    CHECK_NEAR(s.error, 0.0, 1e-12, "D does not appear in the error");
    CHECK_NEAR(s.u_unsat, 0.0, 1e-12, "D does not pass through the controller");
    CHECK_NEAR(s.u, 0.7, 1e-12, "D is summed at the plant input");
}

static void test_first_sample_derivative_zero(void)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, 0.0, 100.0, 0.002, 0.0);   /* pure unfiltered derivative */
    ENR312_PD_Signals_t s = {0};
    s.reference = 1.0; s.measured = 0.0;
    ENR312_PD_Update(&c, &s);
    CHECK_NEAR(s.u_unsat, 0.0, 1e-12,
               "first sample has no predecessor -> derivative is 0, not a spike");
    /* Second sample with an unchanged error is also zero. */
    ENR312_PD_Update(&c, &s);
    CHECK_NEAR(s.u_unsat, 0.0, 1e-12, "constant error -> zero derivative");
}

static void test_saturation(void)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, 1000.0, 0.0, 0.002, 10.0);
    ENR312_PD_SetOutputLimit(&c, 5.0);
    ENR312_PD_Signals_t s = {0};
    s.reference = 1.0; s.measured = 0.0;
    ENR312_PD_Update(&c, &s);
    CHECK_NEAR(s.u_unsat, 1000.0, 1e-9, "unsaturated value is reported");
    CHECK_NEAR(s.u, 5.0, 1e-12, "output is clamped to the limit");
    CHECK_EQ_I(c.saturation_events, 1, "saturation counted");

    s.reference = -1.0;
    ENR312_PD_Update(&c, &s);
    CHECK_NEAR(s.u, -5.0, 1e-12, "negative clamp is symmetric");
    CHECK_EQ_I(c.saturation_events, 2, "second saturation counted");
}

static void test_load_disturbance_offset_formula(void)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, 5.0, 2.5, 0.002, 10.0);
    CHECK_NEAR(ENR312_PD_LoadDisturbanceOffset(&c), 0.2, 1e-12,
               "steady-state offset under unit load = 1/Kp");
    ENR312_PD_Init(&c, 6.55, 4.0, 0.002, 10.0);
    CHECK_NEAR(ENR312_PD_LoadDisturbanceOffset(&c), 1.0 / 6.55, 1e-12,
               "offset for the EXP002 selected design");
}

static void test_predict_step_demand(void)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, 5.0, 2.5, 0.002, 10.0);
    /* u_peak = A*(Kp + Kd*alpha/Ts) = A*(5 + 2.5*0.11808862/0.002) = A*152.611 */
    CHECK_NEAR(ENR312_PD_PredictStepDemand(&c, 1.0), 152.6108, 1e-3,
               "predicted peak demand per degree");
    CHECK_NEAR(ENR312_PD_PredictStepDemand(&c, 2.0), 305.2216, 1e-3,
               "EXP002 default 2 deg step");
    CHECK(ENR312_PD_PredictStepDemand(&c, 2.0) < 400.0,
          "EXP002 default step stays inside the 400 output limit");
    CHECK(ENR312_PD_PredictStepDemand(&c, 10.0) > 400.0,
          "a 10 deg step would clip -- which is why the default is not 10 deg");
    CHECK_NEAR(ENR312_PD_PredictStepDemand(&c, -2.0), 305.2216, 1e-3,
               "prediction uses magnitude");
}

/* ---- Closed-loop: firmware vs analytic model ------------------------------ */
/* WARM-UP MATTERS, and this is a real property of the controller rather than a
 * testing convenience. ENR312_PD_Update deliberately reports a zero derivative
 * on its first sample (there is no predecessor to difference against). If the
 * excitation step is applied on that very first tick, the derivative kick that
 * produces T(s)'s numerator zero is suppressed, and the measured response
 * collapses towards the no-zero case -- about 11 % overshoot instead of 27 %.
 *
 * The EXP002 sequencer never hits this, because its IDLE phase runs first. The
 * simulation must reproduce that ordering or it is not testing the same system. */
#define WARMUP_TICKS 5

static void closed_loop(double kp, double kd, double R, double D, double fc,
                        int n, double *y_out, double ts)
{
    ENR312_PD_t c;
    ENR312_PD_Init(&c, kp, kd, ts, fc);
    ENR312_PD_SetOutputLimit(&c, 1e9);        /* disable saturation for linearity */
    Plant_t p = {0.0, 0.0};
    for (int k = 0; k < WARMUP_TICKS; ++k) {  /* zero excitation, establishes prev_error */
        ENR312_PD_Signals_t s = {0};
        s.measured = p.y;
        ENR312_PD_Update(&c, &s);
        plant_step(&p, s.u, ts);
    }
    for (int k = 0; k < n; ++k) {
        ENR312_PD_Signals_t s = {0};
        s.reference = R; s.disturbance = D; s.noise = 0.0; s.measured = p.y;
        ENR312_PD_Update(&c, &s);
        y_out[k] = p.y;
        plant_step(&p, s.u, ts);
    }
}

static void metrics(const double *y, int n, double ts, double yf,
                    double *peak, double *tpk, double *os, double *settle)
{
    int ipk = 0;
    for (int k = 1; k < n; ++k) { if (y[k] > y[ipk]) { ipk = k; } }
    *peak = y[ipk];
    *tpk  = ipk * ts;
    *os   = 100.0 * (*peak - yf) / fabs(yf);
    int last = -1;
    for (int k = 0; k < n; ++k) { if (fabs(y[k] - yf) > 0.02 * fabs(yf)) { last = k; } }
    *settle = (last < 0) ? 0.0 : last * ts;
}

/* Tutorial 1 design, reference step -> complementary sensitivity T(s).
 * Analytic prediction (scripts/exp002_sensitivity_design.py):
 *     peak 1.2676 at 1.055 s, overshoot 26.76 %, settling 3.239 s
 * The firmware uses a 10 Hz-filtered derivative, which the ideal C = Kp + Kd*s
 * does not, so agreement is expected to be close but not exact. The tolerances
 * below are tight enough to catch a real error and loose enough to admit that
 * known, deliberate difference. */
static void test_closed_loop_T_matches_model(void)
{
    const double ts = 0.002; const int n = 15000;   /* 30 s */
    static double y[15000];
    closed_loop(5.0, 2.5, 1.0, 0.0, ENR312_PD_DEFAULT_DERIV_FC_HZ, n, y, ts);

    double peak, tpk, os, settle;
    metrics(y, n, ts, 1.0, &peak, &tpk, &os, &settle);

    CHECK_NEAR(peak, 1.2676, 0.02, "T peak value vs analytic 1.2676");
    CHECK_NEAR(tpk, 1.055, 0.05, "T peak time vs analytic 1.055 s");
    CHECK_NEAR(os, 26.76, 2.0, "T overshoot vs analytic 26.76 %%");
    CHECK_NEAR(settle, 3.239, 0.30, "T settling vs analytic 3.239 s");
    CHECK_NEAR(y[n - 1], 1.0, 1e-3, "T final value is exactly 1 (T(0)=1)");
}

/* Load-disturbance step -> SD(s). The steady-state value is the sharpest
 * available check: it must equal 1/Kp EXACTLY, because a PD controller has no
 * integral action. */
static void test_closed_loop_SD_offset(void)
{
    const double ts = 0.002; const int n = 15000;
    static double y[15000];
    closed_loop(5.0, 2.5, 0.0, 1.0, ENR312_PD_DEFAULT_DERIV_FC_HZ, n, y, ts);

    CHECK_NEAR(y[n - 1], 0.2, 1e-4,
               "SD settles to 1/Kp = 0.2, NOT to zero -- no integral action");

    double peak, tpk, os, settle;
    metrics(y, n, ts, 0.2, &peak, &tpk, &os, &settle);
    CHECK_NEAR(tpk, 1.694, 0.10, "SD peak time vs analytic 1.694 s");
    CHECK_NEAR(os, 12.03, 2.5, "SD overshoot vs analytic 12.03 %%");

    /* And the decisive engineering point: relative to ZERO it never settles. */
    int outside_zero = 0;
    for (int k = n - 100; k < n; ++k) {
        if (fabs(y[k]) > 0.02 * peak) { outside_zero++; }
    }
    CHECK_EQ_I(outside_zero, 100,
               "measured against zero the disturbance response NEVER settles");
}

/* The EXP002 selected design must also reproduce its analytic prediction. */
static void test_closed_loop_selected_design(void)
{
    const double ts = 0.002; const int n = 15000;
    static double y[15000];
    closed_loop(6.55, 4.0, 1.0, 0.0, ENR312_PD_DEFAULT_DERIV_FC_HZ, n, y, ts);

    double peak, tpk, os, settle;
    metrics(y, n, ts, 1.0, &peak, &tpk, &os, &settle);
    CHECK_NEAR(peak, 1.1849, 0.02, "selected design T peak vs analytic 1.1849");
    CHECK_NEAR(os, 18.49, 2.0, "selected design overshoot vs analytic 18.49 %%");
    CHECK(tpk <= 2.0, "selected design meets peak-time spec (<= 2 s), got %.3f", tpk);
    CHECK(settle <= 4.0, "selected design meets settling spec (<= 4 s), got %.3f", settle);
}

int main(void)
{
    printf("EXP002 PD controller unit tests (parameter set %s)\n",
           ENR312_PARAMETER_SET_ID);
    test_alpha_from_fc();
    test_proportional_only();
    test_noise_enters_at_sensor();
    test_disturbance_enters_at_plant_input();
    test_first_sample_derivative_zero();
    test_saturation();
    test_load_disturbance_offset_formula();
    test_predict_step_demand();
    test_closed_loop_T_matches_model();
    test_closed_loop_SD_offset();
    test_closed_loop_selected_design();
    TEST_REPORT("test_enr312_pd");
    return enr312_tests_failed == 0 ? 0 : 1;
}

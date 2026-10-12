/**
 * @file test_enr312_metrics.c
 * @brief Host tests for the EXP004 dual-output step-metrics accumulator.
 *
 * Covers both settling conventions. The distinction is not cosmetic: applying
 * the rotor convention to the pendulum divides by a final value of ~0.
 */

#include "enr312_metrics.h"
#include "test_harness.h"

static void test_settle_to_final(void)
{
    ENR312_StepMetrics_t m;
    ENR312_StepMetrics_Init(&m, ENR312_SETTLE_TO_FINAL, 2.0, 0.02, 0.002);

    /* Rise to 2.5 (25 % overshoot), then settle to 2.0 at t = 1.0 s. */
    for (int k = 0; k <= 500; ++k) {
        double t = k * 0.002;
        double v = (t < 0.5) ? 2.5 : 2.0;
        ENR312_StepMetrics_Update(&m, v, t);
    }
    CHECK_NEAR(m.peak, 2.5, 1e-12, "peak captured");
    CHECK_NEAR(ENR312_StepMetrics_Overshoot(&m), 25.0, 1e-9, "overshoot vs final value");
    /* Last sample outside the +/-2 % band (1.96..2.04) is the last 2.5 sample. */
    CHECK_NEAR(ENR312_StepMetrics_Settling(&m), 0.498, 1e-9, "settling time");
}

static void test_settle_to_zero(void)
{
    ENR312_StepMetrics_t m;
    ENR312_StepMetrics_Init(&m, ENR312_SETTLE_TO_ZERO, 0.0, 0.02, 0.002);

    /* Excursion to -1.0, back to 0 at t = 0.6 s. Band is 2 % of the peak. */
    for (int k = 0; k <= 500; ++k) {
        double t = k * 0.002;
        double v = (t < 0.3) ? -1.0 : 0.0;
        ENR312_StepMetrics_Update(&m, v, t);
    }
    CHECK_NEAR(m.peak, 1.0, 1e-12, "peak uses magnitude, sign-independent");
    CHECK_NEAR(ENR312_StepMetrics_Settling(&m), 0.298, 1e-9, "settling to a zero band");
    CHECK(isnan(ENR312_StepMetrics_Overshoot(&m)),
          "overshoot is undefined without a final value");
}

static void test_never_leaves_band(void)
{
    ENR312_StepMetrics_t m;
    ENR312_StepMetrics_Init(&m, ENR312_SETTLE_TO_FINAL, 1.0, 0.02, 0.002);
    for (int k = 0; k < 100; ++k) { ENR312_StepMetrics_Update(&m, 1.0, k * 0.002); }
    CHECK_NEAR(ENR312_StepMetrics_Settling(&m), 0.0, 1e-12,
               "a signal already at its final value settles at t = 0");
}

static void test_nan_rejected(void)
{
    ENR312_StepMetrics_t m;
    ENR312_StepMetrics_Init(&m, ENR312_SETTLE_TO_FINAL, 1.0, 0.02, 0.002);
    ENR312_StepMetrics_Update(&m, 2.0, 0.1);
    uint32_t before = m.samples;
    ENR312_StepMetrics_Update(&m, NAN, 0.2);
    ENR312_StepMetrics_Update(&m, INFINITY, 0.3);
    CHECK_EQ_I(m.samples, before, "non-finite samples are rejected, not counted");
    CHECK_NEAR(m.peak, 2.0, 1e-12, "peak not poisoned by NaN");
}

static void test_zero_final_value_guard(void)
{
    ENR312_StepMetrics_t m;
    ENR312_StepMetrics_Init(&m, ENR312_SETTLE_TO_FINAL, 0.0, 0.02, 0.002);
    ENR312_StepMetrics_Update(&m, 1.0, 0.1);
    CHECK(isnan(ENR312_StepMetrics_Overshoot(&m)),
          "overshoot against a zero final value is NaN, not a divide-by-zero");
}

static void test_defaults(void)
{
    ENR312_StepMetrics_t m;
    ENR312_StepMetrics_Init(&m, ENR312_SETTLE_TO_FINAL, 1.0, -1.0, -1.0);
    CHECK_NEAR(m.tol, 0.02, 1e-12, "invalid tolerance falls back to 2 %%");
    CHECK_NEAR(m.ts_s, 0.002, 1e-12, "invalid sample period falls back to 2 ms");
}

int main(void)
{
    printf("EXP004 step-metrics tests\n");
    test_settle_to_final();
    test_settle_to_zero();
    test_never_leaves_band();
    test_nan_rejected();
    test_zero_final_value_guard();
    test_defaults();
    TEST_REPORT("test_enr312_metrics");
    return enr312_tests_failed == 0 ? 0 : 1;
}

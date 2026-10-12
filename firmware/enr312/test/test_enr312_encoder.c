/**
 * @file test_enr312_encoder.c
 * @brief Host unit tests for the EXP001 sensing chain.
 *
 * These tests are the ONLY EXP001 evidence obtainable without the rig, so they
 * are deliberately thorough about the one thing that can be proved without
 * hardware: that the decoding arithmetic is correct.
 *
 * Covers acceptance criteria AC-5 and AC-6 (experiments/EXP001/VALIDATION.md).
 */

#include "enr312_encoder.h"
#include "test_harness.h"
#include <stdlib.h>

/* --- Equation (8): wrapped difference -------------------------------------- */
static void test_wrapped_diff_basic(void)
{
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(10u, 5u),  5, "simple forward");
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(5u, 10u), -5, "simple reverse");
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(0u, 0u),   0, "no motion");

    /* Wrap forward: 65535 -> 0 is +1, not -65535. */
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(0u, 65535u), 1, "wrap up by 1");
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(4u, 65534u), 6, "wrap up by 6");

    /* Wrap backward: 0 -> 65535 is -1, not +65535. */
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(65535u, 0u), -1, "wrap down by 1");
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(65530u, 5u), -11, "wrap down by 11");

    /* The two extremes of the representable range. */
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(32767u, 0u),  32767, "max positive");
    CHECK_EQ_I(ENR312_Encoder_WrappedDiff(32768u, 0u), -32768, "max negative");
}

/* Exhaustive: for every possible signed delta in [-32768, 32767] and a spread
 * of starting points, WrappedDiff must recover the delta exactly. This is a
 * complete proof over the input domain of the delta, not a sample of it. */
static void test_wrapped_diff_exhaustive(void)
{
    const uint16_t starts[] = { 0u, 1u, 12345u, 32767u, 32768u, 60000u, 65535u };
    int bad = 0;
    for (unsigned si = 0; si < sizeof(starts)/sizeof(starts[0]); ++si) {
        for (int32_t d = -32768; d <= 32767; ++d) {
            uint16_t prev = starts[si];
            uint16_t now  = (uint16_t)((int32_t)prev + d);
            if (ENR312_Encoder_WrappedDiff(now, prev) != d) {
                bad++;
            }
        }
    }
    CHECK_EQ_I(bad, 0, "exhaustive delta recovery over 7 x 65536 cases");
}

/* --- Equations (5)-(7): scale and sign -------------------------------------- */
static void test_resolution_constants(void)
{
    CHECK_EQ_I(ENR312_ENCODER_COUNTS_PER_REV, 2400, "600 PPR x4 = 2400");
    CHECK_NEAR(ENR312_ENCODER_DEG_PER_COUNT, 0.15, 1e-12, "0.15 deg/count");
    CHECK_NEAR(ENR312_ENCODER_RAD_PER_COUNT, 0.002617993877991494, 1e-15,
               "2*pi/2400 rad/count");
    /* Cross-check against the UCLA reference constant ENCODER_READ_ANGLE_SCALE. */
    CHECK_NEAR(1.0 / ENR312_ENCODER_DEG_PER_COUNT, 6.666667, 1e-6,
               "counts/deg agrees with reference 6.666667");
}

static void test_angle_scale_and_origin(void)
{
    ENR312_Encoder_t e;
    ENR312_Encoder_Init(&e, 1000u, +1);

    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&e), 0.0, 1e-12, "origin latched at init");

    ENR312_Encoder_Update(&e, 1000u + 2400u);
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&e), 360.0, 1e-9, "one full rev = 360 deg");
    CHECK_EQ_I(ENR312_Encoder_GetRelativeCounts(&e), 2400, "one rev = 2400 counts");

    ENR312_Encoder_Update(&e, 1000u);
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&e), 0.0, 1e-9, "back to origin");
}

static void test_polarity(void)
{
    ENR312_Encoder_t p, n;
    ENR312_Encoder_Init(&p, 0u, +1);
    ENR312_Encoder_Init(&n, 0u, -1);
    ENR312_Encoder_Update(&p, 240u);   /* +240 counts = +36 deg */
    ENR312_Encoder_Update(&n, 240u);
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&p), +36.0, 1e-9, "polarity +1");
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&n), -36.0, 1e-9, "polarity -1");

    /* Any polarity other than -1 must be coerced to +1, never stored raw --
     * a stray 0 would silently zero every angle the system ever reports. */
    ENR312_Encoder_t z;
    ENR312_Encoder_Init(&z, 0u, 0);
    CHECK_EQ_I(z.polarity, 1, "invalid polarity coerced to +1");
    ENR312_Encoder_Init(&z, 0u, 7);
    CHECK_EQ_I(z.polarity, 1, "invalid polarity 7 coerced to +1");
}

/* --- Equations (9)-(10): multi-wrap accumulation ---------------------------- */
static void test_many_wraps_forward(void)
{
    /* Rotate forward 100 full revolutions (240 000 counts) in 500-count steps,
     * which crosses the 16-bit boundary ~3.66 times. The accumulator must land
     * exactly on 240 000 -- no drift, no lost wrap. */
    ENR312_Encoder_t e;
    ENR312_Encoder_Init(&e, 0u, +1);

    const int64_t total = 100 * ENR312_ENCODER_COUNTS_PER_REV;
    int64_t issued = 0;
    uint16_t raw = 0u;
    while (issued < total) {
        int64_t step = (total - issued > 500) ? 500 : (total - issued);
        raw = (uint16_t)(raw + (uint16_t)step);
        issued += step;
        ENR312_Encoder_Update(&e, raw);
    }
    CHECK_EQ_I(ENR312_Encoder_GetRelativeCounts(&e), total, "100 rev forward exact");
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&e), 36000.0, 1e-6, "100 rev = 36000 deg");
    CHECK(e.wrap_events >= 3u, "wrap diagnostic counted at least 3 wraps (got %u)",
          e.wrap_events);
}

static void test_many_wraps_reverse(void)
{
    ENR312_Encoder_t e;
    ENR312_Encoder_Init(&e, 0u, +1);
    const int64_t total = 100 * ENR312_ENCODER_COUNTS_PER_REV;
    int64_t issued = 0;
    uint16_t raw = 0u;
    while (issued < total) {
        int64_t step = (total - issued > 500) ? 500 : (total - issued);
        raw = (uint16_t)(raw - (uint16_t)step);
        issued += step;
        ENR312_Encoder_Update(&e, raw);
    }
    CHECK_EQ_I(ENR312_Encoder_GetRelativeCounts(&e), -total, "100 rev reverse exact");
}

/* Randomised: a long pseudo-random walk with per-sample deltas bounded well
 * inside the half-modulus limit of equation (10). The accumulator must track
 * the independently computed ground truth exactly at every step. */
static void test_random_walk_matches_truth(void)
{
    ENR312_Encoder_t e;
    ENR312_Encoder_Init(&e, 30000u, +1);

    uint16_t raw = 30000u;
    int64_t truth = 0;
    unsigned seed = 20260819u;
    int mismatches = 0;

    for (int i = 0; i < 200000; ++i) {
        seed = seed * 1103515245u + 12345u;
        int32_t d = (int32_t)((seed >> 16) % 4001u) - 2000;  /* [-2000, +2000] */
        raw = (uint16_t)((int32_t)raw + d);
        truth += d;
        ENR312_Encoder_Update(&e, raw);
        if (ENR312_Encoder_GetRelativeCounts(&e) != truth) {
            mismatches++;
        }
    }
    CHECK_EQ_I(mismatches, 0, "200k-sample random walk tracked exactly");
}

/* The half-modulus limit of equation (10) is a real boundary. Verify both that
 * it holds at the edge and that it genuinely fails beyond it -- a guarantee
 * whose failure mode is untested is not a guarantee. */
static void test_half_modulus_boundary(void)
{
    ENR312_Encoder_t e;
    ENR312_Encoder_Init(&e, 0u, +1);
    ENR312_Encoder_Update(&e, 32767u);
    CHECK_EQ_I(ENR312_Encoder_GetRelativeCounts(&e), 32767,
               "delta of +32767 (just inside limit) decoded correctly");

    ENR312_Encoder_t f;
    ENR312_Encoder_Init(&f, 0u, +1);
    ENR312_Encoder_Update(&f, 32768u);
    CHECK_EQ_I(ENR312_Encoder_GetRelativeCounts(&f), -32768,
               "delta of +32768 aliases to -32768, as the theory predicts");

    /* Restate the physical margin so the boundary is understood as unreachable:
     * 32768 counts / 2400 counts-per-rev / 0.002 s = 6826.7 rev/s. */
    double omega_max_rev_s = (double)ENR312_ENCODER_COUNTER_HALF
                           / (double)ENR312_ENCODER_COUNTS_PER_REV
                           / ENR312_CONTROL_PERIOD_S;
    CHECK_NEAR(omega_max_rev_s, 6826.666666, 1e-3,
               "aliasing threshold is 6827 rev/s (equation 10)");
}

/* --- Equations (12)-(14): velocity estimation ------------------------------ */
static void test_velocity_granularity(void)
{
    ENR312_Encoder_t e;
    ENR312_Encoder_Init(&e, 0u, +1);

    /* First sample after Init has no predecessor -> velocity must be 0, not
     * a garbage value derived from uninitialised state. */
    ENR312_Encoder_Update(&e, 0u);
    CHECK_NEAR(ENR312_Encoder_GetVelocityRadS(&e, ENR312_CONTROL_PERIOD_S), 0.0,
               1e-12, "velocity is zero on the first sample");

    /* One count per 2 ms sample = q/Ts = 1.308997 rad/s (equation 13). */
    ENR312_Encoder_Update(&e, 1u);
    CHECK_NEAR(ENR312_Encoder_GetVelocityRadS(&e, ENR312_CONTROL_PERIOD_S),
               1.308996938995747, 1e-9, "one count per sample = 1.309 rad/s");

    /* Ten counts per sample. */
    ENR312_Encoder_Update(&e, 11u);
    CHECK_NEAR(ENR312_Encoder_GetVelocityRadS(&e, ENR312_CONTROL_PERIOD_S),
               13.08996938995747, 1e-9, "ten counts per sample");

    /* Stationary -> exactly zero, with no drift. */
    ENR312_Encoder_Update(&e, 11u);
    CHECK_NEAR(ENR312_Encoder_GetVelocityRadS(&e, ENR312_CONTROL_PERIOD_S), 0.0,
               1e-12, "stationary pendulum reports exactly zero velocity");

    /* Degenerate sample period must not divide by zero. */
    CHECK_NEAR(ENR312_Encoder_GetVelocityRadS(&e, 0.0), 0.0, 1e-12,
               "zero sample period returns 0, not inf/NaN");
}

static void test_set_origin_here(void)
{
    ENR312_Encoder_t e;
    ENR312_Encoder_Init(&e, 0u, +1);
    ENR312_Encoder_Update(&e, 1200u);           /* +180 deg */
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&e), 180.0, 1e-9, "before re-zero");

    ENR312_Encoder_SetOriginHere(&e);
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&e), 0.0, 1e-12, "after re-zero");

    ENR312_Encoder_Update(&e, 1200u + 240u);
    CHECK_NEAR(ENR312_Encoder_GetAngleDeg(&e), 36.0, 1e-9, "relative to new origin");
}

int main(void)
{
    printf("EXP001 sensing-chain unit tests (parameter set %s)\n",
           ENR312_PARAMETER_SET_ID);

    test_wrapped_diff_basic();
    test_wrapped_diff_exhaustive();
    test_resolution_constants();
    test_angle_scale_and_origin();
    test_polarity();
    test_many_wraps_forward();
    test_many_wraps_reverse();
    test_random_walk_matches_truth();
    test_half_modulus_boundary();
    test_velocity_granularity();
    test_set_origin_here();

    TEST_REPORT("test_enr312_encoder");
    return enr312_tests_failed == 0 ? 0 : 1;
}

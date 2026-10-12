/**
 * @file test_enr312_rotor.c
 * @brief Host unit tests for the EXP001 actuation chain.
 *
 * Covers acceptance criteria AC-5 and AC-7 (experiments/EXP001/VALIDATION.md).
 *
 * NOTE ON WHAT THESE TESTS CAN AND CANNOT SHOW. They verify the COMMAND MODEL
 * -- equation (1) and the timer arithmetic of equations (2)-(3). They cannot
 * verify that the physical arm follows the command, because nothing in this
 * system measures the arm. That is prediction P1/P3 and needs the rig.
 */

#include "enr312_rotor.h"
#include "test_harness.h"

static void test_actuation_constants(void)
{
    CHECK_EQ_I(ENR312_ROTOR_MICROSTEPS_PER_REV, 3200, "200 full steps x 16 = 3200");
    CHECK_NEAR(ENR312_ROTOR_DEG_PER_MICROSTEP, 0.1125, 1e-12, "0.1125 deg/microstep");
    CHECK_NEAR(ENR312_ROTOR_RAD_PER_MICROSTEP, 0.001963495408493621, 1e-15,
               "2*pi/3200 rad/microstep");
    /* Cross-check against reference STEPPER_READ_POSITION_STEPS_PER_DEGREE. */
    CHECK_NEAR(1.0 / ENR312_ROTOR_DEG_PER_MICROSTEP, 8.888889, 1e-6,
               "microsteps/deg agrees with reference 8.888889");
    /* The reference's two scales are in the ratio 6.666667/8.888889 = 0.75.
     * Reproducing it exactly confirms both chains are consistent with the
     * reference rig's geometry. */
    CHECK_NEAR((1.0 / ENR312_ENCODER_DEG_PER_COUNT) /
               (1.0 / ENR312_ROTOR_DEG_PER_MICROSTEP), 0.75, 1e-9,
               "encoder/stepper scale ratio = 0.75");
}

static void test_move_and_angle(void)
{
    ENR312_Rotor_t r;
    ENR312_Rotor_Init(&r, +1);
    CHECK_NEAR(ENR312_Rotor_GetAngleDeg(&r), 0.0, 1e-12, "origin at init");

    int64_t actual = 0;
    /* The handout's two commanded angles. +45 deg = 400 microsteps exactly. */
    CHECK_EQ_I(ENR312_Rotor_GoToDegrees(&r, 45.0, &actual), ENR312_ROTOR_OK, "goto +45");
    CHECK_EQ_I(actual, 400, "+45 deg = 400 microsteps");
    CHECK_NEAR(ENR312_Rotor_GetAngleDeg(&r), 45.0, 1e-12, "angle after +45");

    /* -90 deg = -800 microsteps; from +400 that is a delta of -1200. */
    CHECK_EQ_I(ENR312_Rotor_GoToDegrees(&r, -90.0, &actual), ENR312_ROTOR_OK, "goto -90");
    CHECK_EQ_I(actual, -1200, "delta from +45 to -90 = -1200 microsteps");
    CHECK_NEAR(ENR312_Rotor_GetAngleDeg(&r), -90.0, 1e-12, "angle after -90");

    CHECK_EQ_I(ENR312_Rotor_GoToDegrees(&r, 0.0, &actual), ENR312_ROTOR_OK, "return");
    CHECK_EQ_I(r.position_microsteps, 0, "net zero after closed sequence");
}

/* P3 in software: a closed sequence must return the position model exactly to
 * zero. If this fails the firmware has a bug; if it passes and the HARDWARE
 * still drifts, the drift is lost steps. That separation is the value of the
 * test. */
static void test_zero_net_cycles(void)
{
    ENR312_Rotor_t r;
    ENR312_Rotor_Init(&r, +1);
    for (int i = 0; i < 10; ++i) {
        ENR312_Rotor_GoToDegrees(&r, +90.0, NULL);
        ENR312_Rotor_GoToDegrees(&r,   0.0, NULL);
        ENR312_Rotor_GoToDegrees(&r, -90.0, NULL);
        ENR312_Rotor_GoToDegrees(&r,   0.0, NULL);
    }
    CHECK_EQ_I(r.position_microsteps, 0, "10 zero-net cycles leave position at 0");
    CHECK_EQ_I(r.clamp_events, 0, "no limit was touched during P3");
}

static void test_travel_limits(void)
{
    ENR312_Rotor_t r;
    ENR312_Rotor_Init(&r, +1);
    /* 240 deg limit = 240 * 8.888889 = 2133 microsteps (truncated). */
    CHECK_EQ_I(r.limit_microsteps, 2133, "limit in microsteps");

    int64_t actual = 0;
    ENR312_RotorStatus_t st = ENR312_Rotor_GoToDegrees(&r, 300.0, &actual);
    CHECK_EQ_I(st, ENR312_ROTOR_CLAMPED_TO_LIMIT, "beyond +limit is clamped");
    CHECK_EQ_I(r.position_microsteps, 2133, "clamped to +limit exactly");
    CHECK_EQ_I(r.clamp_events, 1, "clamp counted");

    st = ENR312_Rotor_GoToDegrees(&r, -300.0, &actual);
    CHECK_EQ_I(st, ENR312_ROTOR_CLAMPED_TO_LIMIT, "beyond -limit is clamped");
    CHECK_EQ_I(r.position_microsteps, -2133, "clamped to -limit exactly");

    /* A clamp must be a truncation, not a rejection: motion up to the limit is
     * still issued, so `actual` is non-zero and the model stays consistent with
     * what the hardware was told to do. */
    CHECK(actual != 0, "clamped move still issues partial motion");

    /* Inside the limit is untouched. */
    ENR312_Rotor_t q;
    ENR312_Rotor_Init(&q, +1);
    CHECK_EQ_I(ENR312_Rotor_GoToDegrees(&q, 239.0, NULL), ENR312_ROTOR_OK,
               "239 deg is inside the limit");
}

static void test_rejects_non_finite(void)
{
    ENR312_Rotor_t r;
    ENR312_Rotor_Init(&r, +1);
    int64_t actual = 99;
    CHECK_EQ_I(ENR312_Rotor_MoveDegrees(&r, 1.0 / 0.0, &actual),
               ENR312_ROTOR_REJECTED, "infinite move rejected");
    CHECK_EQ_I(actual, 0, "rejected move reports zero motion");
    CHECK_EQ_I(r.position_microsteps, 0, "rejected move does not change position");
    CHECK_EQ_I(ENR312_Rotor_GoToDegrees(&r, 0.0 / 0.0, &actual),
               ENR312_ROTOR_REJECTED, "NaN target rejected");
}

/* Equations (2)-(3): step-rate quantisation, and the numbers quoted in
 * FIRST_PRINCIPLES.md section 2.3 / prediction P5. */
static void test_step_timer_arr(void)
{
    ENR312_Rotor_t r;
    ENR312_Rotor_Init(&r, +1);
    r.max_step_rate_hz = 20000u;   /* widen past the EXP001 cap for this test */

    uint32_t arr = 0;
    double   act = 0.0;

    CHECK_EQ_I(ENR312_Rotor_ComputeStepTimerARR(&r, 1000u, &arr, &act),
               ENR312_ROTOR_OK, "1000 Hz accepted");
    CHECK_EQ_I(arr, 81, "ARR for 1000 steps/s");
    CHECK_NEAR(act, 1000.381, 1e-3, "achieved rate at 1000 steps/s");
    CHECK(fabs(act - 1000.0) / 1000.0 < 0.001, "error under 0.1%% at 1000 steps/s");

    CHECK_EQ_I(ENR312_Rotor_ComputeStepTimerARR(&r, 2000u, &arr, &act),
               ENR312_ROTOR_OK, "2000 Hz accepted");
    CHECK_EQ_I(arr, 40, "ARR for 2000 steps/s");
    CHECK(fabs(act - 2000.0) / 2000.0 < 0.001, "error under 0.1%% at 2000 steps/s");

    /* At 10 kHz only 8 timer ticks remain per step and the error is large.
     * This is prediction P5's second half and it is a real design limit, so it
     * is asserted rather than merely mentioned. */
    CHECK_EQ_I(ENR312_Rotor_ComputeStepTimerARR(&r, 10000u, &arr, &act),
               ENR312_ROTOR_OK, "10000 Hz accepted");
    CHECK_EQ_I(arr, 7, "ARR for 10000 steps/s");
    CHECK_NEAR(act, 10253.906, 1e-2, "achieved rate at 10000 steps/s");
    CHECK(fabs(act - 10000.0) / 10000.0 > 0.02,
          "error exceeds 2%% at 10000 steps/s, as predicted");

    /* The tick rate itself -- fractional, and it must stay fractional.
     * A regression that truncates it to 82031 would pass an integer check but
     * bias every predicted step rate by -3 ppm. */
    CHECK_NEAR(ENR312_STEP_TICK_HZ, 82031.25, 1e-9,
               "84 MHz / 1024 = 82031.25 Hz exactly, not truncated");
}

static void test_step_rate_clamped_and_rejected(void)
{
    ENR312_Rotor_t r;
    ENR312_Rotor_Init(&r, +1);
    CHECK_EQ_I(r.max_step_rate_hz, ENR312_EXP001_MAX_STEP_RATE_HZ,
               "EXP001 rate cap applied at init");

    uint32_t arr = 0;
    double   act = 0.0;
    CHECK_EQ_I(ENR312_Rotor_ComputeStepTimerARR(&r, 9000u, &arr, &act),
               ENR312_ROTOR_RATE_CLAMPED, "request above cap is clamped");
    CHECK_EQ_I(arr, 81, "clamped request yields the 1000 steps/s ARR");

    CHECK_EQ_I(ENR312_Rotor_ComputeStepTimerARR(&r, 0u, &arr, &act),
               ENR312_ROTOR_REJECTED, "zero rate rejected, no divide by zero");
    CHECK_EQ_I(ENR312_Rotor_ComputeStepTimerARR(&r, 1000u, NULL, &act),
               ENR312_ROTOR_REJECTED, "NULL output rejected");
}

static void test_step_rate_to_velocity(void)
{
    /* Equation (4): 1000 steps/s -> 1.9635 rad/s -> 112.5 deg/s. */
    CHECK_NEAR(ENR312_Rotor_StepRateToRadS(1000.0), 1.963495408493621, 1e-9,
               "1000 steps/s in rad/s");
    CHECK_NEAR(ENR312_Rotor_StepRateToRadS(1000.0) * 180.0 / 3.14159265358979, 112.5,
               1e-6, "1000 steps/s in deg/s");
}

static void test_polarity(void)
{
    ENR312_Rotor_t p, n;
    ENR312_Rotor_Init(&p, +1);
    ENR312_Rotor_Init(&n, -1);
    ENR312_Rotor_MoveMicrosteps(&p, 400, NULL);
    ENR312_Rotor_MoveMicrosteps(&n, 400, NULL);
    CHECK_NEAR(ENR312_Rotor_GetAngleDeg(&p), +45.0, 1e-12, "rotor polarity +1");
    CHECK_NEAR(ENR312_Rotor_GetAngleDeg(&n), -45.0, 1e-12, "rotor polarity -1");
}

int main(void)
{
    printf("EXP001 actuation-chain unit tests (parameter set %s)\n",
           ENR312_PARAMETER_SET_ID);

    test_actuation_constants();
    test_move_and_angle();
    test_zero_net_cycles();
    test_travel_limits();
    test_rejects_non_finite();
    test_step_timer_arr();
    test_step_rate_clamped_and_rejected();
    test_step_rate_to_velocity();
    test_polarity();

    TEST_REPORT("test_enr312_rotor");
    return enr312_tests_failed == 0 ? 0 : 1;
}

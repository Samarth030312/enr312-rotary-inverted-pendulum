/**
 * @file    enr312_rotor.c
 * @brief   EXP001 actuation chain implementation. See enr312_rotor.h.
 */

#include "enr312_rotor.h"
#include <math.h>
#include <stddef.h>

void ENR312_Rotor_Init(ENR312_Rotor_t *r, int32_t polarity)
{
    r->position_microsteps = 0;
    r->polarity            = (polarity == -1) ? -1 : +1;
    r->limit_microsteps    = (int64_t)(ENR312_ROTOR_LIMIT_DEG
                                       * (double)ENR312_ROTOR_MICROSTEPS_PER_REV / 360.0);
    r->max_step_rate_hz    = ENR312_EXP001_MAX_STEP_RATE_HZ;
    r->clamp_events        = 0u;
}

ENR312_RotorStatus_t ENR312_Rotor_MoveMicrosteps(ENR312_Rotor_t *r,
                                                 int64_t delta_microsteps,
                                                 int64_t *actual_out)
{
    int64_t target = r->position_microsteps + delta_microsteps;
    ENR312_RotorStatus_t st = ENR312_ROTOR_OK;

    if (target > r->limit_microsteps) {
        target = r->limit_microsteps;
        st = ENR312_ROTOR_CLAMPED_TO_LIMIT;
    } else if (target < -r->limit_microsteps) {
        target = -r->limit_microsteps;
        st = ENR312_ROTOR_CLAMPED_TO_LIMIT;
    }

    if (st == ENR312_ROTOR_CLAMPED_TO_LIMIT) {
        r->clamp_events++;
    }

    int64_t actual = target - r->position_microsteps;
    r->position_microsteps = target;

    if (actual_out != NULL) {
        *actual_out = actual;
    }
    return st;
}

ENR312_RotorStatus_t ENR312_Rotor_MoveDegrees(ENR312_Rotor_t *r,
                                              double delta_deg,
                                              int64_t *actual_out)
{
    if (!isfinite(delta_deg)) {
        if (actual_out != NULL) { *actual_out = 0; }
        return ENR312_ROTOR_REJECTED;
    }
    /* Round to nearest microstep. The residual (< half a microstep, 0.056 deg)
     * is discarded rather than carried forward: EXP001 issues a small number of
     * discrete moves, so accumulating a fractional remainder would add state
     * whose only effect is to make the commanded position harder to reason
     * about. If a future experiment issues many small moves, revisit this. */
    double usteps = delta_deg * (double)ENR312_ROTOR_MICROSTEPS_PER_REV / 360.0;
    return ENR312_Rotor_MoveMicrosteps(r, (int64_t)llround(usteps), actual_out);
}

ENR312_RotorStatus_t ENR312_Rotor_GoToDegrees(ENR312_Rotor_t *r,
                                              double target_deg,
                                              int64_t *actual_out)
{
    if (!isfinite(target_deg)) {
        if (actual_out != NULL) { *actual_out = 0; }
        return ENR312_ROTOR_REJECTED;
    }
    double target_usteps = target_deg * (double)ENR312_ROTOR_MICROSTEPS_PER_REV / 360.0;
    int64_t delta = (int64_t)llround(target_usteps) - r->position_microsteps;
    return ENR312_Rotor_MoveMicrosteps(r, delta, actual_out);
}

double ENR312_Rotor_GetAngleRad(const ENR312_Rotor_t *r)
{
    return (double)r->polarity * (double)r->position_microsteps
         * ENR312_ROTOR_RAD_PER_MICROSTEP;
}

double ENR312_Rotor_GetAngleDeg(const ENR312_Rotor_t *r)
{
    return (double)r->polarity * (double)r->position_microsteps
         * ENR312_ROTOR_DEG_PER_MICROSTEP;
}

void ENR312_Rotor_SetOriginHere(ENR312_Rotor_t *r)
{
    r->position_microsteps = 0;
}

ENR312_RotorStatus_t ENR312_Rotor_ComputeStepTimerARR(const ENR312_Rotor_t *r,
                                                      uint32_t requested_hz,
                                                      uint32_t *arr_out,
                                                      double   *actual_hz_out)
{
    if (arr_out == NULL || requested_hz == 0u) {
        return ENR312_ROTOR_REJECTED;
    }

    ENR312_RotorStatus_t st = ENR312_ROTOR_OK;
    uint32_t hz = requested_hz;
    if (hz > r->max_step_rate_hz) {
        hz = r->max_step_rate_hz;
        st = ENR312_ROTOR_RATE_CLAMPED;
    }

    /* Equation (2). Round-to-nearest rather than truncate, so the achieved rate
     * straddles the request instead of being biased high.
     *
     * The division is done in floating point against the exact tick rate
     * (82031.25 Hz). Doing it in integer arithmetic against a truncated
     * 82031 Hz would bias every predicted rate low by 3 ppm and put the
     * firmware quietly out of agreement with the derivation. */
    double exact_divisor = ENR312_STEP_TICK_HZ / (double)hz;
    uint32_t divisor = (uint32_t)(exact_divisor + 0.5);
    if (divisor == 0u) {
        divisor = 1u;
    }
    *arr_out = divisor - 1u;

    if (actual_hz_out != NULL) {
        /* Equation (3). */
        *actual_hz_out = ENR312_STEP_TICK_HZ / (double)divisor;
    }
    return st;
}

double ENR312_Rotor_StepRateToRadS(double step_rate_hz)
{
    return step_rate_hz * ENR312_ROTOR_RAD_PER_MICROSTEP;   /* Equation (4) */
}

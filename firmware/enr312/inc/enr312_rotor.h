/**
 * @file    enr312_rotor.h
 * @brief   EXP001 actuation chain: microstep command -> rotor arm angle.
 *
 * Implements equations (1)-(4) of experiments/EXP001/FIRST_PRINCIPLES.md.
 *
 * The rotor has NO position sensor. Its position is not measured; it is
 * commanded and remembered. This module IS that memory, and its correctness is
 * exactly as good as assumption A2 ("no steps are lost"). It cannot detect step
 * loss -- nothing in the system can. EXP001 prediction P3 is the only check.
 *
 * HAL-free by design, so it is host-testable.
 */

#ifndef ENR312_ROTOR_H
#define ENR312_ROTOR_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENR312_ROTOR_OK = 0,
    ENR312_ROTOR_CLAMPED_TO_LIMIT,  /**< move truncated at a travel limit    */
    ENR312_ROTOR_RATE_CLAMPED,      /**< step rate reduced to the EXP001 cap */
    ENR312_ROTOR_REJECTED           /**< invalid argument; no motion issued  */
} ENR312_RotorStatus_t;

typedef struct {
    int64_t  position_microsteps;   /**< net commanded microsteps since origin */
    int32_t  polarity;              /**< +1 or -1; actuation-chain convention  */
    int64_t  limit_microsteps;      /**< +/- travel limit, in microsteps       */
    uint32_t max_step_rate_hz;      /**< commanded-rate ceiling                */
    uint32_t clamp_events;          /**< diagnostic: limit hits                */
} ENR312_Rotor_t;

/** @brief Initialise; latches the present arm position as the zero datum. */
void ENR312_Rotor_Init(ENR312_Rotor_t *r, int32_t polarity);

/**
 * @brief Command a relative move, clamped to the travel limit.
 *
 * @param delta_microsteps  signed request
 * @param actual_out        microsteps actually accepted (may be truncated)
 * @return status; CLAMPED_TO_LIMIT when the request crossed a travel limit.
 *
 * Clamping is a truncation, not a rejection: partial motion up to the limit is
 * issued. A move that would exceed the limit is a caller error, and the
 * clamp_events counter exists so it cannot pass unnoticed.
 */
ENR312_RotorStatus_t ENR312_Rotor_MoveMicrosteps(ENR312_Rotor_t *r,
                                                 int64_t delta_microsteps,
                                                 int64_t *actual_out);

/** @brief Command a relative move expressed in degrees (rounded to nearest microstep). */
ENR312_RotorStatus_t ENR312_Rotor_MoveDegrees(ENR312_Rotor_t *r,
                                              double delta_deg,
                                              int64_t *actual_out);

/** @brief Command an absolute target angle in degrees, relative to the origin. */
ENR312_RotorStatus_t ENR312_Rotor_GoToDegrees(ENR312_Rotor_t *r,
                                              double target_deg,
                                              int64_t *actual_out);

/** @brief Commanded arm angle, radians.  Equation (1). */
double ENR312_Rotor_GetAngleRad(const ENR312_Rotor_t *r);

/** @brief Commanded arm angle, degrees. */
double ENR312_Rotor_GetAngleDeg(const ENR312_Rotor_t *r);

/** @brief Re-latch the origin here. */
void ENR312_Rotor_SetOriginHere(ENR312_Rotor_t *r);

/**
 * @brief Timer auto-reload for a requested step rate.  Equations (2)-(3).
 *
 * @param requested_hz  desired step rate; clamped to [1, max_step_rate_hz]
 * @param arr_out       resulting ARR value
 * @param actual_hz_out achieved rate after integer rounding
 * @return RATE_CLAMPED if the request was reduced, REJECTED if arguments are
 *         unusable, otherwise OK.
 *
 * The achievable rate is quantised because ARR is an integer. Below 2000
 * steps/s the relative error is under 0.04 %; at 10000 steps/s it is +2.54 %.
 * This is a rate error, not a position error -- the position model counts
 * pulses issued, not their spacing.
 */
ENR312_RotorStatus_t ENR312_Rotor_ComputeStepTimerARR(const ENR312_Rotor_t *r,
                                                      uint32_t requested_hz,
                                                      uint32_t *arr_out,
                                                      double   *actual_hz_out);

/** @brief Arm angular velocity for a given step rate, rad/s.  Equation (4). */
double ENR312_Rotor_StepRateToRadS(double step_rate_hz);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_ROTOR_H */

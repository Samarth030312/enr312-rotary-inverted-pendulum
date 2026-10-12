/**
 * @file    enr312_encoder.h
 * @brief   EXP001 sensing chain: wrap-safe quadrature counter -> pendulum angle.
 *
 * Implements equations (7)-(14) of experiments/EXP001/FIRST_PRINCIPLES.md.
 *
 * This module is intentionally free of HAL/CMSIS dependencies. It consumes a
 * raw counter value that the caller reads from the timer; it does not know
 * what a timer is. That is what makes it unit-testable on the host, and the
 * host tests are the only EXP001 evidence obtainable without the rig.
 */

#ifndef ENR312_ENCODER_H
#define ENR312_ENCODER_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint16_t last_raw;        /**< previous hardware counter value            */
    int64_t  accum_counts;    /**< accumulated signed counts since origin     */
    int64_t  origin_counts;   /**< datum subtracted to form the reported angle*/
    int32_t  polarity;        /**< +1 or -1; sensing-chain sign convention    */
    int64_t  prev_rel_counts; /**< previous relative count, for velocity      */
    bool     have_prev;       /**< false until the first Update after Reset   */
    uint32_t wrap_events;     /**< diagnostic: number of counter wraps seen   */
} ENR312_Encoder_t;

/**
 * @brief Initialise the decoder and latch the origin at the current counter.
 *
 * After this call the reported angle is exactly zero. The origin is arbitrary
 * -- an incremental encoder has no absolute reference and cannot have one.
 * Giving the origin physical meaning is EXP002's job.
 *
 * @param polarity  +1 or -1. Any other value is rejected and +1 is used.
 */
void ENR312_Encoder_Init(ENR312_Encoder_t *e, uint16_t raw_now, int32_t polarity);

/**
 * @brief Consume one new hardware counter sample.
 *
 * Applies the modular difference of equation (8) and accumulates per (9). Safe
 * across arbitrary 16-bit wraps provided the true motion between samples is
 * less than half a counter period -- which for this rig means below ~6827
 * rev/s (equation 10), i.e. unconditionally.
 */
void ENR312_Encoder_Update(ENR312_Encoder_t *e, uint16_t raw_now);

/** @brief Relative count since the origin (polarity NOT applied). */
int64_t ENR312_Encoder_GetRelativeCounts(const ENR312_Encoder_t *e);

/** @brief Pendulum angle in radians: s * (C - C0) * q.  Equation (7)/(9). */
double ENR312_Encoder_GetAngleRad(const ENR312_Encoder_t *e);

/** @brief Pendulum angle in degrees. Display only; models use radians. */
double ENR312_Encoder_GetAngleDeg(const ENR312_Encoder_t *e);

/**
 * @brief Backward-difference angular velocity, rad/s.  Equation (12).
 *
 * Returns 0.0 on the first sample after Init (no previous sample exists).
 *
 * CAUTION -- this estimator is quantised at q/Ts = 1.309 rad/s and carries
 * sigma = 0.534 rad/s of noise at Ts = 2 ms (equations 13-14). It is provided
 * for EXP001 observation. It must NOT be fed to a derivative gain unfiltered;
 * see FIRST_PRINCIPLES.md section 3.5.
 */
double ENR312_Encoder_GetVelocityRadS(const ENR312_Encoder_t *e, double ts_s);

/** @brief Re-latch the origin to the present position (zeroing). */
void ENR312_Encoder_SetOriginHere(ENR312_Encoder_t *e);

/**
 * @brief Wrap-safe signed difference of two raw counter values. Equation (8).
 *
 * Exposed because it is the single most error-prone line in the sensing chain
 * and is therefore tested directly and exhaustively.
 */
int32_t ENR312_Encoder_WrappedDiff(uint16_t now, uint16_t prev);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_ENCODER_H */

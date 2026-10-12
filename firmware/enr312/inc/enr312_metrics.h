/**
 * @file    enr312_metrics.h
 * @brief   Online step-response metrics for any measured signal.
 *
 * WHY THIS EXISTS
 * ---------------
 * Tutorial 4 section 1 states the addition EXP004 makes over EXP003: "application
 * of a Reference Tracking input signal to the MIMO system results in Pendulum
 * Angle displacement in addition to Rotor Angle. This Tutorial will be directed
 * to a design with objectives to meet requirements on Settling Time for BOTH
 * Rotor Angle as well as Pendulum Angle."
 *
 * EXP003 measured the rotor only. EXP004 needs the same measurements on the
 * pendulum channel, so the metric accumulator is factored out here and applied to
 * both channels rather than duplicated.
 *
 * EXP004 REQUIRES NO OTHER NEW FIRMWARE. Its sensitivity-function analysis
 * (M_S, w_SC, Nyquist) is performed offline on the step-response data EXP003's
 * telemetry already carries. Adding an on-target frequency-response computation
 * would cost flash and RAM for something the host does better, so it is not done.
 *
 * TWO SETTLING CONVENTIONS, BOTH NEEDED
 * -------------------------------------
 * The rotor tracks a non-zero reference, so its settling is measured against a
 * final value. The pendulum is displaced and returns towards zero, so it has no
 * meaningful "final value" to settle to -- its settling is measured as the last
 * time it was outside a band around ZERO, scaled to its own peak excursion.
 * Using the rotor convention on the pendulum would divide by a final value of
 * ~0 and produce nonsense.
 *
 * HAL-free, host-testable, zero static allocation.
 */

#ifndef ENR312_METRICS_H
#define ENR312_METRICS_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Which zero-reference convention the settling test uses. */
typedef enum {
    ENR312_SETTLE_TO_FINAL = 0,  /**< band around a supplied final value (rotor)  */
    ENR312_SETTLE_TO_ZERO        /**< band around zero, scaled to peak (pendulum) */
} ENR312_SettleMode_t;

typedef struct {
    ENR312_SettleMode_t mode;
    double   tol;             /**< fractional band, e.g. 0.02 for 2 %            */
    double   final_value;     /**< used only in ENR312_SETTLE_TO_FINAL           */
    double   ts_s;

    double   peak;            /**< max |signal| seen                              */
    double   peak_time_s;
    double   last_outside_s;  /**< last time the signal was outside the band      */
    uint32_t samples;
    bool     any_sample;
} ENR312_StepMetrics_t;

/**
 * @brief Initialise an accumulator.
 * @param final_value  target for ENR312_SETTLE_TO_FINAL; ignored otherwise.
 *                     Must be non-zero in that mode, or every sample counts as
 *                     outside the band.
 */
void ENR312_StepMetrics_Init(ENR312_StepMetrics_t *m, ENR312_SettleMode_t mode,
                             double final_value, double tol, double ts_s);

/** @brief Consume one sample at time t_s. */
void ENR312_StepMetrics_Update(ENR312_StepMetrics_t *m, double value, double t_s);

/** @brief Overshoot in percent of the final value. SETTLE_TO_FINAL only; NaN otherwise. */
double ENR312_StepMetrics_Overshoot(const ENR312_StepMetrics_t *m);

/**
 * @brief Settling time in seconds.
 *
 * In SETTLE_TO_ZERO mode the band is `tol * peak`, so the answer is only
 * meaningful once the peak has actually occurred. Returns 0 if the signal never
 * left the band.
 */
double ENR312_StepMetrics_Settling(const ENR312_StepMetrics_t *m);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_METRICS_H */

/**
 * @file    enr312_pd.h
 * @brief   EXP002 (Tutorial 2) discrete PD controller for the rotor loop.
 *
 * Implements  C(s) = Kp + Kd*s,  Kd = Kp*Td   (Tutorial 1 section 2, Tutorial 2 section 1)
 *
 * WHY A FILTERED DERIVATIVE, AND WHY THIS CORNER FREQUENCY
 * --------------------------------------------------------
 * An ideal derivative is not implementable and, more importantly, is not
 * *desirable* here. EXP001 established the numbers that force the decision:
 * a raw backward-difference velocity estimate from the 2400 count/rev encoder at
 * Ts = 2 ms is quantised at q/Ts = 1.309 rad/s and carries sigma = 0.534 rad/s
 * (FIRST_PRINCIPLES.md equations 13-14). Feeding that to a gain Kd would inject
 * roughly 0.534*Kd of noise straight into the actuator command.
 *
 * A first-order low-pass on the derivative term with corner f_c reduces that noise
 * by sqrt(a/(2-a)) with a = 1 - exp(-2*pi*f_c*Ts). At f_c = 10 Hz and Ts = 2 ms the
 * factor is 0.254, taking sigma from 0.534 to 0.136 rad/s.
 *
 * 10 Hz is therefore a derived default, not an inherited constant -- although it
 * happens to coincide with the UCLA reference's DERIVATIVE_LOW_PASS_CORNER_FREQUENCY.
 *
 * PLANT ASSUMPTION -- OPEN ITEM OI-7
 * ---------------------------------
 * Tutorial 1 gives the rotor plant as G_Rotor(s) = 1/s^2, i.e. the controller output
 * u is interpreted as a rotor ANGULAR ACCELERATION command. The mapping from u to the
 * stepper actuator is NOT verified on this rig and is deliberately kept outside this
 * module (see ENR312_PD_Output for the contract). Do not bake a mapping in here.
 *
 * HAL-free, so it is host-testable.
 */

#ifndef ENR312_PD_H
#define ENR312_PD_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Default derivative low-pass corner. Derived from EXP001 equations 13-14. */
#define ENR312_PD_DEFAULT_DERIV_FC_HZ   10.0

/** Symmetric saturation on the controller output, in the units of u.
 *  Saturation is a SAFETY limit, not a tuning parameter. It exists so that a
 *  mis-entered gain cannot command an unbounded actuator effort. */
#define ENR312_PD_DEFAULT_U_LIMIT       50.0

typedef struct {
    double kp;              /**< proportional gain                              */
    double kd;              /**< derivative gain, Kd = Kp*Td                    */
    double ts_s;            /**< sample period [s]                             */
    double deriv_alpha;     /**< low-pass coefficient a = 1-exp(-2*pi*fc*Ts)   */
    double u_limit;         /**< symmetric output saturation                    */

    double prev_error;      /**< e[k-1]                                        */
    double deriv_state;     /**< filtered derivative state                     */
    bool   have_prev;       /**< false until the first Update after Init       */

    /* Diagnostics -- cheap, and they turn "the rig behaved oddly" into evidence. */
    uint32_t saturation_events;
} ENR312_PD_t;

/** One controller evaluation, all signals of Tutorial 2 Figure 1. */
typedef struct {
    double reference;       /**< R  -- reference tracking input                */
    double disturbance;     /**< D  -- load disturbance, added at PLANT INPUT  */
    double noise;           /**< N  -- measurement noise, added at the SENSOR  */
    double measured;        /**< Y  -- plant output as seen without noise      */
    double error;           /**< e = R - (Y + N)                               */
    double u_unsat;         /**< controller output before saturation           */
    double u;               /**< U  -- plant input = sat(u_unsat) + D          */
} ENR312_PD_Signals_t;

/**
 * @brief Initialise the controller.
 * @param kp,kd  gains; Kd = Kp*Td
 * @param ts_s   sample period [s], must be > 0
 * @param fc_hz  derivative low-pass corner [Hz]; <= 0 disables filtering
 *               (NOT recommended -- see the header comment)
 */
void ENR312_PD_Init(ENR312_PD_t *c, double kp, double kd, double ts_s, double fc_hz);

/** @brief Set the symmetric output saturation limit. */
void ENR312_PD_SetOutputLimit(ENR312_PD_t *c, double limit);

/** @brief Reset the internal state without changing the gains. */
void ENR312_PD_Reset(ENR312_PD_t *c);

/**
 * @brief Evaluate one control step, filling every Tutorial 2 signal.
 *
 * Signal topology follows Tutorial 2 Figure 1 exactly:
 *
 *     R --->(+)--- e --->[ C(s) ]--- u ---->(+)--- U ---->[ P(s) ]---> Y
 *            ^-                                  ^
 *            |                                   |
 *            +------- (Y + N) <------------------+--- D
 *
 * @param sig  in: reference, disturbance, noise, measured.  out: error, u_unsat, u.
 *
 * The derivative acts on the ERROR, so a reference step produces a derivative
 * kick. That is the textbook form Tutorial 2 specifies and it is kept, because
 * EXP002's whole purpose is to measure the sensitivity functions of exactly this
 * controller. Derivative-on-measurement would change T(s) and invalidate the
 * comparison against the model.
 */
void ENR312_PD_Update(ENR312_PD_t *c, ENR312_PD_Signals_t *sig);

/** @brief Convert a corner frequency to the first-order filter coefficient. */
double ENR312_PD_AlphaFromFc(double fc_hz, double ts_s);

/**
 * @brief Predicted steady-state offset under a unit load-disturbance step.
 *
 * Equals 1/Kp for P(s) = 1/s^2 with a PD controller. A PD controller has no
 * integral action, so a constant load leaves a PERMANENT offset -- the response
 * never returns to zero. This is why Tutorial 2 warns of "extended settling time"
 * and why Tutorial 6 introduces integral action. Exposed so firmware and analysis
 * agree on the number rather than each deriving it separately.
 */
double ENR312_PD_LoadDisturbanceOffset(const ENR312_PD_t *c);

/**
 * @brief Predicted PEAK controller demand for a reference step of `amplitude`.
 *
 *     u_peak = amplitude * (Kp + Kd*alpha/Ts)
 *
 * WHY THIS EXISTS. Derivative-on-error means a reference STEP produces an
 * enormous first-sample derivative: the error jumps by the full amplitude in one
 * sample, so de/dt = amplitude/Ts. With Kp = 5, Kd = 2.5, alpha = 0.11809 and
 * Ts = 2 ms the derivative term is 147.5*amplitude against a proportional term of
 * only 5*amplitude -- about 30x larger.
 *
 * If that demand exceeds the output limit the loop clips, and a clipped loop is
 * NONLINEAR. Its measured "sensitivity function" is then not a sensitivity
 * function at all. EXP002 must therefore choose the excitation amplitude and the
 * output limit together so that this prediction stays inside the limit.
 *
 * Call it before running, not after wondering why the data looks wrong.
 */
double ENR312_PD_PredictStepDemand(const ENR312_PD_t *c, double amplitude);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_PD_H */

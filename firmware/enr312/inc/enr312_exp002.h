/**
 * @file    enr312_exp002.h
 * @brief   EXP002 (Tutorial 2) sensitivity-function measurement sequencer.
 *
 * Tutorial 2 measures two closed-loop transfer functions on the rotor loop:
 *
 *   Complementary sensitivity   T(s)  = PC/(1+PC)   -- reference tracking
 *       excited by a step on R with D = N = 0
 *   Load-disturbance sensitivity SD(s) = P/(1+PC)   -- disturbance rejection
 *       excited by a step on D with R = N = 0
 *
 * This module runs those two excitations as an explicit state machine and emits
 * one telemetry record per control tick carrying every signal of Tutorial 2
 * Figure 1 (R, D, N, e, U, Y), which is exactly what the offline analysis needs.
 *
 * SCOPE DISCIPLINE. EXP002 is the ROTOR LOOP ONLY. There is deliberately no
 * pendulum plant, no second loop and no MIMO structure here -- that is EXP003
 * (Tutorial 3). Nothing in this module anticipates it.
 *
 * SAFETY. Like EXP001, the sequencer never enables an actuator itself. It
 * produces a desired plant input U; the board layer decides whether to act on it.
 * `armed` defaults to false, and a disarmed run executes the full sequence and
 * emits complete telemetry with zero commanded motion -- the intended dry run.
 *
 * HAL-free, so the whole sequence including its abort paths is host-testable.
 */

#ifndef ENR312_EXP002_H
#define ENR312_EXP002_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"
#include "enr312_pd.h"
#include "enr312_rotor.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    EXP002_PHASE_IDLE = 0,        /**< settle; R = D = N = 0                  */
    EXP002_PHASE_REF_STEP,        /**< step on R  -> measures T(s)            */
    EXP002_PHASE_REF_SETTLE,      /**< R back to 0, let the loop settle       */
    EXP002_PHASE_DIST_STEP,       /**< step on D  -> measures SD(s)           */
    EXP002_PHASE_DIST_SETTLE,
    EXP002_PHASE_DONE,
    EXP002_PHASE_ABORTED
} ENR312_Exp002Phase_t;

typedef enum {
    EXP002_ABORT_NONE = 0,
    EXP002_ABORT_ROTOR_LIMIT,     /**< rotor travel limit reached             */
    EXP002_ABORT_SATURATION,      /**< controller saturated for too long      */
    EXP002_ABORT_OPERATOR
} ENR312_Exp002Abort_t;

/** One telemetry record. Field order matches ENR312_Exp002_CsvHeader(). */
typedef struct {
    uint32_t tick;
    double   t_s;                 /**< nominal time = tick*Ts (NOT measured)  */
    uint8_t  phase;
    double   reference_deg;       /**< R [deg]                                */
    double   disturbance;         /**< D [plant-input units]                  */
    double   noise_deg;           /**< N [deg]                                */
    double   error_deg;           /**< e = R - (Y+N) [deg]                    */
    double   u;                   /**< U, plant input (after sat, incl. D)    */
    double   rotor_deg;           /**< Y, rotor angle [deg]                   */
    uint8_t  abort_reason;
} ENR312_Exp002Sample_t;

typedef struct {
    ENR312_PD_t          pd;
    ENR312_Rotor_t       rotor;

    ENR312_Exp002Phase_t phase;
    ENR312_Exp002Abort_t abort_reason;
    uint32_t             tick;
    uint32_t             phase_tick;
    uint32_t             sat_run;      /**< consecutive saturated ticks       */

    bool                 armed;
    double               ts_s;

    double               ref_step_deg;
    double               dist_step;

    ENR312_Exp002Sample_t last;
} ENR312_Exp002_t;

/* Phase durations. 6 s per excitation comfortably exceeds the 4 s settling
 * objective of Tutorial 2 section 3, so the full transient is captured. */
#define EXP002_IDLE_TICKS         (ENR312_CONTROL_RATE_HZ * 1u)
#define EXP002_STEP_TICKS         (ENR312_CONTROL_RATE_HZ * 6u)
#define EXP002_SETTLE_TICKS       (ENR312_CONTROL_RATE_HZ * 3u)

/** Default excitation amplitudes, chosen TOGETHER with the output limit.
 *
 *  EXP002 is a linear-response measurement, so the loop must not clip. With the
 *  Tutorial 1 gains the predicted peak demand for a reference step is
 *  amplitude * (Kp + Kd*alpha/Ts) = amplitude * 152.5
 *  (see ENR312_PD_PredictStepDemand). A 2 deg step therefore demands ~305, so the
 *  EXP002 output limit is set to 400 -- above the transient, still bounded.
 *
 *  2 deg is also large enough to be resolved: at 0.15 deg/count it is ~13 encoder
 *  counts, so quantisation contributes about 1 % of the step. A smaller step
 *  would be quieter on the actuator but noisier in the measurement. */
#define EXP002_DEFAULT_REF_STEP_DEG   2.0
#define EXP002_DEFAULT_DIST_STEP      1.0
#define EXP002_DEFAULT_U_LIMIT        400.0

/** Abort if the controller stays saturated this long (0.5 s). */
#define EXP002_SAT_ABORT_TICKS    (ENR312_CONTROL_RATE_HZ / 2u)

/**
 * @brief Initialise the sequencer.
 * @param kp,kd  controller gains under test
 * @param armed  false for a dry run (recommended first)
 */
void ENR312_Exp002_Init(ENR312_Exp002_t *x, double kp, double kd, bool armed);

/** @brief Override the excitation amplitudes before the run starts. */
void ENR312_Exp002_SetExcitation(ENR312_Exp002_t *x, double ref_step_deg,
                                 double dist_step);

/**
 * @brief Advance one control tick.
 * @param rotor_deg_measured  plant output Y [deg]
 * @param noise_deg           N to inject this tick [deg]; 0 when unused
 * @return this tick's telemetry record (never NULL)
 */
const ENR312_Exp002Sample_t *ENR312_Exp002_Tick(ENR312_Exp002_t *x,
                                                double rotor_deg_measured,
                                                double noise_deg);

/** Plant-input clamp; ignored unless 0 < limit <= 4 * EXP002_DEFAULT_U_LIMIT. */
void ENR312_Exp002_SetULimit(ENR312_Exp002_t *x, double limit);

void ENR312_Exp002_Abort(ENR312_Exp002_t *x);
bool ENR312_Exp002_IsFinished(const ENR312_Exp002_t *x);
const char *ENR312_Exp002_CsvHeader(void);
int ENR312_Exp002_FormatCsv(const ENR312_Exp002Sample_t *s, char *buf, int buflen);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_EXP002_H */

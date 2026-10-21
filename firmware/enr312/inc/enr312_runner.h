/**
 * @file    enr312_runner.h
 * @brief   Closed-loop experiment runner: one tick = measured angles in,
 *          commanded rotor velocity out. Hardware-independent.
 *
 * The runner is the bridge between the tutorial cores (EXP002/003/005, which
 * output u = rotor ANGULAR ACCELERATION in deg/s^2, because the rotor plant is
 * G_rotor = 1/s^2 in degrees) and the stepper, which is commanded by STEP RATE.
 * It integrates u into a velocity, clamps it, and returns it; the board layer
 * converts deg/s to microsteps/s. The same code runs on the STM32, in the
 * host tests and in the rig emulator.
 *
 * Experiments
 *   2  Tutorial 2  rotor only (pendulum REMOVED or CLAMPED): R step, then D step
 *   3  Tutorial 3  suspended MIMO: inner pendulum PD + outer rotor PD, R step
 *   4  Tutorial 4  identical acquisition to 3 (the analysis differs)
 *   5  Tutorial 5  INVERTED: capture gate, balance, R step, then HOLD balancing
 *                  until the operator stops (the pendulum is never dropped)
 *   6-10, 21-23  general core (enr312_ctrl.h): Tutorials 6-10 and the PEND experiments
 *   (Tutorial 1 is open-loop: first-motion moves and sensing, no runner.)
 *
 * Pendulum angle convention (docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md):
 *   psi = encoder angle, 0 = hanging datum (taken with 'z' while hanging still),
 *         positive in the Tutorial-3 sense (EXP001 P2b fixes the polarity).
 *   EXP003/004 use psi directly.
 *   EXP005 uses alpha = wrap180(180 - psi): the coupling changes sign between
 *         hanging and upright, so the upright angle is measured the other way.
 */
#ifndef ENR312_RUNNER_H
#define ENR312_RUNNER_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_exp002.h"
#include "enr312_exp003.h"
#include "enr312_exp005.h"
#include "enr312_ctrl.h"

#ifdef __cplusplus
extern "C" {
#endif

/** One configuration for every closed-loop experiment. Tutorials 2-5 use
 *  exp, kp, kd, kpp, kdp, step_deg, dist, u_limit, v_max; the general core
 *  (enr312_ctrl.h, experiments 6-10 and 21-23) uses the rest as well. */
typedef ENR312_CtrlConfig_t ENR312_RunnerConfig_t;

typedef enum {
    ENR312_RUN_IDLE = 0,
    ENR312_RUN_ACTIVE,      /**< core running                                  */
    ENR312_RUN_STOPPING,    /**< core finished or stop requested: decelerating */
    ENR312_RUN_FINISHED,    /**< velocity 0, sequence complete                 */
    ENR312_RUN_ABORTED      /**< velocity 0 immediately                        */
} ENR312_RunState_t;

typedef enum {
    ENR312_RUN_ABORT_NONE = 0,
    ENR312_RUN_ABORT_CORE,          /**< the tutorial core aborted (see core_abort) */
    ENR312_RUN_ABORT_VELOCITY,      /**< speed ceiling held > 200 ms                */
    ENR312_RUN_ABORT_OPERATOR,
    ENR312_RUN_ABORT_WATCHDOG       /**< host silent (set by the board layer)       */
} ENR312_RunAbort_t;

typedef struct {
    ENR312_RunnerConfig_t cfg;
    ENR312_Exp002_t e2;
    ENR312_Exp003_t e3;
    ENR312_Exp005_t e5;
    ENR312_Ctrl_t   ec;     /**< general core, experiments 6-10 and 21-23     */
    ENR312_RunState_t state;
    ENR312_RunAbort_t abort_reason;
    uint8_t  core_abort;    /**< core-specific abort code                    */
    uint8_t  phase;         /**< core phase (enum of that experiment)        */
    uint32_t tick;
    uint32_t vsat_run;
    double   v_deg_s;       /**< commanded rotor velocity                    */
    double   u;             /**< last plant input [deg/s^2]                  */
    double   ref_deg;       /**< last rotor reference                        */
    double   pend_deg;      /**< pendulum angle in the core's convention     */
} ENR312_Runner_t;

/** Tutorial defaults for an experiment (gains, step, limits). */
void ENR312_Runner_Defaults(ENR312_RunnerConfig_t *cfg, uint8_t exp);

/** Check a configuration. Returns NULL if valid, else a short reason. */
const char *ENR312_Runner_Validate(const ENR312_RunnerConfig_t *cfg);

/** Initialise and start. Returns false (and stays IDLE) if cfg is invalid. */
bool ENR312_Runner_Start(ENR312_Runner_t *r, const ENR312_RunnerConfig_t *cfg);

/**
 * One control tick (Ts = ENR312_CONTROL_PERIOD_S).
 * @param rotor_deg  measured rotor angle (from the step count)
 * @param psi_deg    encoder pendulum angle, 0 = hanging datum
 * @return commanded rotor velocity [deg/s]; 0 when not running
 */
double ENR312_Runner_Tick(ENR312_Runner_t *r, double rotor_deg, double psi_deg);

/** Graceful stop: decelerate at u_limit to rest. */
void ENR312_Runner_Stop(ENR312_Runner_t *r);

/** Immediate abort: velocity 0 now. */
void ENR312_Runner_Abort(ENR312_Runner_t *r, ENR312_RunAbort_t why);

/** True while the runner commands motion (ACTIVE or STOPPING). */
bool ENR312_Runner_IsMoving(const ENR312_Runner_t *r);

/** Human-readable names for telemetry. */
const char *ENR312_Runner_PhaseName(const ENR312_Runner_t *r);
const char *ENR312_Runner_AbortName(const ENR312_Runner_t *r);

/** Live update of a running general-core experiment (gains, filters, rate). */
void ENR312_Runner_ApplyLive(ENR312_Runner_t *r, const ENR312_RunnerConfig_t *cfg);

/** Live rotor set-point for HOLD / REGULATE (general core only). False if not applicable. */
bool ENR312_Runner_SetRef(ENR312_Runner_t *r, double ref_deg);

/** True if the +/-120 deg suspended-mode pendulum bound applies to this run. */
bool ENR312_Runner_SuspendedLimit(const ENR312_Runner_t *r);

/** True for experiments that balance upright and start with an operator capture. */
bool ENR312_Runner_NeedsCapture(uint8_t exp);

/** Map the encoder angle to the EXP005 upright angle alpha = wrap180(180 - psi). */
double ENR312_Runner_UprightAngle(double psi_deg);

#ifdef __cplusplus
}
#endif

#endif /* ENR312_RUNNER_H */

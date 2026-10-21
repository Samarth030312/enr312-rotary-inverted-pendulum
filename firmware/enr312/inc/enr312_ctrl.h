/**
 * @file    enr312_ctrl.h
 * @brief   General controller core for Tutorials 6-10 and the PEND experiments.
 *          Hardware-independent: angles in, plant input u [deg/s^2] out.
 *
 * Tutorials 2-5 keep their own, rig-validated cores (enr312_exp00N.c). This
 * core adds what the later tutorials and the PEND lab questions need:
 *
 *   exp  source          mode       law           sequence
 *    6   Tutorial 6      inverted   dual PID + I   capture, release, step, step back, hold
 *    7   Tutorial 7      inverted   dual PID       capture, release, 8 pendulum impulses, hold
 *    8   Tutorial 8      inverted   dual PID + I   capture, release, step, back, load disturbance, hold
 *    9   Tutorial 9      suspended  state feedback rotor step and back (pendulum gains 0)
 *   10   Tutorial 10     suspended  state feedback (LQR gains, optional virtual damping b)
 *   21   PEND S3-5       suspended  dual PID       regulate: stop a swing (pluck, then go)
 *   22   PEND Q7, Q14    suspended  on-off         rotor step and back with bang-bang control
 *   23   PEND C10        inverted   state feedback capture, release, step, back, hold (4-state LQR)
 *
 * Energy swing-up (PEND C12) is NOT run on the rig. A first attempt here never
 * brought the emulated pendulum closer than ~49 deg to upright (cause not
 * established); the idealised simulation in
 * matlab/experiments/PEND/pend_swingup_study.m shows the actuator limits are
 * not the reason. A rig swing-up is future work.
 *
 * Conventions (docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md):
 *   theta  rotor angle [deg], from the microsteps issued
 *   psi    encoder angle [deg], 0 = hanging datum
 *   alpha  = wrap180(180 - psi), the upright angle used in inverted mode
 *   u      rotor angular acceleration [deg/s^2]
 * Inverted dual PID: u = -u_rotor + u_pend   (the Tutorial 5 outer-loop sign)
 * Suspended dual PID: u = +u_rotor + u_pend
 * State feedback:     u = -(k1 (theta - r) + k2 thetadot + k3 a + k4 adot) - b thetadot
 *   a = alpha (inverted) or psi (suspended); thetadot is the commanded rotor
 *   velocity (exact for a stepper that does not miss steps); adot is a
 *   filtered difference of a. b emulates the Tutorial 9/10 rotor plant
 *   1/(s^2 + b s) ("rotor plant design").
 *
 * Every line of this file is mirrored in matlab/+odyssix/+sim/runCtrl.m and
 * the two are compared by matlab/tests/test_sim_matches_firmware.m.
 */
#ifndef ENR312_CTRL_H
#define ENR312_CTRL_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CTRL_MA_MAX            32u    /**< longest moving average on the pendulum   */
#define CTRL_DIV_MAX           50u    /**< slowest loop: 500/50 = 10 Hz             */
#define CTRL_PEND_ABORT_DEG    15.0   /**< inverted: |alpha| beyond this = lost     */
#define CTRL_PEND_WARN_DEG     10.0
#define CTRL_PEND_WARN_TICKS   (ENR312_CONTROL_RATE_HZ / 10u)   /* 100 ms */
#define CTRL_CAPTURE_DEG       2.0
#define CTRL_CAPTURE_TICKS     (ENR312_CONTROL_RATE_HZ * 1u)    /* 1 s    */
#define CTRL_RELEASE_DEG       1.5    /**< same release detection as EXP005 2.0.8   */
#define CTRL_SAT_ABORT_TICKS   (ENR312_CONTROL_RATE_HZ / 5u)    /* 200 ms */

typedef enum {
    CTRL_PH_WAIT_CAPTURE = 0,
    CTRL_PH_WAIT_RELEASE = 1,
    CTRL_PH_BALANCE      = 2,
    CTRL_PH_STEP         = 3,
    CTRL_PH_STEP_BACK    = 4,
    CTRL_PH_DIST         = 5,
    CTRL_PH_DIST_OFF     = 6,
    CTRL_PH_IMPULSES     = 7,
    CTRL_PH_HOLD         = 8,
    CTRL_PH_IDLE         = 9,
    CTRL_PH_REGULATE     = 10,
    CTRL_PH_UNUSED_11    = 11,   /* reserved (swing-up, not run on the rig) */
    CTRL_PH_DONE         = 12,
    CTRL_PH_ABORTED      = 13
} ENR312_CtrlPhase_t;

typedef enum {
    CTRL_ABORT_NONE = 0,
    CTRL_ABORT_PENDULUM_LOST,
    CTRL_ABORT_ROTOR_LIMIT,
    CTRL_ABORT_SATURATION,
    CTRL_ABORT_OPERATOR
} ENR312_CtrlAbort_t;

/** Everything the host can set ('$' commands). Units in brackets. */
typedef struct {
    uint8_t exp;
    double kp, ki, kd;        /**< rotor PID [deg/s^2 per deg, per deg s, per deg/s]  */
    double kpp, kdp;          /**< pendulum PD                                       */
    double fdr, fdp;          /**< derivative low-pass corner, rotor / pendulum [Hz] */
    double k1, k2, k3, k4;    /**< state feedback gains                              */
    double bv;                /**< virtual rotor damping b [1/s] (T9/T10)            */
    double step_deg;          /**< rotor reference step [deg]                        */
    double dist;              /**< load disturbance at the plant input [deg/s^2]     */
    double imp_deg;           /**< pendulum-reference impulse [deg] for 4 ms (T7)    */
    double uon, db;           /**< on-off level [deg/s^2] and dead band [deg]        */
    double u_limit;           /**< plant-input clamp [deg/s^2]                       */
    double v_max;             /**< rotor speed ceiling [deg/s] (runner)              */
    double ref_rate;          /**< live set-point slew [deg/s], 0 = step             */
    uint8_t div;              /**< controller runs every div ticks (500/div Hz)      */
    uint8_t ma;               /**< moving average length on the pendulum, 1 = off   */
} ENR312_CtrlConfig_t;

typedef struct {
    ENR312_CtrlConfig_t c;
    ENR312_CtrlPhase_t  phase;
    ENR312_CtrlAbort_t  abort_reason;
    uint32_t tick, phase_tick, n_imp;
    uint32_t capture_run, warn_run, sat_run;
    double   a_capture;       /**< pendulum angle at capture (release detection)   */
    double   ref_live;        /**< target of the live set-point ($ref=)            */
    double   ref_now;         /**< slewed set-point                                */
    /* rotor PID */
    double   ir, er_prev, dr;  bool r_have;
    /* pendulum PD on its error */
    double   ep_prev, dp;      bool p_have;
    /* filtered derivative of the encoder angle (state feedback) */
    double   psi_prev, dpsi;   bool psi_have;
    /* moving average */
    double   ma_buf[CTRL_MA_MAX]; uint8_t ma_n, ma_i; double ma_sum;
    /* decimation */
    uint8_t  div_count;
    double   u_hold;
    /* outputs (last tick) */
    double   u, u_rotor, u_pend, ref, pend_ref, a_meas;
} ENR312_Ctrl_t;

/** Defaults for an experiment (Tutorial values). Returns false for unknown exp. */
bool ENR312_Ctrl_Defaults(ENR312_CtrlConfig_t *c, uint8_t exp);
/** NULL if valid, else a short reason. */
const char *ENR312_Ctrl_Validate(const ENR312_CtrlConfig_t *c);
/** True for the experiments this core runs. */
bool ENR312_Ctrl_Handles(uint8_t exp);
/** True if the experiment balances upright (alpha used, 120 deg board limit off). */
bool ENR312_Ctrl_Inverted(uint8_t exp);

void ENR312_Ctrl_Init(ENR312_Ctrl_t *x, const ENR312_CtrlConfig_t *c);
/** Live change of gains, rate, filters (not exp, sequence or step). */
void ENR312_Ctrl_SetGains(ENR312_Ctrl_t *x, const ENR312_CtrlConfig_t *c);
/** Live set-point [deg], used in HOLD and REGULATE; slews at ref_rate. */
void ENR312_Ctrl_SetRef(ENR312_Ctrl_t *x, double ref_deg);

/**
 * One 2 ms tick.
 * @param theta      rotor angle [deg]
 * @param thetadot   commanded rotor velocity [deg/s] (runner state)
 * @param psi        encoder angle [deg], 0 = hanging
 * @return plant input u [deg/s^2] (0 when not controlling)
 */
double ENR312_Ctrl_Tick(ENR312_Ctrl_t *x, double theta, double thetadot, double psi);

bool ENR312_Ctrl_IsFinished(const ENR312_Ctrl_t *x);
const char *ENR312_Ctrl_PhaseName(uint8_t phase);
const char *ENR312_Ctrl_AbortName(uint8_t reason);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_CTRL_H */

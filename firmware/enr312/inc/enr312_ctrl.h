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
 *   24   PEND C12        hanging: energy control. amp >= 179: swing up, the 4-state LQR
 *                        catches it; 0 < amp < 179: swing to +/-amp and keep it there;
 *                        amp 0: stop the swing. (A pendulum can rest only at 0 and 180:
 *                        holding it still at psi needs arm acceleration (wg2/wr2) tan psi.)
 *
 * seq = 0 ("lab" mode): no tutorial sequence. Hanging experiments regulate at
 * once; upright ones go from release straight to HOLD. Steps, holds and angles
 * then come from the live set-point ($ref) only.
 *
 * Swing-up (exp 24), from the energy of the pendulum, psi from hanging:
 *   E = psidot^2/(2 wg2) + 1 - cos(psi)        0 hanging still, 2 upright still
 *   dE/dt = (psidot/wg2)(wr2 cos(psi) u - gamma psidot)
 *   u = uon sat(SW_KE (2 + delta - E)) sign(psidot cos psi) - (kp theta + kd thetadot)
 * (pendulum target amp < 179: u = uon sat(SW_KE (h* + delta - E) psidot cos(psi)/wg)
 *  with h* = 1 - cos(amp), the Astrom-Furuta energy law; amp 0 stops the swing)
 * pumps energy in (brakes above the target) while a PD keeps the arm near the
 * centre. delta is the energy the pivot friction drains on the climb, learnt
 * swing by swing, only from swings where the pump had already reached its
 * target: at an apex short of upright delta += SW_KA (2 - (1 - cos psi_apex));
 * on a pass over the top faster than SW_CATCH_RATE delta -= SW_KA (E - 2).
 * The pendulum then arrives at the top nearly at rest. At |alpha| <= SW_CATCH_DEG, |alpha
 * rate| <= SW_CATCH_RATE, E >= SW_E_MIN the state feedback k1..k4 (exp 23
 * LQR) takes over and walks the arm back to 0 at rrate while it balances.
 * wg2 [1/s^2] is the pendulum constant (default Tutorial 5; set it from the
 * free-swing measurement). Simulation: matlab/experiments/PEND/pend_swingup_study.m.
 *
 * Upright auto-trim (HOLD, all upright experiments): the encoder's "upright"
 * (hanging datum + 180) is off the true balance point by a fraction of a degree
 * (rig 2026-10-21: +0.3..+0.7 deg), and the state feedback then holds the arm
 * off by k3/k1 times that (23 deg). In HOLD the mean alpha is learnt with a
 * CTRL_TRIM_TAU_S low-pass and subtracted, so the arm returns to its set-point.
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
#define CTRL_SW_CATCH_DEG      7.0   /**< swing-up hands over inside this     */
#define CTRL_SW_CATCH_RATE     60.0   /**< ... moving slower than this [deg/s] (rig 2026-10-21: 75 deg/s fell) */
#define CTRL_SW_OVER_RATE      CTRL_SW_CATCH_RATE  /**< a pass too fast to catch = too much energy */
#define CTRL_SW_HOME_TICKS     (ENR312_CONTROL_RATE_HZ * 2u)    /* hold where caught 2 s, then home */
#define CTRL_TRIM_TAU_S        8.0    /**< upright auto-trim time constant [s]  */
#define CTRL_SAT_ABORT_UP_TICKS (ENR312_CONTROL_RATE_HZ / 2u)   /* 500 ms, upright HOLD */
#define CTRL_SW_E_MIN          1.8    /**< ... and with at least this energy   */
#define CTRL_SW_KE             10.0   /**< pump gain on (2 + delta - E)        */
#define CTRL_SW_DELTA0         0.15   /**< first guess of the climb loss       */
#define CTRL_SW_KE_AMP         5.0    /**< energy-law gain for a pendulum target (sweep: 5 reaches in 3-6 s, arm <= 34 deg) */
#define CTRL_SW_DELTA_MAX      0.6
#define CTRL_SW_KA             0.5    /**< learning gain on the apex shortfall */
#define CTRL_SW_TIMEOUT_TICKS  (ENR312_CONTROL_RATE_HZ * 40u)   /* 40 s   */

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
    CTRL_PH_SWINGUP      = 11,
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
    uint8_t seq;              /**< 1 = tutorial sequence, 0 = lab: regulate/hold     */
    double wg2;               /**< pendulum constant g/L_eq [1/s^2] (swing-up)       */
    double amp;               /**< exp 24 pendulum target [deg]: 0 stop the swing,
                                   0..179 swing to +/-amp, >= 179 swing up and balance */
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
    double   sw_energy;       /**< swing-up: normalised energy E (0 hanging, 2 up)  */
    double   sw_delta;        /**< swing-up: learnt energy lost per climb           */
    double   sw_dpsi_prev;    /**< swing-up: previous rate, for apex detection      */
    double   sw_epeak;        /**< swing-up: highest E since the last apex          */
    bool     sw_over;         /**< swing-up: this pass over the top already counted */
    double   sw_amp_prev;     /**< swing-up: amp of the last tick (a change resets delta) */
    bool     home_pending;    /**< swing-up: walk the arm home 2 s after the catch   */
    double   trim;            /**< upright auto-trim: learnt encoder offset of upright [deg] */
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

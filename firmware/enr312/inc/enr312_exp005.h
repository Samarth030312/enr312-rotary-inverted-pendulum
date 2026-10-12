/**
 * @file    enr312_exp005.h
 * @brief   EXP005 (Tutorial 5) dual-PID control in the INVERTED (unstable) mode.
 *
 * ============================================================================
 * THIS IS THE FIRST EXPERIMENT IN WHICH LOSS OF CONTROL PRODUCES VIOLENT MOTION.
 * ============================================================================
 * The open-loop inverted pendulum has a right-half-plane pole at +7.2888 rad/s
 * -- it falls with a 137 ms time constant. There is no benign failure mode: if
 * the loop opens, the pendulum falls and the arm slams. Every safety bound here
 * is tighter than EXP003's, and deliberately so.
 *
 * WHAT DIFFERS FROM EXP003 (Tutorial 5 section 8)
 * ------------------------------------------------
 * 1. PLANT SIGN. G_pend = wr^2 s^2 / (s^2 + (wg/Q)s - wg^2). The MINUS makes it
 *    unstable. Parameters also differ: wg^2 = 55.85 (not 57.01), Q = 20 (not 27).
 *
 * 2. INNER GAINS. K_pend = 300 + 30 s, thirty times the suspended-mode gain,
 *    because it must now STABILISE an unstable plant rather than damp a stable
 *    one. SUPPLIED and FIXED by Tutorial 5 -- not a design variable.
 *
 * 3. OUTER-LOOP SIGN INVERSION. In inverted mode T_rotor has NEGATIVE DC gain
 *    (its numerator is den_pend, constant term -wg^2), so closing the outer loop
 *    with a positive K_rotor is POSITIVE feedback. The rotor branch is therefore
 *    negated.
 *
 *    Established by evidence: with the non-inverted sign BOTH of Tutorial 5's
 *    own published designs are unstable (closed-loop poles at +2.46 and +1.89);
 *    with the inversion both are stable, and "Stable System 1" is far more
 *    stable than "Quasi-Stable System 2", reproducing the Tutorial's naming.
 *    Corroborated by the UCLA reference firmware, whose suspended demonstration
 *    mode uses NEGATIVE gains while its inverted modes use positive ones.
 *
 * THE FUNDAMENTAL LIMITATION
 * --------------------------
 * Stabilising the unstable pole does not remove it: T_rotor's numerator is
 * den_pend, so the RHP POLE becomes a NON-MINIMUM-PHASE ZERO at +7.2888 rad/s.
 * That caps achievable bandwidth near z/2 = 3.64 rad/s no matter what K_rotor
 * does, and it is why Tutorial 5's targets are far looser than Tutorial 3's.
 * Expect a pronounced INITIAL DIP in the step response -- the signature of a RHP
 * zero, and physically the arm moving the "wrong way" first to get under the
 * pendulum.
 *
 * SCOPE. Tutorial 5 requires PD control, gain/phase margins and sensitivity.
 * It does NOT require state feedback, LQR, Kalman filtering, integral action or
 * observers, and none appears here.
 *
 * HAL-free, host-testable.
 */

#ifndef ENR312_EXP005_H
#define ENR312_EXP005_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"
#include "enr312_pd.h"
#include "enr312_metrics.h"

#ifdef __cplusplus
extern "C" {
#endif

/* --- Tutorial 5 supplied inner controller (FIXED, inverted mode) ----------
 *
 * DOCUMENTED CONFLICT IN THE SOURCE, resolved by evidence.
 *
 * Tutorial 5 section 8 states:
 *     "Kp = 300.0, Ki = 0.0, Td = 0.5 sec, Kd = Kp*Td = 30.0"
 * but 300 * 0.5 = 150, not 30. The stated Td and the stated Kd cannot both be
 * right.
 *
 * Kd = 30 is the operative value, on two independent pieces of evidence:
 *   1. Tutorial 5's own serial-interface transcript enters
 *      "Pendulum PID Differential Gain: 30.00" in every example.
 *   2. The UCLA reference firmware uses PRIMARY_PROPORTIONAL_MODE_1 = 300 with
 *      PRIMARY_DERIVATIVE_MODE_1 = 30 for inverted mode.
 *
 * Kd is therefore defined DIRECTLY as 30.0, and the implied Td is 0.1 s, not
 * the 0.5 s the text states. Recorded rather than silently corrected.
 */
#define EXP005_KP_PEND        300.0
#define EXP005_KD_PEND        30.0
#define EXP005_TD_PEND        (EXP005_KD_PEND / EXP005_KP_PEND)   /* 0.1 s */

/** Outer-loop sign inversion. See the header comment -- evidence-based. */
#define EXP005_ROTOR_SIGN     (-1.0)

/* --- Tutorial 5 section 13 introduction-step designs ---------------------- */
#define EXP005_SYS1_KP        9.0
#define EXP005_SYS1_KD        9.0
#define EXP005_SYS2_KP        10.0
#define EXP005_SYS2_KD        3.33

/* ==========================================================================
 * SAFETY -- materially tighter than EXP003
 * ==========================================================================
 * The pendulum must stay NEAR UPRIGHT. Once it departs far enough, the linear
 * model no longer applies, the controller cannot recover it, and continuing to
 * drive the actuator makes the impact worse rather than better.
 *
 * 15 deg is chosen, not inherited: sin(15 deg) = 0.259 differs from 15 deg in
 * radians by 1.2 %, so the small-angle linearisation the whole design rests on
 * is still good there. Beyond it the model is no longer the system being
 * controlled.
 */
#define EXP005_PENDULUM_ABORT_DEG   15.0

/** Consecutive ticks the pendulum may exceed a soft warning band before abort. */
#define EXP005_PEND_WARN_DEG        10.0
#define EXP005_PEND_WARN_TICKS      (ENR312_CONTROL_RATE_HZ / 10u)   /* 100 ms */

/** The operator must hold the pendulum upright and steady before arming. */
#define EXP005_CAPTURE_DEG          2.0
#define EXP005_CAPTURE_TICKS        (ENR312_CONTROL_RATE_HZ * 1u)    /* 1 s    */

/** Release detection after capture, deg.  [MEASURED NEED 2026-10-12]
 *  After capture the motor stays still (u = 0) until the pendulum has moved this
 *  far from where it was held: a released inverted pendulum falls away from
 *  upright (time constant 1/wg ~ 0.13 s), a held one cannot. Control running
 *  while the hand still holds it moved the arm 30-150 deg in the emulator and
 *  lost it twice on the rig. 1.5 deg is reached ~0.3 s after release, far
 *  inside the recoverable range (~20 deg at u_limit 1500 deg/s^2). 1.5 deg
 *  (~8 mm at the tip) rides out hand tremor; emulator catch: max |rotor| 10, 13,
 *  18, 25 deg for 1, 1.5, 2, 3 deg. A fade-in of
 *  the outer loop was tried instead and rejected: it only delays the runaway
 *  of a held pendulum and lets the arm drift ~24 deg after a free catch. */
#define EXP005_RELEASE_DEG          1.5

#define EXP005_DEFAULT_ROTOR_STEP_DEG   2.0
#define EXP005_DEFAULT_U_LIMIT          1500.0
#define EXP005_STEP_TICKS   (ENR312_CONTROL_RATE_HZ * 10u)
#define EXP005_SETTLE_TICKS (ENR312_CONTROL_RATE_HZ * 3u)
#define EXP005_SAT_ABORT_TICKS (ENR312_CONTROL_RATE_HZ / 5u)  /* 200 ms */

typedef enum {
    EXP005_PHASE_WAIT_CAPTURE = 0, /**< operator holding pendulum upright      */
    EXP005_PHASE_BALANCE,          /**< balancing, no excitation               */
    EXP005_PHASE_ROTOR_STEP,       /**< rotor reference step                   */
    EXP005_PHASE_SETTLE,
    EXP005_PHASE_DONE,
    EXP005_PHASE_ABORTED
} ENR312_Exp005Phase_t;

typedef enum {
    EXP005_ABORT_NONE = 0,
    EXP005_ABORT_PENDULUM_LOST,    /**< departed the linear region -- the big one */
    EXP005_ABORT_ROTOR_LIMIT,
    EXP005_ABORT_SATURATION,
    EXP005_ABORT_OPERATOR
} ENR312_Exp005Abort_t;

typedef struct {
    uint32_t tick;
    double   t_s;
    uint8_t  phase;
    double   rotor_ref_deg;
    double   rotor_deg;
    double   pend_deg;
    double   u_rotor;
    double   u_pend;
    double   u;
    uint8_t  abort_reason;
} ENR312_Exp005Sample_t;

typedef struct {
    ENR312_PD_t          pd_rotor;
    ENR312_PD_t          pd_pend;
    ENR312_StepMetrics_t rotor_metrics;

    ENR312_Exp005Phase_t phase;
    ENR312_Exp005Abort_t abort_reason;
    uint32_t             tick;
    uint32_t             phase_tick;
    uint32_t             sat_run;
    uint32_t             warn_run;
    uint32_t             capture_run;
    bool                 released;         /**< hand let go after capture      */
    double               alpha_capture;    /**< pendulum angle at capture, deg */

    bool                 armed;
    double               ts_s;
    double               rotor_step_deg;
    double               u_limit;          /**< plant-input clamp              */
    bool                 hold_after_done;  /**< keep balancing in DONE         */

    ENR312_Exp005Sample_t last;
} ENR312_Exp005_t;

/**
 * @brief Initialise EXP005.
 *
 * The inner controller is always Tutorial 5's supplied 300/0/30 and is not a
 * parameter. `armed = false` runs the full sequence commanding nothing.
 */
void ENR312_Exp005_Init(ENR312_Exp005_t *x, double kp_rotor, double kd_rotor,
                        bool armed);

void ENR312_Exp005_SetRotorStep(ENR312_Exp005_t *x, double step_deg);

/** Replace the Tutorial-supplied inner (pendulum) gains, for exploration. */
void ENR312_Exp005_SetPendGains(ENR312_Exp005_t *x, double kp, double kd);

/** Plant-input clamp; ignored unless 0 < limit <= EXP005_DEFAULT_U_LIMIT. */
void ENR312_Exp005_SetULimit(ENR312_Exp005_t *x, double limit);

/** On hardware the pendulum must not be dropped when the sequence ends:
 *  with hold set, DONE keeps balancing (and keeps every abort check live)
 *  until the operator aborts. Default false preserves the original contract. */
void ENR312_Exp005_SetHoldAfterDone(ENR312_Exp005_t *x, bool hold);

/**
 * @brief Advance one control tick.
 *
 * Will not leave WAIT_CAPTURE until the pendulum has been held within
 * +/-EXP005_CAPTURE_DEG of upright for EXP005_CAPTURE_TICKS. Balancing an
 * inverted pendulum that is not yet upright just throws the arm at a limit.
 */
const ENR312_Exp005Sample_t *ENR312_Exp005_Tick(ENR312_Exp005_t *x,
                                                double rotor_deg,
                                                double pend_deg);

void ENR312_Exp005_Abort(ENR312_Exp005_t *x);
bool ENR312_Exp005_IsFinished(const ENR312_Exp005_t *x);
const char *ENR312_Exp005_CsvHeader(void);
int ENR312_Exp005_FormatCsv(const ENR312_Exp005Sample_t *s, char *buf, int buflen);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_EXP005_H */

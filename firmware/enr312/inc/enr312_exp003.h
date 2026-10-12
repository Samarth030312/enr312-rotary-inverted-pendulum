/**
 * @file    enr312_exp003.h
 * @brief   EXP003 (Tutorial 3) dual-PID MIMO control, suspended mode, with
 *          online control-effort measurement.
 *
 * STRUCTURE (Tutorial 3 sections 3-4, Figures 4-6)
 * ------------------------------------------------
 * Two coupled loops. The INNER loop controls pendulum angle; the OUTER loop
 * controls rotor angle. Tutorial 3 section 4 gives the inner-loop relation
 *
 *     phi_rotor = ( phi_rotor_control - phi_rotor * G_pend * K_pend ) * G_rotor
 *
 * so with a pendulum reference of theta_cmd the plant input is the SUM of the two
 * controller outputs:
 *
 *     u = K_rotor(phi_cmd - phi)  +  K_pend(theta_cmd - theta)
 *
 * This matches the UCLA reference's own description of its Dual PID mode
 * ("implemented as summation of Primary and Secondary PID controller
 * structures... summed and supplied to Rotor Control"), which is independent
 * corroboration of the reading.
 *
 * Both controllers are ordinary PD blocks, so this module REUSES ENR312_PD_t
 * twice rather than introducing a new abstraction. The only genuinely new thing
 * in EXP003 is the summation and the control-effort measurement.
 *
 * WHAT IS FIXED AND WHAT IS DESIGNED
 * ----------------------------------
 * Tutorial 3 SUPPLIES the pendulum controller and does not ask for it to be
 * designed:  Kp_pend = 10.0, Td_pend = 0.5 s, Kd_pend = 5.0.
 * The Tutorial's objective is to design K_rotor. Defaults Kp = 6, Td = 0.8.
 *
 * CONTROL EFFORT (Tutorial 3 section 5)
 * -------------------------------------
 *     CE_Max_Amplitude = max |u(t)|
 *     CE_Max_Power     = max u(t)^2
 *     CE_Total         = integral of |u| dt
 *
 * NOTE ON CE_Total. Tutorial 3 writes this as the SIGNED integral of u, but for
 * this loop the signed integral is exactly zero (CE has zero DC gain), while the
 * integral of |u| reproduces the Tutorial's own published value of 11.0 for
 * Design 1. The absolute value is taken. See experiments/EXP003/FIRST_PRINCIPLES.md
 * section 6 for the evidence.
 *
 * SCOPE. Suspended mode only. No inverted-mode operation, no state feedback, no
 * integral action -- those are later experiments and appear nowhere here.
 *
 * HAL-free, so the whole sequence including its abort paths is host-testable.
 */

#ifndef ENR312_EXP003_H
#define ENR312_EXP003_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"
#include "enr312_pd.h"
#include "enr312_rotor.h"
#include "enr312_metrics.h"

#ifdef __cplusplus
extern "C" {
#endif

/* --- Tutorial 3 supplied inner-loop controller (FIXED) -------------------- */
#define EXP003_KP_PEND        10.0
#define EXP003_TD_PEND        0.5
#define EXP003_KD_PEND        (EXP003_KP_PEND * EXP003_TD_PEND)   /* 5.0 */

/* --- Tutorial 3 Design 1 outer-loop defaults ----------------------------- */
#define EXP003_KP_ROTOR_D1    6.0
#define EXP003_TD_ROTOR_D1    0.8
#define EXP003_KD_ROTOR_D1    (EXP003_KP_ROTOR_D1 * EXP003_TD_ROTOR_D1) /* 4.8 */

/* --- Excitation ---------------------------------------------------------- */
#define EXP003_DEFAULT_ROTOR_STEP_DEG   2.0
/* Peak demand for a rotor step is dominated by the rotor derivative term,
 * A*(Kp_rotor + Kd_rotor*alpha/Ts). With Design 1 gains and a 10 Hz derivative
 * filter that is A*289.6; a 2 deg step gives ~579. The limit is set above it. */
#define EXP003_DEFAULT_U_LIMIT          800.0

typedef enum {
    EXP003_PHASE_IDLE = 0,
    EXP003_PHASE_ROTOR_STEP,     /**< rotor reference step -> tracking + CE   */
    EXP003_PHASE_SETTLE,
    EXP003_PHASE_DONE,
    EXP003_PHASE_ABORTED
} ENR312_Exp003Phase_t;

typedef enum {
    EXP003_ABORT_NONE = 0,
    EXP003_ABORT_ROTOR_LIMIT,
    EXP003_ABORT_PENDULUM_LIMIT,
    EXP003_ABORT_SATURATION,
    EXP003_ABORT_OPERATOR
} ENR312_Exp003Abort_t;

/** One telemetry record. Field order matches ENR312_Exp003_CsvHeader(). */
typedef struct {
    uint32_t tick;
    double   t_s;
    uint8_t  phase;
    double   rotor_ref_deg;      /**< phi_command                            */
    double   pend_ref_deg;       /**< theta_command (held 0 in Tutorial 3)   */
    double   rotor_deg;          /**< phi, measured                          */
    double   pend_deg;           /**< theta, measured                        */
    double   u_rotor;            /**< K_rotor output                         */
    double   u_pend;             /**< K_pend output                          */
    double   u;                  /**< plant input = sat(u_rotor + u_pend)    */
    uint8_t  abort_reason;
} ENR312_Exp003Sample_t;

/** Online control-effort accumulator (Tutorial 3 section 5). */
typedef struct {
    double   ce_max;             /**< max |u|                                */
    double   ce_max_power;       /**< max u^2                                */
    double   ce_total;           /**< integral |u| dt, trapezoidal           */
    double   prev_abs_u;
    bool     have_prev;
    uint32_t samples;
} ENR312_ControlEffort_t;

typedef struct {
    ENR312_PD_t            pd_rotor;   /**< outer loop, DESIGNED             */
    ENR312_PD_t            pd_pend;    /**< inner loop, SUPPLIED and FIXED   */
    ENR312_ControlEffort_t effort;

    /* EXP004 (Tutorial 4) addition: settling must be met on BOTH outputs, so the
     * pendulum channel is measured too. Different settling conventions -- see
     * enr312_metrics.h. */
    ENR312_StepMetrics_t   rotor_metrics;
    ENR312_StepMetrics_t   pend_metrics;

    ENR312_Exp003Phase_t   phase;
    ENR312_Exp003Abort_t   abort_reason;
    uint32_t               tick;
    uint32_t               phase_tick;
    uint32_t               sat_run;

    bool                   armed;
    double                 ts_s;
    double                 rotor_step_deg;
    double                 u_limit;      /**< plant-input clamp (default EXP003_DEFAULT_U_LIMIT) */

    ENR312_Exp003Sample_t  last;
} ENR312_Exp003_t;

#define EXP003_IDLE_TICKS     (ENR312_CONTROL_RATE_HZ * 1u)
#define EXP003_STEP_TICKS     (ENR312_CONTROL_RATE_HZ * 15u)  /* >> 10 s spec */
#define EXP003_SETTLE_TICKS   (ENR312_CONTROL_RATE_HZ * 3u)
#define EXP003_SAT_ABORT_TICKS (ENR312_CONTROL_RATE_HZ / 2u)

/** @brief Reset a control-effort accumulator. */
void ENR312_ControlEffort_Reset(ENR312_ControlEffort_t *e);

/**
 * @brief Accumulate one sample into the control-effort metrics.
 *
 * CE_Total uses the trapezoidal rule on |u|, which matters: |u| is spiky right
 * after a step, and a rectangular sum over-estimates it by several percent.
 */
void ENR312_ControlEffort_Update(ENR312_ControlEffort_t *e, double u, double ts_s);

/**
 * @brief Initialise EXP003.
 * @param kp_rotor,kd_rotor  outer-loop gains under test
 * @param armed              false for a dry run (recommended first)
 *
 * The inner pendulum controller is always initialised to Tutorial 3's supplied
 * values and is NOT a parameter -- Tutorial 3 fixes it deliberately so that the
 * rotor design can be compared across students.
 */
void ENR312_Exp003_Init(ENR312_Exp003_t *x, double kp_rotor, double kd_rotor,
                        bool armed);

void ENR312_Exp003_SetRotorStep(ENR312_Exp003_t *x, double step_deg);

/** Replace the Tutorial-supplied inner (pendulum) gains, for exploration.
 *  Call after Init and before the first Tick. Defaults remain Tutorial 3's. */
void ENR312_Exp003_SetPendGains(ENR312_Exp003_t *x, double kp, double kd);

/** Plant-input clamp; ignored unless 0 < limit <= EXP003_DEFAULT_U_LIMIT * 4. */
void ENR312_Exp003_SetULimit(ENR312_Exp003_t *x, double limit);

/**
 * @brief Advance one control tick.
 * @param rotor_deg  measured phi
 * @param pend_deg   measured theta
 */
const ENR312_Exp003Sample_t *ENR312_Exp003_Tick(ENR312_Exp003_t *x,
                                                double rotor_deg,
                                                double pend_deg);

void ENR312_Exp003_Abort(ENR312_Exp003_t *x);
bool ENR312_Exp003_IsFinished(const ENR312_Exp003_t *x);
const char *ENR312_Exp003_CsvHeader(void);
int ENR312_Exp003_FormatCsv(const ENR312_Exp003Sample_t *s, char *buf, int buflen);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_EXP003_H */

/**
 * @file    enr312_exp003.c
 * @brief   EXP003 dual-PID MIMO suspended-mode implementation. See header.
 */

#include "enr312_exp003.h"
#include <stdio.h>
#include <math.h>

void ENR312_ControlEffort_Reset(ENR312_ControlEffort_t *e)
{
    e->ce_max       = 0.0;
    e->ce_max_power = 0.0;
    e->ce_total     = 0.0;
    e->prev_abs_u   = 0.0;
    e->have_prev    = false;
    e->samples      = 0u;
}

void ENR312_ControlEffort_Update(ENR312_ControlEffort_t *e, double u, double ts_s)
{
    double a = fabs(u);
    if (a > e->ce_max) {
        e->ce_max       = a;
        e->ce_max_power = u * u;
    }
    /* Trapezoidal rule. |u| is spiky immediately after a step, and a rectangular
     * sum over-estimates the integral by several percent there. */
    if (e->have_prev) {
        e->ce_total += 0.5 * (a + e->prev_abs_u) * ts_s;
    }
    e->prev_abs_u = a;
    e->have_prev  = true;
    e->samples++;
}

void ENR312_Exp003_Init(ENR312_Exp003_t *x, double kp_rotor, double kd_rotor,
                        bool armed)
{
    ENR312_PD_Init(&x->pd_rotor, kp_rotor, kd_rotor, ENR312_CONTROL_PERIOD_S,
                   ENR312_PD_DEFAULT_DERIV_FC_HZ);
    /* Tutorial 3 SUPPLIES the inner controller and fixes it. Not a parameter. */
    ENR312_PD_Init(&x->pd_pend, EXP003_KP_PEND, EXP003_KD_PEND,
                   ENR312_CONTROL_PERIOD_S, ENR312_PD_DEFAULT_DERIV_FC_HZ);

    /* Saturation is applied ONCE, to the summed plant input, not per controller.
     * Clamping each branch separately would silently change the loop structure
     * Tutorial 3 defines. */
    ENR312_PD_SetOutputLimit(&x->pd_rotor, 1e30);
    ENR312_PD_SetOutputLimit(&x->pd_pend,  1e30);

    ENR312_ControlEffort_Reset(&x->effort);
    ENR312_StepMetrics_Init(&x->rotor_metrics, ENR312_SETTLE_TO_FINAL,
                            EXP003_DEFAULT_ROTOR_STEP_DEG, 0.02,
                            ENR312_CONTROL_PERIOD_S);
    ENR312_StepMetrics_Init(&x->pend_metrics, ENR312_SETTLE_TO_ZERO,
                            0.0, 0.02, ENR312_CONTROL_PERIOD_S);

    x->phase          = EXP003_PHASE_IDLE;
    x->abort_reason   = EXP003_ABORT_NONE;
    x->tick           = 0u;
    x->phase_tick     = 0u;
    x->sat_run        = 0u;
    x->armed          = armed;
    x->ts_s           = ENR312_CONTROL_PERIOD_S;
    x->rotor_step_deg = EXP003_DEFAULT_ROTOR_STEP_DEG;
    x->u_limit        = EXP003_DEFAULT_U_LIMIT;

    x->last.tick          = 0u;
    x->last.t_s           = 0.0;
    x->last.phase         = (uint8_t)x->phase;
    x->last.rotor_ref_deg = 0.0;
    x->last.pend_ref_deg  = 0.0;
    x->last.rotor_deg     = 0.0;
    x->last.pend_deg      = 0.0;
    x->last.u_rotor       = 0.0;
    x->last.u_pend        = 0.0;
    x->last.u             = 0.0;
    x->last.abort_reason  = (uint8_t)EXP003_ABORT_NONE;
}

void ENR312_Exp003_SetRotorStep(ENR312_Exp003_t *x, double step_deg)
{
    if (isfinite(step_deg)) {
        x->rotor_step_deg = step_deg;
        /* The rotor settling band is relative to the commanded final value, so
         * changing the step must re-target the metric or the band is wrong. */
        ENR312_StepMetrics_Init(&x->rotor_metrics, ENR312_SETTLE_TO_FINAL,
                                step_deg, 0.02, x->ts_s);
    }
}

void ENR312_Exp003_Abort(ENR312_Exp003_t *x)
{
    if (x->phase != EXP003_PHASE_ABORTED) {
        x->phase        = EXP003_PHASE_ABORTED;
        x->abort_reason = EXP003_ABORT_OPERATOR;
    }
}

bool ENR312_Exp003_IsFinished(const ENR312_Exp003_t *x)
{
    return (x->phase == EXP003_PHASE_DONE) || (x->phase == EXP003_PHASE_ABORTED);
}

static void exp003_advance(ENR312_Exp003_t *x, ENR312_Exp003Phase_t next)
{
    x->phase      = next;
    x->phase_tick = 0u;
}

const ENR312_Exp003Sample_t *ENR312_Exp003_Tick(ENR312_Exp003_t *x,
                                                double rotor_deg,
                                                double pend_deg)
{
    /* ---- 1. Excitation --------------------------------------------------- *
     * Tutorial 3 holds the pendulum reference at zero throughout and excites
     * only the rotor reference. That is what makes T_rotor separable. */
    double phi_ref   = (x->phase == EXP003_PHASE_ROTOR_STEP) ? x->rotor_step_deg : 0.0;
    double theta_ref = 0.0;

    /* ---- 2. The two controllers ------------------------------------------ */
    ENR312_PD_Signals_t sr = {0};
    sr.reference = phi_ref;
    sr.measured  = rotor_deg;
    ENR312_PD_Update(&x->pd_rotor, &sr);

    ENR312_PD_Signals_t sp = {0};
    sp.reference = theta_ref;
    sp.measured  = pend_deg;
    ENR312_PD_Update(&x->pd_pend, &sp);

    /* ---- 3. Summation, then a single saturation -------------------------- */
    double u_sum   = sr.u_unsat + sp.u_unsat;
    double u       = u_sum;
    bool   clipped = false;
    if (u >  x->u_limit) { u =  x->u_limit; clipped = true; }
    if (u < -x->u_limit) { u = -x->u_limit; clipped = true; }

    /* ---- 4. Safety, before the command is used --------------------------- *
     * Checked every tick and in every phase, including dry runs, so no abort
     * path first executes on hardware. Saturation aborts only when armed: while
     * disarmed the plant is open-loop and a standing error is expected. */
    if (!ENR312_Exp003_IsFinished(x)) {
        if (fabs(rotor_deg) > ENR312_ROTOR_LIMIT_DEG) {
            x->phase = EXP003_PHASE_ABORTED;
            x->abort_reason = EXP003_ABORT_ROTOR_LIMIT;
        } else if (fabs(pend_deg) > ENR312_PENDULUM_ABORT_DEG) {
            x->phase = EXP003_PHASE_ABORTED;
            x->abort_reason = EXP003_ABORT_PENDULUM_LIMIT;
        } else if (x->armed && clipped) {
            x->sat_run++;
            if (x->sat_run >= EXP003_SAT_ABORT_TICKS) {
                x->phase = EXP003_PHASE_ABORTED;
                x->abort_reason = EXP003_ABORT_SATURATION;
            }
        } else {
            x->sat_run = 0u;
        }
    }

    /* ---- 5. Control effort ------------------------------------------------ *
     * Accumulated only during the excitation phase. Including the idle phase
     * would add a stretch of near-zero u to CE_Total and make designs look
     * better or worse purely as a function of how long the operator waited. */
    if (x->phase == EXP003_PHASE_ROTOR_STEP) {
        double t_rel = (double)x->phase_tick * x->ts_s;
        ENR312_ControlEffort_Update(&x->effort, u, x->ts_s);
        ENR312_StepMetrics_Update(&x->rotor_metrics, rotor_deg, t_rel);
        ENR312_StepMetrics_Update(&x->pend_metrics, pend_deg, t_rel);
    }

    /* ---- 6. Sequence ------------------------------------------------------ */
    switch (x->phase) {
    case EXP003_PHASE_IDLE:
        if (x->phase_tick >= EXP003_IDLE_TICKS) {
            exp003_advance(x, EXP003_PHASE_ROTOR_STEP);
            ENR312_ControlEffort_Reset(&x->effort);
            ENR312_StepMetrics_Init(&x->rotor_metrics, ENR312_SETTLE_TO_FINAL,
                                    x->rotor_step_deg, 0.02, x->ts_s);
            ENR312_StepMetrics_Init(&x->pend_metrics, ENR312_SETTLE_TO_ZERO,
                                    0.0, 0.02, x->ts_s);
        }
        break;
    case EXP003_PHASE_ROTOR_STEP:
        if (x->phase_tick >= EXP003_STEP_TICKS) {
            exp003_advance(x, EXP003_PHASE_SETTLE);
        }
        break;
    case EXP003_PHASE_SETTLE:
        if (x->phase_tick >= EXP003_SETTLE_TICKS) {
            exp003_advance(x, EXP003_PHASE_DONE);
        }
        break;
    case EXP003_PHASE_DONE:
    case EXP003_PHASE_ABORTED:
    default:
        break;
    }

    /* ---- 7. Telemetry ----------------------------------------------------- */
    x->last.tick          = x->tick;
    x->last.t_s           = (double)x->tick * x->ts_s;
    x->last.phase         = (uint8_t)x->phase;
    x->last.rotor_ref_deg = phi_ref;
    x->last.pend_ref_deg  = theta_ref;
    x->last.rotor_deg     = rotor_deg;
    x->last.pend_deg      = pend_deg;
    x->last.u_rotor       = sr.u_unsat;
    x->last.u_pend        = sp.u_unsat;
    x->last.u             = ENR312_Exp003_IsFinished(x) ? 0.0 : u;
    x->last.abort_reason  = (uint8_t)x->abort_reason;

    x->tick++;
    x->phase_tick++;
    return &x->last;
}

const char *ENR312_Exp003_CsvHeader(void)
{
    return "tick,t_s,phase,rotor_ref_deg,pend_ref_deg,rotor_deg,pend_deg,"
           "u_rotor,u_pend,u,abort_reason";
}

int ENR312_Exp003_FormatCsv(const ENR312_Exp003Sample_t *s, char *buf, int buflen)
{
    return snprintf(buf, (size_t)buflen,
                    "%lu,%.6f,%u,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%u",
                    (unsigned long)s->tick, s->t_s, (unsigned)s->phase,
                    s->rotor_ref_deg, s->pend_ref_deg, s->rotor_deg, s->pend_deg,
                    s->u_rotor, s->u_pend, s->u, (unsigned)s->abort_reason);
}

void ENR312_Exp003_SetPendGains(ENR312_Exp003_t *x, double kp, double kd)
{
    ENR312_PD_Init(&x->pd_pend, kp, kd, ENR312_CONTROL_PERIOD_S,
                   ENR312_PD_DEFAULT_DERIV_FC_HZ);
    ENR312_PD_SetOutputLimit(&x->pd_pend, 1e30);
}

void ENR312_Exp003_SetULimit(ENR312_Exp003_t *x, double limit)
{
    if (limit > 0.0 && limit <= 4.0 * EXP003_DEFAULT_U_LIMIT) {
        x->u_limit = limit;
    }
}

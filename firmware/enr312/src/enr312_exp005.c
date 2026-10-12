/**
 * @file    enr312_exp005.c
 * @brief   EXP005 inverted-mode dual-PID implementation. See header.
 */

#include "enr312_exp005.h"
#include <stdio.h>
#include <math.h>

void ENR312_Exp005_Init(ENR312_Exp005_t *x, double kp_rotor, double kd_rotor,
                        bool armed)
{
    ENR312_PD_Init(&x->pd_rotor, kp_rotor, kd_rotor, ENR312_CONTROL_PERIOD_S,
                   ENR312_PD_DEFAULT_DERIV_FC_HZ);
    /* Tutorial 5 SUPPLIES the inverted-mode inner controller. Not a parameter. */
    ENR312_PD_Init(&x->pd_pend, EXP005_KP_PEND, EXP005_KD_PEND,
                   ENR312_CONTROL_PERIOD_S, ENR312_PD_DEFAULT_DERIV_FC_HZ);
    /* Saturation is applied once to the summed plant input, not per branch. */
    ENR312_PD_SetOutputLimit(&x->pd_rotor, 1e30);
    ENR312_PD_SetOutputLimit(&x->pd_pend,  1e30);

    ENR312_StepMetrics_Init(&x->rotor_metrics, ENR312_SETTLE_TO_FINAL,
                            EXP005_DEFAULT_ROTOR_STEP_DEG, 0.02,
                            ENR312_CONTROL_PERIOD_S);

    x->phase          = EXP005_PHASE_WAIT_CAPTURE;
    x->abort_reason   = EXP005_ABORT_NONE;
    x->tick           = 0u;
    x->phase_tick     = 0u;
    x->sat_run        = 0u;
    x->warn_run       = 0u;
    x->capture_run    = 0u;
    x->released       = false;
    x->alpha_capture  = 0.0;
    x->armed          = armed;
    x->ts_s           = ENR312_CONTROL_PERIOD_S;
    x->rotor_step_deg = EXP005_DEFAULT_ROTOR_STEP_DEG;
    x->u_limit         = EXP005_DEFAULT_U_LIMIT;
    x->hold_after_done = false;

    x->last.tick          = 0u;
    x->last.t_s           = 0.0;
    x->last.phase         = (uint8_t)x->phase;
    x->last.rotor_ref_deg = 0.0;
    x->last.rotor_deg     = 0.0;
    x->last.pend_deg      = 0.0;
    x->last.u_rotor       = 0.0;
    x->last.u_pend        = 0.0;
    x->last.u             = 0.0;
    x->last.abort_reason  = (uint8_t)EXP005_ABORT_NONE;
}

void ENR312_Exp005_SetRotorStep(ENR312_Exp005_t *x, double step_deg)
{
    if (isfinite(step_deg)) {
        x->rotor_step_deg = step_deg;
        ENR312_StepMetrics_Init(&x->rotor_metrics, ENR312_SETTLE_TO_FINAL,
                                step_deg, 0.02, x->ts_s);
    }
}

void ENR312_Exp005_Abort(ENR312_Exp005_t *x)
{
    if (x->phase != EXP005_PHASE_ABORTED) {
        x->phase        = EXP005_PHASE_ABORTED;
        x->abort_reason = EXP005_ABORT_OPERATOR;
    }
}

bool ENR312_Exp005_IsFinished(const ENR312_Exp005_t *x)
{
    return (x->phase == EXP005_PHASE_DONE) || (x->phase == EXP005_PHASE_ABORTED);
}

static void exp005_advance(ENR312_Exp005_t *x, ENR312_Exp005Phase_t next)
{
    x->phase      = next;
    x->phase_tick = 0u;
}

const ENR312_Exp005Sample_t *ENR312_Exp005_Tick(ENR312_Exp005_t *x,
                                                double rotor_deg,
                                                double pend_deg)
{
    bool holding = x->hold_after_done && (x->phase == EXP005_PHASE_DONE);
    /* Wait, motor still, until the operator's hand has let go: the pendulum
     * starts to fall away from where it was held (EXP005_RELEASE_DEG). */
    if (x->phase == EXP005_PHASE_BALANCE && !x->released &&
        fabs(pend_deg - x->alpha_capture) >= EXP005_RELEASE_DEG) {
        x->released   = true;
        x->phase_tick = 0u;            /* BALANCE's 2 s count from release */
    }
    bool controlling = ((x->phase == EXP005_PHASE_BALANCE && x->released) ||
                        x->phase == EXP005_PHASE_ROTOR_STEP ||
                        x->phase == EXP005_PHASE_SETTLE || holding);

    double phi_ref = (x->phase == EXP005_PHASE_ROTOR_STEP) ? x->rotor_step_deg : 0.0;

    /* ---- Controllers ----------------------------------------------------- */
    ENR312_PD_Signals_t sr = {0};
    sr.reference = phi_ref;
    sr.measured  = rotor_deg;
    ENR312_PD_Update(&x->pd_rotor, &sr);

    ENR312_PD_Signals_t sp = {0};
    sp.reference = 0.0;             /* upright */
    sp.measured  = pend_deg;
    ENR312_PD_Update(&x->pd_pend, &sp);

    /* Outer branch is NEGATED in inverted mode -- see the header. */
    double u_rotor = EXP005_ROTOR_SIGN * sr.u_unsat;
    double u_pend  = sp.u_unsat;
    double u_sum   = u_rotor + u_pend;

    double u = controlling ? u_sum : 0.0;
    bool clipped = false;
    if (u >  x->u_limit) { u =  x->u_limit; clipped = true; }
    if (u < -x->u_limit) { u = -x->u_limit; clipped = true; }

    /* ---- Safety, evaluated before the command is used -------------------- *
     * Ordered by severity. Losing the pendulum is the failure that matters:
     * beyond EXP005_PENDULUM_ABORT_DEG the small-angle linearisation the whole
     * design rests on no longer describes the system, so continuing to drive
     * the actuator cannot recover it and only makes the impact worse. */
    if (!ENR312_Exp005_IsFinished(x) || holding) {
        if (fabs(pend_deg) > EXP005_PENDULUM_ABORT_DEG) {
            x->phase        = EXP005_PHASE_ABORTED;
            x->abort_reason = EXP005_ABORT_PENDULUM_LOST;
        } else if (fabs(rotor_deg) > ENR312_ROTOR_LIMIT_DEG) {
            x->phase        = EXP005_PHASE_ABORTED;
            x->abort_reason = EXP005_ABORT_ROTOR_LIMIT;
        } else {
            /* Soft warning band: sustained large deviation predicts loss even
             * before the hard bound is reached. Catching it early converts a
             * fall into a controlled stop. */
            if (controlling && fabs(pend_deg) > EXP005_PEND_WARN_DEG) {
                x->warn_run++;
                if (x->warn_run >= EXP005_PEND_WARN_TICKS) {
                    x->phase        = EXP005_PHASE_ABORTED;
                    x->abort_reason = EXP005_ABORT_PENDULUM_LOST;
                }
            } else {
                x->warn_run = 0u;
            }

            if (x->armed && controlling && clipped) {
                x->sat_run++;
                if (x->sat_run >= EXP005_SAT_ABORT_TICKS) {
                    x->phase        = EXP005_PHASE_ABORTED;
                    x->abort_reason = EXP005_ABORT_SATURATION;
                }
            } else {
                x->sat_run = 0u;
            }
        }
    }

    /* ---- Metrics ---------------------------------------------------------- */
    if (x->phase == EXP005_PHASE_ROTOR_STEP) {
        ENR312_StepMetrics_Update(&x->rotor_metrics, rotor_deg,
                                  (double)x->phase_tick * x->ts_s);
    }

    /* ---- Sequence --------------------------------------------------------- */
    switch (x->phase) {
    case EXP005_PHASE_WAIT_CAPTURE:
        /* Do not start balancing until the operator has actually presented the
         * pendulum upright and steady. Closing the loop on a pendulum that is
         * already falling just throws the arm at a travel limit. */
        if (fabs(pend_deg) <= EXP005_CAPTURE_DEG) {
            x->capture_run++;
            if (x->capture_run >= EXP005_CAPTURE_TICKS) {
                x->alpha_capture = pend_deg;
                x->released      = false;
                exp005_advance(x, EXP005_PHASE_BALANCE);
            }
        } else {
            x->capture_run = 0u;
        }
        break;
    case EXP005_PHASE_BALANCE:
        if (x->released && x->phase_tick >= ENR312_CONTROL_RATE_HZ * 2u) {   /* 2 s settle */
            exp005_advance(x, EXP005_PHASE_ROTOR_STEP);
            ENR312_StepMetrics_Init(&x->rotor_metrics, ENR312_SETTLE_TO_FINAL,
                                    x->rotor_step_deg, 0.02, x->ts_s);
        }
        break;
    case EXP005_PHASE_ROTOR_STEP:
        if (x->phase_tick >= EXP005_STEP_TICKS) {
            exp005_advance(x, EXP005_PHASE_SETTLE);
        }
        break;
    case EXP005_PHASE_SETTLE:
        if (x->phase_tick >= EXP005_SETTLE_TICKS) {
            exp005_advance(x, EXP005_PHASE_DONE);
        }
        break;
    case EXP005_PHASE_DONE:
    case EXP005_PHASE_ABORTED:
    default:
        break;
    }

    /* ---- Telemetry -------------------------------------------------------- */
    x->last.tick          = x->tick;
    x->last.t_s           = (double)x->tick * x->ts_s;
    x->last.phase         = (uint8_t)x->phase;
    x->last.rotor_ref_deg = phi_ref;
    x->last.rotor_deg     = rotor_deg;
    x->last.pend_deg      = pend_deg;
    x->last.u_rotor       = u_rotor;
    x->last.u_pend        = u_pend;
    x->last.u             = (ENR312_Exp005_IsFinished(x) && !(holding && x->phase == EXP005_PHASE_DONE)) ? 0.0 : u;
    x->last.abort_reason  = (uint8_t)x->abort_reason;

    x->tick++;
    x->phase_tick++;
    return &x->last;
}

const char *ENR312_Exp005_CsvHeader(void)
{
    return "tick,t_s,phase,rotor_ref_deg,rotor_deg,pend_deg,"
           "u_rotor,u_pend,u,abort_reason";
}

int ENR312_Exp005_FormatCsv(const ENR312_Exp005Sample_t *s, char *buf, int buflen)
{
    return snprintf(buf, (size_t)buflen,
                    "%lu,%.6f,%u,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%u",
                    (unsigned long)s->tick, s->t_s, (unsigned)s->phase,
                    s->rotor_ref_deg, s->rotor_deg, s->pend_deg,
                    s->u_rotor, s->u_pend, s->u, (unsigned)s->abort_reason);
}

void ENR312_Exp005_SetPendGains(ENR312_Exp005_t *x, double kp, double kd)
{
    ENR312_PD_Init(&x->pd_pend, kp, kd, ENR312_CONTROL_PERIOD_S,
                   ENR312_PD_DEFAULT_DERIV_FC_HZ);
    ENR312_PD_SetOutputLimit(&x->pd_pend, 1e30);
}

void ENR312_Exp005_SetULimit(ENR312_Exp005_t *x, double limit)
{
    if (limit > 0.0 && limit <= EXP005_DEFAULT_U_LIMIT) {
        x->u_limit = limit;
    }
}

void ENR312_Exp005_SetHoldAfterDone(ENR312_Exp005_t *x, bool hold)
{
    x->hold_after_done = hold;
}

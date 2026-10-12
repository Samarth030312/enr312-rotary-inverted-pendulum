/**
 * @file    enr312_exp002.c
 * @brief   EXP002 sensitivity-function sequencer. See enr312_exp002.h.
 */

#include "enr312_exp002.h"
#include <stdio.h>
#include <math.h>

void ENR312_Exp002_Init(ENR312_Exp002_t *x, double kp, double kd, bool armed)
{
    ENR312_PD_Init(&x->pd, kp, kd, ENR312_CONTROL_PERIOD_S,
                   ENR312_PD_DEFAULT_DERIV_FC_HZ);
    /* Limit chosen against the predicted derivative transient, not guessed --
     * see EXP002_DEFAULT_REF_STEP_DEG. */
    ENR312_PD_SetOutputLimit(&x->pd, EXP002_DEFAULT_U_LIMIT);
    ENR312_Rotor_Init(&x->rotor, ENR312_ROTOR_POLARITY);

    x->phase        = EXP002_PHASE_IDLE;
    x->abort_reason = EXP002_ABORT_NONE;
    x->tick         = 0u;
    x->phase_tick   = 0u;
    x->sat_run      = 0u;
    x->armed        = armed;
    x->ts_s         = ENR312_CONTROL_PERIOD_S;
    x->ref_step_deg = EXP002_DEFAULT_REF_STEP_DEG;
    x->dist_step    = EXP002_DEFAULT_DIST_STEP;

    x->last.tick          = 0u;
    x->last.t_s           = 0.0;
    x->last.phase         = (uint8_t)x->phase;
    x->last.reference_deg = 0.0;
    x->last.disturbance   = 0.0;
    x->last.noise_deg     = 0.0;
    x->last.error_deg     = 0.0;
    x->last.u             = 0.0;
    x->last.rotor_deg     = 0.0;
    x->last.abort_reason  = (uint8_t)EXP002_ABORT_NONE;
}

void ENR312_Exp002_SetExcitation(ENR312_Exp002_t *x, double ref_step_deg,
                                 double dist_step)
{
    if (isfinite(ref_step_deg)) { x->ref_step_deg = ref_step_deg; }
    if (isfinite(dist_step))    { x->dist_step    = dist_step; }
}

void ENR312_Exp002_Abort(ENR312_Exp002_t *x)
{
    if (x->phase != EXP002_PHASE_ABORTED) {
        x->phase        = EXP002_PHASE_ABORTED;
        x->abort_reason = EXP002_ABORT_OPERATOR;
    }
}

bool ENR312_Exp002_IsFinished(const ENR312_Exp002_t *x)
{
    return (x->phase == EXP002_PHASE_DONE) || (x->phase == EXP002_PHASE_ABORTED);
}

static void exp002_advance(ENR312_Exp002_t *x, ENR312_Exp002Phase_t next)
{
    x->phase      = next;
    x->phase_tick = 0u;
}

const ENR312_Exp002Sample_t *ENR312_Exp002_Tick(ENR312_Exp002_t *x,
                                                double rotor_deg_measured,
                                                double noise_deg)
{
    /* ---- 1. Excitation for this phase ---------------------------------- *
     * Exactly one of R and D is non-zero at any time. Exciting both at once
     * would make T(s) and SD(s) inseparable from a single record, which is the
     * one mistake that quietly ruins a sensitivity measurement. */
    double R = 0.0, D = 0.0;
    switch (x->phase) {
    case EXP002_PHASE_REF_STEP:  R = x->ref_step_deg; break;
    case EXP002_PHASE_DIST_STEP: D = x->dist_step;    break;
    default: break;
    }

    /* ---- 2. Controller ------------------------------------------------- */
    ENR312_PD_Signals_t sig;
    sig.reference   = R;
    sig.disturbance = D;
    sig.noise       = noise_deg;
    sig.measured    = rotor_deg_measured;
    sig.error       = 0.0;
    sig.u_unsat     = 0.0;
    sig.u           = 0.0;

    ENR312_PD_Update(&x->pd, &sig);

    /* ---- 3. Safety ------------------------------------------------------ *
     * Evaluated every tick and in every phase, including dry runs and IDLE, so
     * that no abort path first executes on real hardware. */
    if (!ENR312_Exp002_IsFinished(x)) {
        /* Sustained saturation is a genuine fault ONLY when armed.
         *
         * While disarmed the plant is open-loop by construction -- nothing acts
         * on U -- so the error never decreases and the controller output stays
         * hard against its limit for the whole excitation. That is the expected
         * behaviour of a dry run, not a fault, and aborting on it would make the
         * dry run useless precisely when it is most needed.
         *
         * The clamp is detected by comparing u against u_unsat rather than by
         * re-testing the threshold: the derivative tail decays exponentially and
         * can sit a hair above the limit for thousands of ticks, so a bare `>`
         * comparison reports saturation long after the output has effectively
         * recovered. */
        if (x->armed && (sig.u != sig.u_unsat + sig.disturbance)) {
            x->sat_run++;
            if (x->sat_run >= EXP002_SAT_ABORT_TICKS) {
                x->phase        = EXP002_PHASE_ABORTED;
                x->abort_reason = EXP002_ABORT_SATURATION;
            }
        } else {
            x->sat_run = 0u;
        }

        if (fabs(rotor_deg_measured) > ENR312_ROTOR_LIMIT_DEG) {
            x->phase        = EXP002_PHASE_ABORTED;
            x->abort_reason = EXP002_ABORT_ROTOR_LIMIT;
        }
    }

    /* ---- 4. Sequence ---------------------------------------------------- */
    switch (x->phase) {
    case EXP002_PHASE_IDLE:
        if (x->phase_tick >= EXP002_IDLE_TICKS) {
            exp002_advance(x, EXP002_PHASE_REF_STEP);
        }
        break;
    case EXP002_PHASE_REF_STEP:
        if (x->phase_tick >= EXP002_STEP_TICKS) {
            exp002_advance(x, EXP002_PHASE_REF_SETTLE);
        }
        break;
    case EXP002_PHASE_REF_SETTLE:
        if (x->phase_tick >= EXP002_SETTLE_TICKS) {
            exp002_advance(x, EXP002_PHASE_DIST_STEP);
        }
        break;
    case EXP002_PHASE_DIST_STEP:
        if (x->phase_tick >= EXP002_STEP_TICKS) {
            exp002_advance(x, EXP002_PHASE_DIST_SETTLE);
        }
        break;
    case EXP002_PHASE_DIST_SETTLE:
        if (x->phase_tick >= EXP002_SETTLE_TICKS) {
            exp002_advance(x, EXP002_PHASE_DONE);
        }
        break;
    case EXP002_PHASE_DONE:
    case EXP002_PHASE_ABORTED:
    default:
        break;
    }

    /* ---- 5. Telemetry --------------------------------------------------- *
     * A disarmed run reports the plant input the controller WOULD have issued,
     * so a dry run is diagnostically useful, but the board layer must not act
     * on it. Arming is the board layer's gate, not this module's. */
    x->last.tick          = x->tick;
    x->last.t_s           = (double)x->tick * x->ts_s;
    x->last.phase         = (uint8_t)x->phase;
    x->last.reference_deg = R;
    x->last.disturbance   = D;
    x->last.noise_deg     = noise_deg;
    x->last.error_deg     = sig.error;
    x->last.u             = ENR312_Exp002_IsFinished(x) ? 0.0 : sig.u;
    x->last.rotor_deg     = rotor_deg_measured;
    x->last.abort_reason  = (uint8_t)x->abort_reason;

    x->tick++;
    x->phase_tick++;
    return &x->last;
}

const char *ENR312_Exp002_CsvHeader(void)
{
    return "tick,t_s,phase,reference_deg,disturbance,noise_deg,"
           "error_deg,u,rotor_deg,abort_reason";
}

int ENR312_Exp002_FormatCsv(const ENR312_Exp002Sample_t *s, char *buf, int buflen)
{
    return snprintf(buf, (size_t)buflen,
                    "%lu,%.6f,%u,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%u",
                    (unsigned long)s->tick, s->t_s, (unsigned)s->phase,
                    s->reference_deg, s->disturbance, s->noise_deg,
                    s->error_deg, s->u, s->rotor_deg,
                    (unsigned)s->abort_reason);
}

void ENR312_Exp002_SetULimit(ENR312_Exp002_t *x, double limit)
{
    if (limit > 0.0 && limit <= 4.0 * EXP002_DEFAULT_U_LIMIT) {
        ENR312_PD_SetOutputLimit(&x->pd, limit);
    }
}

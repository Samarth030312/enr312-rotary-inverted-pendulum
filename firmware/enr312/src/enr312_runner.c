/**
 * @file    enr312_runner.c
 * @brief   Closed-loop experiment runner. See enr312_runner.h.
 */
#include "enr312_runner.h"
#include <math.h>
#include <stddef.h>

#define RUN_TS              ENR312_CONTROL_PERIOD_S
#define RUN_VSAT_TICKS      (ENR312_CONTROL_RATE_HZ / 5u)      /* 200 ms */
#define RUN_DEFAULT_VMAX    360.0                              /* deg/s  */

void ENR312_Runner_Defaults(ENR312_RunnerConfig_t *cfg, uint8_t exp)
{
    /* the general core sets every field; for Tutorials 2-5 this leaves the
     * fields they do not use at neutral values, then the code below applies
     * their own defaults */
    if (ENR312_Ctrl_Defaults(cfg, exp)) { return; }
    cfg->exp      = exp;
    cfg->kpp      = 0.0;
    cfg->kdp      = 0.0;
    cfg->dist     = 0.0;
    cfg->v_max    = RUN_DEFAULT_VMAX;
    switch (exp) {
    case 2:                                     /* Tutorial 2 selected design */
        cfg->kp = 5.0;  cfg->kd = 2.5;
        cfg->step_deg = EXP002_DEFAULT_REF_STEP_DEG;
        cfg->dist     = EXP002_DEFAULT_DIST_STEP;
        cfg->u_limit  = EXP002_DEFAULT_U_LIMIT;
        break;
    case 3:                                     /* Tutorial 3 Design 1        */
    case 4:                                     /* Tutorial 4 reference       */
        cfg->kp = EXP003_KP_ROTOR_D1; cfg->kd = EXP003_KD_ROTOR_D1;
        cfg->kpp = EXP003_KP_PEND;    cfg->kdp = EXP003_KD_PEND;
        cfg->step_deg = EXP003_DEFAULT_ROTOR_STEP_DEG;
        cfg->u_limit  = EXP003_DEFAULT_U_LIMIT;
        break;
    case 5:                                     /* Tutorial 5 System 1        */
    default:
        cfg->exp = 5;
        cfg->kp = EXP005_SYS1_KP; cfg->kd = EXP005_SYS1_KD;
        cfg->kpp = EXP005_KP_PEND; cfg->kdp = EXP005_KD_PEND;
        cfg->step_deg = EXP005_DEFAULT_ROTOR_STEP_DEG;
        cfg->u_limit  = EXP005_DEFAULT_U_LIMIT;
        break;
    }
}

static bool in(double v, double lo, double hi)
{
    return isfinite(v) && v >= lo && v <= hi;
}

const char *ENR312_Runner_Validate(const ENR312_RunnerConfig_t *c)
{
    double ulimMax = (c->exp == 5) ? EXP005_DEFAULT_U_LIMIT
                   : (c->exp == 2) ? 4.0 * EXP002_DEFAULT_U_LIMIT
                                   : 4.0 * EXP003_DEFAULT_U_LIMIT;
    if (ENR312_Ctrl_Handles(c->exp))     { return ENR312_Ctrl_Validate(c); }
    if (c->exp < 2u || c->exp > 5u)      { return "exp must be 2..10 or 21..23"; }
    if (c->ki != 0.0 || c->k1 != 0.0 || c->k2 != 0.0 || c->k3 != 0.0 || c->k4 != 0.0 ||
        c->bv != 0.0 || c->imp_deg != 0.0 || c->uon != 0.0 || c->db != 0.0 ||
        c->div != 1u || c->ma != 1u) {
        return "parameter not used by Tutorials 2-5 (use exp 6..10, 21..23)";
    }
    if (!in(c->kp, 0.0, 100.0))          { return "kp out of 0..100"; }
    if (!in(c->kd, 0.0, 100.0))          { return "kd out of 0..100"; }
    if (!in(c->kpp, 0.0, 1000.0))        { return "kpp out of 0..1000"; }
    if (!in(c->kdp, 0.0, 200.0))         { return "kdp out of 0..200"; }
    if (!in(c->step_deg, -20.0, 20.0))   { return "step out of -20..20 deg"; }
    if (!in(c->dist, -100.0, 100.0))     { return "dist out of -100..100"; }
    if (!in(c->u_limit, 1.0, ulimMax))   { return "ulim out of range for this exp"; }
    if (!in(c->v_max, 10.0, 720.0))      { return "vmax out of 10..720 deg/s"; }
    return NULL;
}

double ENR312_Runner_UprightAngle(double psi_deg)
{
    double a = fmod(180.0 - psi_deg, 360.0);       /* (-360, 360) */
    if (a > 180.0)   { a -= 360.0; }
    if (a <= -180.0) { a += 360.0; }
    return a;
}

bool ENR312_Runner_Start(ENR312_Runner_t *r, const ENR312_RunnerConfig_t *cfg)
{
    if (ENR312_Runner_Validate(cfg) != NULL) {
        return false;
    }
    r->cfg = *cfg;
    r->state = ENR312_RUN_ACTIVE;
    r->abort_reason = ENR312_RUN_ABORT_NONE;
    r->core_abort = 0u;
    r->phase = 0u;
    r->tick = 0u;
    r->vsat_run = 0u;
    r->v_deg_s = 0.0;
    r->u = 0.0;
    r->ref_deg = 0.0;
    r->pend_deg = 0.0;

    if (ENR312_Ctrl_Handles(cfg->exp)) {
        ENR312_Ctrl_Init(&r->ec, cfg);
        return true;
    }
    switch (cfg->exp) {
    case 2:
        ENR312_Exp002_Init(&r->e2, cfg->kp, cfg->kd, true);
        ENR312_Exp002_SetExcitation(&r->e2, cfg->step_deg, cfg->dist);
        ENR312_Exp002_SetULimit(&r->e2, cfg->u_limit);
        break;
    case 3:
    case 4:
        ENR312_Exp003_Init(&r->e3, cfg->kp, cfg->kd, true);
        ENR312_Exp003_SetPendGains(&r->e3, cfg->kpp, cfg->kdp);
        ENR312_Exp003_SetRotorStep(&r->e3, cfg->step_deg);
        ENR312_Exp003_SetULimit(&r->e3, cfg->u_limit);
        break;
    default:
        ENR312_Exp005_Init(&r->e5, cfg->kp, cfg->kd, true);
        ENR312_Exp005_SetPendGains(&r->e5, cfg->kpp, cfg->kdp);
        ENR312_Exp005_SetRotorStep(&r->e5, cfg->step_deg);
        ENR312_Exp005_SetULimit(&r->e5, cfg->u_limit);
        ENR312_Exp005_SetHoldAfterDone(&r->e5, true);
        break;
    }
    return true;
}

void ENR312_Runner_Stop(ENR312_Runner_t *r)
{
    if (r->state == ENR312_RUN_ACTIVE) {
        r->state = ENR312_RUN_STOPPING;
    }
}

void ENR312_Runner_Abort(ENR312_Runner_t *r, ENR312_RunAbort_t why)
{
    if (r->state == ENR312_RUN_ACTIVE || r->state == ENR312_RUN_STOPPING) {
        r->state = ENR312_RUN_ABORTED;
        r->abort_reason = why;
    }
    r->v_deg_s = 0.0;
    r->u = 0.0;
}

bool ENR312_Runner_IsMoving(const ENR312_Runner_t *r)
{
    return r->state == ENR312_RUN_ACTIVE || r->state == ENR312_RUN_STOPPING;
}

double ENR312_Runner_Tick(ENR312_Runner_t *r, double rotor_deg, double psi_deg)
{
    if (!ENR312_Runner_IsMoving(r)) {
        r->v_deg_s = 0.0;
        return 0.0;
    }

    if (r->state == ENR312_RUN_ACTIVE) {
        bool finished = false, aborted = false;
        if (ENR312_Ctrl_Handles(r->cfg.exp)) {
            r->u = ENR312_Ctrl_Tick(&r->ec, rotor_deg, r->v_deg_s, psi_deg);
            r->ref_deg = r->ec.ref; r->pend_deg = r->ec.a_meas;
            r->phase = (uint8_t)r->ec.phase;
            aborted  = (r->ec.phase == CTRL_PH_ABORTED);
            finished = (r->ec.phase == CTRL_PH_DONE);
            r->core_abort = (uint8_t)r->ec.abort_reason;
        } else switch (r->cfg.exp) {
        case 2: {
            const ENR312_Exp002Sample_t *s = ENR312_Exp002_Tick(&r->e2, rotor_deg, 0.0);
            r->u = s->u; r->ref_deg = s->reference_deg; r->pend_deg = psi_deg;
            r->phase = s->phase;
            aborted  = (r->e2.phase == EXP002_PHASE_ABORTED);
            finished = ENR312_Exp002_IsFinished(&r->e2);
            r->core_abort = (uint8_t)r->e2.abort_reason;
            break;
        }
        case 3:
        case 4: {
            const ENR312_Exp003Sample_t *s = ENR312_Exp003_Tick(&r->e3, rotor_deg, psi_deg);
            r->u = s->u; r->ref_deg = s->rotor_ref_deg; r->pend_deg = psi_deg;
            r->phase = s->phase;
            aborted  = (r->e3.phase == EXP003_PHASE_ABORTED);
            finished = ENR312_Exp003_IsFinished(&r->e3);
            r->core_abort = (uint8_t)r->e3.abort_reason;
            break;
        }
        default: {
            double alpha = ENR312_Runner_UprightAngle(psi_deg);
            const ENR312_Exp005Sample_t *s = ENR312_Exp005_Tick(&r->e5, rotor_deg, alpha);
            r->u = s->u; r->ref_deg = s->rotor_ref_deg; r->pend_deg = alpha;
            r->phase = s->phase;
            aborted  = (r->e5.phase == EXP005_PHASE_ABORTED);
            finished = false;                      /* HOLD: balance until stopped */
            r->core_abort = (uint8_t)r->e5.abort_reason;
            break;
        }
        }
        if (aborted) {
            ENR312_Runner_Abort(r, ENR312_RUN_ABORT_CORE);
            r->tick++;
            return 0.0;
        }
        if (finished) {
            r->state = ENR312_RUN_STOPPING;
        }
    }

    if (r->state == ENR312_RUN_STOPPING) {
        /* decelerate at the plant-input limit; then rest */
        double dv = r->cfg.u_limit * RUN_TS;
        r->u = 0.0;
        if (fabs(r->v_deg_s) <= dv) {
            r->v_deg_s = 0.0;
            r->state = ENR312_RUN_FINISHED;
        } else {
            r->v_deg_s -= (r->v_deg_s > 0.0) ? dv : -dv;
        }
        r->tick++;
        return r->v_deg_s;
    }

    /* integrate the commanded acceleration into the step-rate command */
    r->v_deg_s += r->u * RUN_TS;
    if (fabs(r->v_deg_s) >= r->cfg.v_max) {
        r->v_deg_s = (r->v_deg_s > 0.0) ? r->cfg.v_max : -r->cfg.v_max;
        if (++r->vsat_run >= RUN_VSAT_TICKS) {
            ENR312_Runner_Abort(r, ENR312_RUN_ABORT_VELOCITY);
            r->tick++;
            return 0.0;
        }
    } else {
        r->vsat_run = 0u;
    }
    r->tick++;
    return r->v_deg_s;
}

const char *ENR312_Runner_PhaseName(const ENR312_Runner_t *r)
{
    static const char *const p2[] = {"IDLE", "REF_STEP", "REF_SETTLE", "DIST_STEP",
                                     "DIST_SETTLE", "DONE", "ABORTED"};
    static const char *const p3[] = {"IDLE", "ROTOR_STEP", "SETTLE", "DONE", "ABORTED"};
    static const char *const p5[] = {"WAIT_CAPTURE", "BALANCE", "ROTOR_STEP", "SETTLE",
                                     "HOLD", "ABORTED"};
    if (r->state == ENR312_RUN_IDLE) { return "IDLE"; }
    if (ENR312_Ctrl_Handles(r->cfg.exp)) { return ENR312_Ctrl_PhaseName(r->phase); }
    switch (r->cfg.exp) {
    case 2:  return (r->phase < 7u) ? p2[r->phase] : "?";
    case 3:
    case 4:  return (r->phase < 5u) ? p3[r->phase] : "?";
    default: return (r->phase < 6u) ? p5[r->phase] : "?";
    }
}

const char *ENR312_Runner_AbortName(const ENR312_Runner_t *r)
{
    switch (r->abort_reason) {
    case ENR312_RUN_ABORT_NONE:     return "NONE";
    case ENR312_RUN_ABORT_VELOCITY: return "VELOCITY_LIMIT";
    case ENR312_RUN_ABORT_OPERATOR: return "OPERATOR";
    case ENR312_RUN_ABORT_WATCHDOG: return "HOST_WATCHDOG";
    case ENR312_RUN_ABORT_CORE:     break;
    default:                        return "?";
    }
    if (ENR312_Ctrl_Handles(r->cfg.exp)) { return ENR312_Ctrl_AbortName(r->core_abort); }
    switch (r->cfg.exp) {
    case 2:
        return r->core_abort == EXP002_ABORT_ROTOR_LIMIT ? "ROTOR_LIMIT"
             : r->core_abort == EXP002_ABORT_SATURATION  ? "SATURATION" : "CORE";
    case 3:
    case 4:
        return r->core_abort == EXP003_ABORT_ROTOR_LIMIT    ? "ROTOR_LIMIT"
             : r->core_abort == EXP003_ABORT_PENDULUM_LIMIT ? "PENDULUM_LIMIT"
             : r->core_abort == EXP003_ABORT_SATURATION     ? "SATURATION" : "CORE";
    default:
        return r->core_abort == EXP005_ABORT_PENDULUM_LOST ? "PENDULUM_LOST"
             : r->core_abort == EXP005_ABORT_ROTOR_LIMIT   ? "ROTOR_LIMIT"
             : r->core_abort == EXP005_ABORT_SATURATION    ? "SATURATION" : "CORE";
    }
}

void ENR312_Runner_ApplyLive(ENR312_Runner_t *r, const ENR312_RunnerConfig_t *cfg)
{
    if (ENR312_Runner_IsMoving(r) && ENR312_Ctrl_Handles(r->cfg.exp) && cfg->exp == r->cfg.exp) {
        ENR312_Ctrl_SetGains(&r->ec, cfg);
        r->cfg.u_limit = cfg->u_limit;
        r->cfg.v_max = cfg->v_max;
    }
}

bool ENR312_Runner_SetRef(ENR312_Runner_t *r, double ref_deg)
{
    if (!ENR312_Runner_IsMoving(r) || !ENR312_Ctrl_Handles(r->cfg.exp)) { return false; }
    ENR312_Ctrl_SetRef(&r->ec, ref_deg);
    return true;
}

bool ENR312_Runner_SuspendedLimit(const ENR312_Runner_t *r)
{
    return ENR312_Runner_IsMoving(r) && r->cfg.exp != 5u && !ENR312_Ctrl_Inverted(r->cfg.exp);
}

bool ENR312_Runner_NeedsCapture(uint8_t exp)
{
    return exp == 5u || exp == 6u || exp == 7u || exp == 8u || exp == 23u;
}

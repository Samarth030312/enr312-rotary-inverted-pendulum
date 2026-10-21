/**
 * @file    enr312_ctrl.c
 * @brief   General controller core (Tutorials 6-10, PEND). See enr312_ctrl.h.
 *
 * Mirrored line by line in matlab/+odyssix/+sim/runCtrl.m: keep the order of
 * floating-point operations identical when changing anything here.
 */
#include "enr312_ctrl.h"
#include <math.h>
#include <stddef.h>

#define TS          ENR312_CONTROL_PERIOD_S
#define SEC(s)      ((uint32_t)(ENR312_CONTROL_RATE_HZ * (s)))
#define PI_         3.14159265358979323846

/* sequence timing */
/* 5 s: after the hand lets go the arm swings about +/-5 deg and is back in its
 * +/-1 deg balancing wobble after ~3 s (simulation); a 2 s wait started the
 * Tutorial 6 step on top of that transient */
#define T_BALANCE   SEC(5u)
#define T_STEP      SEC(15u)
#define T_STEP8     SEC(10u)
#define T_DIST      SEC(10u)
#define T_IMP_EVERY SEC(5u)
#define T_IMP_LEN   2u                    /* 4 ms, Tutorial 7 */
#define N_IMPULSES  8u
#define T_IDLE      SEC(1u)


static double clampd(double v, double lim) { return v > lim ? lim : (v < -lim ? -lim : v); }

static double alpha_of(double psi)
{
    double a = fmod(180.0 - psi, 360.0);
    if (a > 180.0)   { a -= 360.0; }
    if (a <= -180.0) { a += 360.0; }
    return a;
}

static double hang_of(double psi)              /* wrap to (-180, 180]: 360 = hanging */
{
    double a = fmod(psi, 360.0);
    if (a > 180.0)   { a -= 360.0; }
    if (a <= -180.0) { a += 360.0; }
    return a;
}

static double lp_alpha(double fc, double dt)
{
    if (fc <= 0.0) { return 1.0; }
    double a = 1.0 - exp(-2.0 * PI_ * fc * dt);
    return (a > 1.0) ? 1.0 : (a < 0.0 ? 0.0 : a);
}

bool ENR312_Ctrl_Handles(uint8_t exp)
{
    return (exp >= 6u && exp <= 10u) || (exp >= 21u && exp <= 24u);
}

bool ENR312_Ctrl_Inverted(uint8_t exp)
{
    return exp == 6u || exp == 7u || exp == 8u || exp == 23u || exp == 24u;
}

static bool state_feedback(uint8_t exp) { return exp == 9u || exp == 10u || exp == 23u || exp == 24u; }

bool ENR312_Ctrl_Defaults(ENR312_CtrlConfig_t *c, uint8_t exp)
{
    c->exp = exp;
    c->kp = 0.0; c->ki = 0.0; c->kd = 0.0; c->kpp = 0.0; c->kdp = 0.0;
    c->fdr = 50.0; c->fdp = 10.0;
    c->k1 = 0.0; c->k2 = 0.0; c->k3 = 0.0; c->k4 = 0.0; c->bv = 0.0;
    c->step_deg = 0.0; c->dist = 0.0; c->imp_deg = 0.0;
    c->uon = 0.0; c->db = 0.0;
    c->u_limit = 1500.0; c->v_max = 360.0; c->ref_rate = 90.0;
    c->div = 1u; c->ma = 1u; c->seq = 1u; c->wg2 = 55.85; c->amp = 180.0;
    switch (exp) {
    case 6:  /* Tutorial 6 reference design: Kp 15, Ti 5 s (Ki 3), Td 0.5 s */
        c->kp = 15.0; c->ki = 3.0; c->kd = 7.5; c->kpp = 300.0; c->kdp = 30.0;
        c->step_deg = 40.0;
        break;
    case 7:  /* Tutorial 7: rotor PID fixed at 15/0/7.5, pendulum PD designed */
        c->kp = 15.0; c->kd = 7.5; c->kpp = 300.0; c->kdp = 30.0; c->imp_deg = 10.0;
        break;
    case 8:  /* Tutorial 8: Kp 15, Ti 2 s (Ki 7.5), Td 0.5 s */
        c->kp = 15.0; c->ki = 7.5; c->kd = 7.5; c->kpp = 300.0; c->kdp = 30.0;
        /* D 60: the tutorial gives only S_D(0) = 1/Kp; 60 deg/s^2 makes the
         * no-integral offset D/Kp = 4 deg, well clear of the +/-1 deg wobble */
        c->step_deg = 40.0; c->dist = 60.0;
        break;
    case 9:  /* Tutorial 9 reference: wN = 1, zeta = 1 -> K = [1 2] */
        c->k1 = 1.0; c->k2 = 2.0; c->step_deg = 20.0; c->u_limit = 800.0;
        break;
    case 10: /* Tutorial 10: LQR with Q = I, R = 1 for 1/s^2 -> K = [1 1.7321] */
        c->k1 = 1.0; c->k2 = 1.7321; c->step_deg = 20.0; c->u_limit = 800.0;
        break;
    case 21: /* PEND swing stop: Tutorial 3 design 1 gains */
        c->kp = 6.0; c->kd = 4.8; c->kpp = 10.0; c->kdp = 5.0; c->fdr = 10.0;
        c->u_limit = 800.0;
        break;
    case 22: /* PEND on-off control */
        c->uon = 200.0; c->db = 0.5; c->step_deg = 20.0; c->u_limit = 800.0;
        break;
    case 23: /* PEND inverted LQR: Q = diag(1,1,10,1), R = 0.01, Tutorial 5 plant
              * (odyssix.ctrl.lqr with odyssix.ctrl.pendulumModel('inverted')) */
        c->k1 = -10.0; c->k2 = -13.787; c->k3 = 382.789; c->k4 = 50.787;
        c->step_deg = 20.0;
        c->fdp = 5.0;   /* k4 51 on a 10 Hz rate made u rms 212 (PID: 135); 5 Hz: 139, alpha rms 0.21 deg */
        break;
    case 24: /* PEND swing-up: pump 1000 deg/s^2, arm centring PD 4/4, exp 23 LQR catch, 720 deg/s */
        c->uon = 1000.0; c->kp = 4.0; c->kd = 4.0;
        c->v_max = 720.0;   /* the catch needs the arm fast: at 360 deg/s it saturated */
        c->fdp = 5.0;       /* as exp 23 */
        c->k1 = -10.0; c->k2 = -13.787; c->k3 = 382.789; c->k4 = 50.787;
        break;
    default:
        return false;
    }
    return true;
}

static bool in(double v, double lo, double hi) { return isfinite(v) && v >= lo && v <= hi; }

const char *ENR312_Ctrl_Validate(const ENR312_CtrlConfig_t *c)
{
    if (!ENR312_Ctrl_Handles(c->exp))       { return "exp not handled here"; }
    if (!in(c->kp, 0.0, 100.0) || !in(c->ki, 0.0, 100.0) || !in(c->kd, 0.0, 100.0)) {
        return "rotor gains out of 0..100";
    }
    if (!in(c->kpp, 0.0, 1000.0) || !in(c->kdp, 0.0, 200.0)) { return "pendulum gains out of range"; }
    if (!in(c->fdr, 0.5, 200.0) || !in(c->fdp, 0.5, 200.0))   { return "fdr/fdp out of 0.5..200 Hz"; }
    if (!in(c->k1, -1000.0, 1000.0) || !in(c->k2, -1000.0, 1000.0) ||
        !in(c->k3, -5000.0, 5000.0) || !in(c->k4, -1000.0, 1000.0)) { return "k1..k4 out of range"; }
    if (!in(c->bv, 0.0, 10.0))               { return "bv out of 0..10"; }
    if (!in(c->step_deg, -45.0, 45.0))       { return "step out of -45..45 deg"; }
    if (!in(c->dist, -200.0, 200.0))         { return "dist out of -200..200"; }
    if (!in(c->imp_deg, -20.0, 20.0))        { return "imp out of -20..20 deg"; }
    if (!in(c->uon, 0.0, 1500.0) || !in(c->db, 0.0, 10.0)) { return "uon/db out of range"; }
    if (!in(c->u_limit, 1.0, 1500.0))        { return "ulim out of 1..1500"; }
    if (!in(c->v_max, 10.0, 720.0))          { return "vmax out of 10..720 deg/s"; }
    if (!in(c->ref_rate, 0.0, 360.0))        { return "rrate out of 0..360 deg/s"; }
    if (c->div < 1u || c->div > CTRL_DIV_MAX) { return "div out of 1..50"; }
    if (c->ma < 1u || c->ma > CTRL_MA_MAX)    { return "ma out of 1..32"; }
    if (c->seq > 1u)                          { return "seq must be 0 or 1"; }
    if (!in(c->wg2, 20.0, 120.0))             { return "wg2 out of 20..120 1/s^2"; }
    if (!in(c->amp, 0.0, 180.0))              { return "amp out of 0..180 deg"; }
    return NULL;
}

void ENR312_Ctrl_SetGains(ENR312_Ctrl_t *x, const ENR312_CtrlConfig_t *c)
{
    x->c.kp = c->kp; x->c.ki = c->ki; x->c.kd = c->kd; x->c.kpp = c->kpp; x->c.kdp = c->kdp;
    x->c.fdr = c->fdr; x->c.fdp = c->fdp;
    x->c.k1 = c->k1; x->c.k2 = c->k2; x->c.k3 = c->k3; x->c.k4 = c->k4; x->c.bv = c->bv;
    x->c.uon = c->uon; x->c.db = c->db; x->c.wg2 = c->wg2; x->c.amp = c->amp;
    x->c.u_limit = c->u_limit; x->c.ref_rate = c->ref_rate; x->c.dist = c->dist;
    x->c.div = c->div;
    if (c->ma != x->c.ma) {                       /* restart the average cleanly */
        x->c.ma = c->ma; x->ma_n = 0u; x->ma_i = 0u; x->ma_sum = 0.0;
    }
}

void ENR312_Ctrl_SetRef(ENR312_Ctrl_t *x, double ref_deg) { x->ref_live = ref_deg; x->home_pending = false; }

void ENR312_Ctrl_Init(ENR312_Ctrl_t *x, const ENR312_CtrlConfig_t *c)
{
    x->c = *c;
    x->phase = (c->exp == 24u) ? CTRL_PH_SWINGUP
             : ENR312_Ctrl_Inverted(c->exp) ? CTRL_PH_WAIT_CAPTURE
             : (c->exp == 21u || c->seq == 0u) ? CTRL_PH_REGULATE : CTRL_PH_IDLE;
    x->abort_reason = CTRL_ABORT_NONE;
    x->tick = 0u; x->phase_tick = 0u; x->n_imp = 0u;
    x->capture_run = 0u; x->warn_run = 0u; x->sat_run = 0u;
    x->a_capture = 0.0; x->ref_live = 0.0; x->ref_now = 0.0;
    x->ir = 0.0; x->er_prev = 0.0; x->dr = 0.0; x->r_have = false;
    x->ep_prev = 0.0; x->dp = 0.0; x->p_have = false;
    x->psi_prev = 0.0; x->dpsi = 0.0; x->psi_have = false;
    x->ma_n = 0u; x->ma_i = 0u; x->ma_sum = 0.0;
    for (uint32_t i = 0; i < CTRL_MA_MAX; ++i) { x->ma_buf[i] = 0.0; }
    x->div_count = 0u; x->u_hold = 0.0; x->sw_energy = 0.0;
    x->sw_delta = (c->amp >= 179.0) ? CTRL_SW_DELTA0 : 0.0;   /* the climb-loss guess is for swing-up only */
    x->sw_dpsi_prev = 0.0; x->sw_epeak = 0.0; x->sw_over = false;
    x->sw_amp_prev = c->amp; x->home_pending = false; x->trim = 0.0;
    x->u = 0.0; x->u_rotor = 0.0; x->u_pend = 0.0; x->ref = 0.0; x->pend_ref = 0.0; x->a_meas = 0.0;
}

bool ENR312_Ctrl_IsFinished(const ENR312_Ctrl_t *x)
{
    return x->phase == CTRL_PH_DONE || x->phase == CTRL_PH_ABORTED;
}

static void advance(ENR312_Ctrl_t *x, ENR312_CtrlPhase_t p) { x->phase = p; x->phase_tick = 0u; }

static bool controlling(const ENR312_Ctrl_t *x)
{
    return x->phase != CTRL_PH_WAIT_CAPTURE && x->phase != CTRL_PH_WAIT_RELEASE &&
           x->phase != CTRL_PH_DONE && x->phase != CTRL_PH_ABORTED;
}

double ENR312_Ctrl_Tick(ENR312_Ctrl_t *x, double theta, double thetadot, double psi)
{
    const ENR312_CtrlConfig_t *c = &x->c;
    bool inv = ENR312_Ctrl_Inverted(c->exp);

    /* ---- measurement: moving average on the encoder angle (every tick) ---- */
    if (x->ma_n == c->ma) { x->ma_sum -= x->ma_buf[x->ma_i]; } else { x->ma_n++; }
    x->ma_buf[x->ma_i] = psi;
    x->ma_sum += psi;
    x->ma_i = (uint8_t)((x->ma_i + 1u) % c->ma);
    double psi_f = x->ma_sum / (double)x->ma_n;
    /* hanging mode: wrapped, so a pendulum at rest after a full turn (psi 360)
     * reads 0; the rate (dpsi) and the swing-up use the continuous count */
    double a_raw = inv ? alpha_of(psi) : hang_of(psi);
    double a_f   = inv ? alpha_of(psi_f) : hang_of(psi_f);
    /* upright auto-trim (header): learn the mean alpha in HOLD, control on the rest */
    if (inv && x->phase == CTRL_PH_HOLD) { x->trim += (a_f - x->trim) * TS / CTRL_TRIM_TAU_S; }
    double a_c = inv ? (a_f - x->trim) : a_f;

    /* ---- release detection (same rule as EXP005 2.0.8) -------------------- */
    if (x->phase == CTRL_PH_WAIT_RELEASE && fabs(a_raw - x->a_capture) >= CTRL_RELEASE_DEG) {
        advance(x, (c->seq == 0u) ? CTRL_PH_HOLD : CTRL_PH_BALANCE);
    }

    /* ---- references -------------------------------------------------------- */
    double step = 0.0;
    if (x->phase == CTRL_PH_STEP) { step = c->step_deg; }
    double ref = step;
    if (x->phase == CTRL_PH_HOLD || x->phase == CTRL_PH_REGULATE) {
        double d = x->ref_live - x->ref_now, lim = c->ref_rate * TS;
        if (c->ref_rate > 0.0 && d > lim)  { d = lim; }
        if (c->ref_rate > 0.0 && d < -lim) { d = -lim; }
        x->ref_now += d;
        ref = x->ref_now;
    }
    double pend_ref = 0.0;
    if (x->phase == CTRL_PH_IMPULSES && (x->phase_tick % T_IMP_EVERY) >= (T_IMP_EVERY - T_IMP_LEN)) {
        pend_ref = c->imp_deg;
    }
    double dist = (x->phase == CTRL_PH_DIST) ? c->dist : 0.0;

    /* ---- control law (computed every div ticks, held in between) ---------- */
    bool ctl = controlling(x);
    double u_unsat = 0.0;
    if (!ctl) {
        x->div_count = 0u; x->u_hold = 0.0; x->u_rotor = 0.0; x->u_pend = 0.0;
    } else if (x->div_count == 0u) {
        double dt = TS * (double)c->div;
        /* derivative of the (filtered) encoder angle, for state feedback */
        double rawd = x->psi_have ? (psi_f - x->psi_prev) / dt : 0.0;
        x->dpsi += lp_alpha(c->fdp, dt) * (rawd - x->dpsi);
        x->psi_prev = psi_f; x->psi_have = true;
        double adot = inv ? -x->dpsi : x->dpsi;      /* alpha = 180 - psi */

        if (x->phase == CTRL_PH_SWINGUP) {
            /* energy control (see the header); psi in rad, psidot in rad/s.
             * Target height h* = 2 (upright) for amp >= 179, else 1 - cos(amp). */
            bool upr = c->amp >= 179.0;
            double hstar = upr ? 2.0 : 1.0 - cos(c->amp * PI_ / 180.0);
            if (c->amp != x->sw_amp_prev) {                  /* new target: relearn the loss */
                x->sw_delta = upr ? CTRL_SW_DELTA0 : 0.0; x->sw_epeak = 0.0; x->sw_amp_prev = c->amp;
            }
            double pr = psi_f * PI_ / 180.0, pdr = x->dpsi * PI_ / 180.0;
            double en = pdr * pdr / (2.0 * c->wg2) + 1.0 - cos(pr);
            double dir = pdr * cos(pr);
            double s = (dir > 0.0) ? 1.0 : ((dir < 0.0) ? -1.0 : 0.0);
            if (s == 0.0 && en < 0.05) { s = 1.0; }          /* kick from rest (swing-up) */
            /* learn the climb loss from each apex (rate changes sign), only on
             * swings where the pump had already reached its target */
            if (en > x->sw_epeak) { x->sw_epeak = en; }
            if (x->dpsi * x->sw_dpsi_prev < 0.0) {                   /* an apex */
                double happ = 1.0 - cos(pr);
                if (upr) {
                    if (cos(pr) < 0.0 && x->sw_epeak >= 2.0 + x->sw_delta - 0.1) {
                        x->sw_delta += CTRL_SW_KA * (2.0 - happ);
                    }
                } else if (hstar > 0.0 && x->sw_epeak >= 0.8 * (hstar + x->sw_delta)) {
                    x->sw_delta += CTRL_SW_KA * (hstar - happ);       /* both ways */
                }
                x->sw_epeak = 0.0;
            }
            if (upr && fabs(a_raw) < 5.0 && fabs(x->dpsi) > CTRL_SW_OVER_RATE && !x->sw_over) {
                x->sw_delta -= CTRL_SW_KA_OVER * (en - 2.0);         /* over the top too fast */
                x->sw_over = true;
            }
            if (fabs(a_raw) > 30.0) { x->sw_over = false; }
            x->sw_delta = (x->sw_delta < CTRL_SW_DELTA_MIN) ? CTRL_SW_DELTA_MIN
                        : ((x->sw_delta > CTRL_SW_DELTA_MAX) ? CTRL_SW_DELTA_MAX : x->sw_delta);
            x->sw_dpsi_prev = x->dpsi;
            double et = hstar + x->sw_delta;
            double up;
            if (upr) {
                /* swing-up: pump at full strength until close (rig: 3/3 caught) */
                up = c->uon * clampd(CTRL_SW_KE * (et - en), 1.0) * s;
            } else {
                /* amplitude: the Astrom-Furuta law u = k (E* - E) psidot cos(psi);
                 * dE/dt ~ (E* - E)(psidot cos psi)^2, so it only removes energy
                 * above the target and fades out near it (bang-bang shook small
                 * swings instead of stopping them) */
                up = c->uon * clampd(CTRL_SW_KE_AMP * (et - en) * pdr * cos(pr) / sqrt(c->wg2), 1.0);
            }
            /* never push the arm on past 80 % of its speed ceiling */
            if (fabs(thetadot) > 0.8 * c->v_max && up * thetadot > 0.0) { up = 0.0; }
            x->u_rotor = -(c->kp * theta + c->kd * thetadot);
            x->u_pend = up;
            x->sw_energy = en;
            u_unsat = x->u_rotor + x->u_pend;
        } else if (state_feedback(c->exp)) {
            x->u_rotor = -(c->k1 * (theta - ref) + c->k2 * thetadot);
            x->u_pend  = -(c->k3 * a_c + c->k4 * adot);
            u_unsat = x->u_rotor + x->u_pend - c->bv * thetadot;
        } else if (c->exp == 22u) {
            double e = ref - theta;
            x->u_rotor = (e > c->db) ? c->uon : ((e < -c->db) ? -c->uon : 0.0);
            x->u_pend = 0.0;
            u_unsat = x->u_rotor;
        } else {
            /* dual PID: rotor PID on the angle error, pendulum PD on its error */
            double er = ref - theta;
            double der = x->r_have ? (er - x->er_prev) / dt : 0.0;
            x->dr += lp_alpha(c->fdr, dt) * (der - x->dr);
            x->er_prev = er; x->r_have = true;
            double ur = c->kp * er + c->kd * x->dr + x->ir;
            double ep = pend_ref - a_c;
            double dep = x->p_have ? (ep - x->ep_prev) / dt : 0.0;
            x->dp += lp_alpha(c->fdp, dt) * (dep - x->dp);
            x->ep_prev = ep; x->p_have = true;
            double up = c->kpp * ep + c->kdp * x->dp;
            x->u_rotor = inv ? -ur : ur;
            x->u_pend = up;
            u_unsat = x->u_rotor + x->u_pend;
            /* integral with conditional anti-windup: integrate only while the
             * output is not saturated, and never beyond the actuator limit */
            if (c->ki > 0.0 && fabs(u_unsat) < c->u_limit) {
                x->ir += c->ki * er * dt;
                x->ir = clampd(x->ir, c->u_limit);
            }
        }
        x->u_hold = u_unsat;
        x->div_count = (uint8_t)(c->div - 1u);
    } else {
        x->div_count--;
        u_unsat = x->u_hold;
    }
    double u = clampd(u_unsat, c->u_limit);
    bool clipped = ctl && (u != u_unsat);
    u += ctl ? dist : 0.0;

    /* ---- safety ----------------------------------------------------------- */
    if (!ENR312_Ctrl_IsFinished(x)) {
        if (fabs(theta) > ENR312_ROTOR_LIMIT_DEG) {
            advance(x, CTRL_PH_ABORTED); x->abort_reason = CTRL_ABORT_ROTOR_LIMIT;
        } else if (x->phase == CTRL_PH_SWINGUP) {
            x->warn_run = 0u; x->sat_run = 0u;        /* swinging: no upright bounds */
        } else if (inv && fabs(a_raw) > CTRL_PEND_ABORT_DEG) {
            advance(x, CTRL_PH_ABORTED); x->abort_reason = CTRL_ABORT_PENDULUM_LOST;
        } else {
            if (inv && ctl && fabs(a_raw) > CTRL_PEND_WARN_DEG) {
                if (++x->warn_run >= CTRL_PEND_WARN_TICKS) {
                    advance(x, CTRL_PH_ABORTED); x->abort_reason = CTRL_ABORT_PENDULUM_LOST;
                }
            } else {
                x->warn_run = 0u;
            }
            /* swing-up: catching a moving pendulum saturates the input for a
             * moment by design; the 15 deg bound still guards those 0.5 s */
            bool catching = (c->exp == 24u && x->phase == CTRL_PH_HOLD && x->phase_tick < SEC(0.5));
            /* holding upright, a tap saturates the input while the loop recovers
             * (rig 2026-10-21 R01: aborted mid-recovery at 200 ms); the 15 deg,
             * arm and speed bounds still guard. Sequences keep 200 ms. */
            uint32_t sat_ticks = (inv && x->phase == CTRL_PH_HOLD) ? CTRL_SAT_ABORT_UP_TICKS : CTRL_SAT_ABORT_TICKS;
            if (clipped && c->exp != 22u && !catching) {
                if (++x->sat_run >= sat_ticks) {
                    advance(x, CTRL_PH_ABORTED); x->abort_reason = CTRL_ABORT_SATURATION;
                }
            } else {
                x->sat_run = 0u;
            }
        }
    }
    if (x->phase == CTRL_PH_ABORTED) { u = 0.0; }

    /* ---- sequence (a transition takes effect from the next tick) ------------ */
    switch (x->phase) {
    case CTRL_PH_WAIT_CAPTURE:
        if (fabs(a_raw) <= CTRL_CAPTURE_DEG) {
            if (++x->capture_run >= CTRL_CAPTURE_TICKS) {
                x->a_capture = a_raw;
                advance(x, CTRL_PH_WAIT_RELEASE);
            }
        } else {
            x->capture_run = 0u;
        }
        break;
    case CTRL_PH_SWINGUP: {
        /* catch: slow anywhere inside the window, or still approaching from its
         * edge (gravity is slowing it; the LQR completes the stop) */
        double adot_c = -x->dpsi;                                     /* alpha = 180 - psi */
        bool slow = fabs(x->dpsi) <= CTRL_SW_CATCH_RATE;
        bool approaching = fabs(a_raw) >= 2.0 && a_raw * adot_c < 0.0 && fabs(x->dpsi) <= CTRL_SW_CATCH_APPROACH;
        /* feasibility: what the catching LQR would ask for at once */
        double u_catch = c->k2 * thetadot + c->k3 * a_raw + c->k4 * adot_c;
        bool feasible = fabs(u_catch) <= CTRL_SW_CATCH_UMAX * c->u_limit;
        if (c->amp >= 179.0 && fabs(a_raw) <= CTRL_SW_CATCH_DEG && (slow || approaching) && feasible &&
            x->sw_energy >= CTRL_SW_E_MIN) {
            /* start from where it caught, then bring the arm home (slewed at rrate) */
            x->ref_now = theta; x->ref_live = theta; x->home_pending = true;
            advance(x, CTRL_PH_HOLD);
        } else if (c->amp >= 179.0 && x->phase_tick >= CTRL_SW_TIMEOUT_TICKS) {
            advance(x, CTRL_PH_DONE);
        }
        break;
    }
    case CTRL_PH_HOLD:
        if (x->home_pending && x->phase_tick >= CTRL_SW_HOME_TICKS) {   /* swing-up: walk home */
            x->ref_live = 0.0; x->home_pending = false;
        }
        break;
    case CTRL_PH_BALANCE:
        if (x->phase_tick >= T_BALANCE) {
            advance(x, (c->exp == 7u) ? CTRL_PH_IMPULSES : CTRL_PH_STEP);
        }
        break;
    case CTRL_PH_IDLE:
        if (x->phase_tick >= T_IDLE) { advance(x, CTRL_PH_STEP); }
        break;
    case CTRL_PH_STEP:
        if (x->phase_tick >= ((c->exp == 8u) ? T_STEP8 : T_STEP)) { advance(x, CTRL_PH_STEP_BACK); }
        break;
    case CTRL_PH_STEP_BACK:
        if (x->phase_tick >= ((c->exp == 8u) ? T_STEP8 : T_STEP)) {
            advance(x, (c->exp == 8u) ? CTRL_PH_DIST : (inv ? CTRL_PH_HOLD : CTRL_PH_DONE));
        }
        break;
    case CTRL_PH_DIST:
        if (x->phase_tick >= T_DIST) { advance(x, CTRL_PH_DIST_OFF); }
        break;
    case CTRL_PH_DIST_OFF:
        if (x->phase_tick >= T_DIST) { advance(x, CTRL_PH_HOLD); }
        break;
    case CTRL_PH_IMPULSES:
        if (x->phase_tick >= T_IMP_EVERY * N_IMPULSES) { advance(x, CTRL_PH_HOLD); }
        break;
    default:
        break;
    }

    x->tick++;
    x->phase_tick++;
    x->ref = ref; x->pend_ref = pend_ref; x->a_meas = a_f;
    return x->u = u;
}

const char *ENR312_Ctrl_PhaseName(uint8_t p)
{
    static const char *const n[] = {"WAIT_CAPTURE", "WAIT_RELEASE", "BALANCE", "STEP",
        "STEP_BACK", "DIST", "DIST_OFF", "IMPULSES", "HOLD", "IDLE", "REGULATE",
        "SWINGUP", "DONE", "ABORTED"};
    return (p < 14u) ? n[p] : "?";
}

const char *ENR312_Ctrl_AbortName(uint8_t r)
{
    switch (r) {
    case CTRL_ABORT_PENDULUM_LOST: return "PENDULUM_LOST";
    case CTRL_ABORT_ROTOR_LIMIT:   return "ROTOR_LIMIT";
    case CTRL_ABORT_SATURATION:    return "SATURATION";
    case CTRL_ABORT_OPERATOR:      return "OPERATOR";
    default:                       return "CORE";
    }
}

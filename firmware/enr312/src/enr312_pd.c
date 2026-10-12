/**
 * @file    enr312_pd.c
 * @brief   EXP002 discrete PD controller implementation. See enr312_pd.h.
 */

#include "enr312_pd.h"
#include <math.h>

double ENR312_PD_AlphaFromFc(double fc_hz, double ts_s)
{
    if (fc_hz <= 0.0 || ts_s <= 0.0) {
        return 1.0;                       /* 1.0 == no filtering (pass-through) */
    }
    /* a = 1 - exp(-2*pi*fc*Ts) -- the standard first-order discrete low-pass
     * coefficient. Steady-state noise gain is sqrt(a/(2-a)). */
    double a = 1.0 - exp(-ENR312_TWO_PI * fc_hz * ts_s);
    if (a > 1.0) { a = 1.0; }
    if (a < 0.0) { a = 0.0; }
    return a;
}

void ENR312_PD_Init(ENR312_PD_t *c, double kp, double kd, double ts_s, double fc_hz)
{
    c->kp          = kp;
    c->kd          = kd;
    c->ts_s        = (ts_s > 0.0) ? ts_s : ENR312_CONTROL_PERIOD_S;
    c->deriv_alpha = ENR312_PD_AlphaFromFc(fc_hz, c->ts_s);
    c->u_limit     = ENR312_PD_DEFAULT_U_LIMIT;
    ENR312_PD_Reset(c);
}

void ENR312_PD_SetOutputLimit(ENR312_PD_t *c, double limit)
{
    c->u_limit = (limit > 0.0) ? limit : ENR312_PD_DEFAULT_U_LIMIT;
}

void ENR312_PD_Reset(ENR312_PD_t *c)
{
    c->prev_error        = 0.0;
    c->deriv_state       = 0.0;
    c->have_prev         = false;
    c->saturation_events = 0u;
}

void ENR312_PD_Update(ENR312_PD_t *c, ENR312_PD_Signals_t *sig)
{
    /* Measurement noise N enters at the sensor, so the controller sees Y + N.
     * This is the whole point of the N injection path: it lets the noise
     * sensitivity C/(1+PC) be measured. */
    double y_sensed = sig->measured + sig->noise;
    double e        = sig->reference - y_sensed;

    /* Filtered derivative of the error.
     * First sample after Init/Reset has no predecessor, so the derivative is
     * defined as zero rather than as a spike from an uninitialised prev_error. */
    double raw_deriv = 0.0;
    if (c->have_prev) {
        raw_deriv = (e - c->prev_error) / c->ts_s;
    }
    c->deriv_state += c->deriv_alpha * (raw_deriv - c->deriv_state);

    double u_unsat = c->kp * e + c->kd * c->deriv_state;

    double u = u_unsat;
    if (u > c->u_limit)  { u =  c->u_limit; c->saturation_events++; }
    if (u < -c->u_limit) { u = -c->u_limit; c->saturation_events++; }

    /* Load disturbance D is summed at the PLANT INPUT, after the controller and
     * after saturation -- it represents a load the controller cannot see. */
    sig->error    = e;
    sig->u_unsat  = u_unsat;
    sig->u        = u + sig->disturbance;

    c->prev_error = e;
    c->have_prev  = true;
}

double ENR312_PD_PredictStepDemand(const ENR312_PD_t *c, double amplitude)
{
    if (c->ts_s <= 0.0) {
        return INFINITY;
    }
    return fabs(amplitude) * (fabs(c->kp) + fabs(c->kd) * c->deriv_alpha / c->ts_s);
}

double ENR312_PD_LoadDisturbanceOffset(const ENR312_PD_t *c)
{
    if (c->kp == 0.0) {
        return INFINITY;
    }
    return 1.0 / c->kp;
}

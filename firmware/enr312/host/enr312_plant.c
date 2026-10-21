/**
 * @file    enr312_plant.c
 * @brief   HOST ONLY: see enr312_plant.h.
 */
#include "enr312_plant.h"
#include "enr312_rig_config.h"
#include <math.h>

#define USTEP_PER_DEG  ((double)ENR312_ROTOR_MICROSTEPS_PER_REV / 360.0)
#define DEG2RAD        (3.14159265358979323846 / 180.0)

void ENR312_Plant_Init(ENR312_Plant_t *p, double wg2, double q, double wr2)
{
    p->wg2 = wg2; p->wr2 = wr2; p->gamma = sqrt(wg2) / q;
    p->psi = 0.0; p->psid = 0.0; p->v_prev = 0.0; p->step_acc = 0.0;
    p->pos = 0; p->t = 0.0; p->held = false; p->enc_bias = 0.0; p->coulomb = 0.0;
}

static void deriv(const ENR312_Plant_t *p, double psi, double psid, double thd,
                  double *dpsi, double *dpsid)
{
    *dpsi  = psid;
    *dpsid = -p->wg2 * sin(psi) + thd * thd * sin(psi) * cos(psi) - p->gamma * psid;
}

void ENR312_Plant_Step(ENR312_Plant_t *p, double rate_usteps, double dt)
{
    /* arm: integrate the step train exactly as the step generator emits it */
    p->step_acc += fabs(rate_usteps) * dt;
    int64_t k = (int64_t)p->step_acc;
    p->step_acc -= (double)k;
    p->pos += (rate_usteps >= 0.0) ? k : -k;

    double v = rate_usteps / USTEP_PER_DEG * DEG2RAD;          /* rad/s */
    if (p->held) {
        p->psid = 0.0;
    } else if (v != p->v_prev) {
        p->psid += p->wr2 * cos(p->psi) * (v - p->v_prev);     /* impulse */
    }
    p->v_prev = v;

    if (!p->held && p->coulomb > 0.0) {
        /* stick-slip pivot friction: stuck while gravity cannot beat it; moving,
         * a constant torque against the motion; a reversal inside a step sticks */
        double drive = -p->wg2 * sin(p->psi) + v * v * sin(p->psi) * cos(p->psi);
        if (p->psid == 0.0 && fabs(drive) <= p->coulomb) {
            p->t += dt;
            return;
        }
        double fsgn = (p->psid > 0.0) ? 1.0 : ((p->psid < 0.0) ? -1.0 : ((drive > 0.0) ? 1.0 : -1.0));
        double a1, b1, a2, b2, a3, b3, a4, b4, w0 = p->psid;
        deriv(p, p->psi, p->psid, v, &a1, &b1);
        deriv(p, p->psi + dt / 2 * a1, p->psid + dt / 2 * b1, v, &a2, &b2);
        deriv(p, p->psi + dt / 2 * a2, p->psid + dt / 2 * b2, v, &a3, &b3);
        deriv(p, p->psi + dt * a3, p->psid + dt * b3, v, &a4, &b4);
        p->psi  += dt / 6 * (a1 + 2 * a2 + 2 * a3 + a4);
        p->psid += dt / 6 * (b1 + 2 * b2 + 2 * b3 + b4) - fsgn * p->coulomb * dt;
        if (w0 != 0.0 && p->psid * w0 < 0.0) { p->psid = 0.0; }        /* reversal: stick */
        p->t += dt;
        return;
    }
    if (!p->held) {
        double a1, b1, a2, b2, a3, b3, a4, b4;
        deriv(p, p->psi, p->psid, v, &a1, &b1);
        deriv(p, p->psi + dt / 2 * a1, p->psid + dt / 2 * b1, v, &a2, &b2);
        deriv(p, p->psi + dt / 2 * a2, p->psid + dt / 2 * b2, v, &a3, &b3);
        deriv(p, p->psi + dt * a3, p->psid + dt * b3, v, &a4, &b4);
        p->psi  += dt / 6 * (a1 + 2 * a2 + 2 * a3 + a4);
        p->psid += dt / 6 * (b1 + 2 * b2 + 2 * b3 + b4);
    }
    p->t += dt;
}

double ENR312_Plant_RotorDeg(const ENR312_Plant_t *p)
{
    return (double)p->pos / USTEP_PER_DEG;
}

double ENR312_Plant_EncoderDeg(const ENR312_Plant_t *p)
{
    double q = 360.0 / (double)ENR312_ENCODER_COUNTS_PER_REV;
    return round((p->psi / DEG2RAD + p->enc_bias) / q) * q;
}

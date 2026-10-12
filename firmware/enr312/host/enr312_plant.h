/**
 * @file    enr312_plant.h
 * @brief   HOST ONLY: nonlinear rotary-pendulum plant driven by a step train.
 *
 * Used by the host tests and the rig emulator; never linked into the target.
 * Physics: docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md eq. (6),
 *   psi'' = -wg2 sin psi + wr2 cos psi theta'' + theta'^2 sin psi cos psi - gamma psi'
 * The arm follows the commanded step rate exactly (a stepper that does not miss
 * steps). A change of step rate is a velocity step, so the pendulum receives
 * the impulse  d(psi') = wr2 cos(psi) d(theta').
 */
#ifndef ENR312_PLANT_H
#define ENR312_PLANT_H
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    double wg2, wr2, gamma;     /* plant constants                            */
    double psi, psid;           /* pendulum, rad, 0 = hanging                 */
    double v_prev;              /* last arm velocity, rad/s                   */
    double step_acc;            /* fractional microsteps                      */
    int64_t pos;                /* arm position, microsteps                   */
    double t;                   /* s                                          */
    bool held;                  /* a hand holds the pendulum still            */
} ENR312_Plant_t;

void   ENR312_Plant_Init(ENR312_Plant_t *p, double wg2, double q, double wr2);
/** Advance by dt with the arm stepping at rate_usteps (signed microsteps/s). */
void   ENR312_Plant_Step(ENR312_Plant_t *p, double rate_usteps, double dt);
double ENR312_Plant_RotorDeg(const ENR312_Plant_t *p);
/** Encoder reading in degrees, quantised to one count (0.15 deg). */
double ENR312_Plant_EncoderDeg(const ENR312_Plant_t *p);
#endif

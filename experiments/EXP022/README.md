> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP022/`.

# EXP022 (PEND): On-off control

| | |
|---|---|
| **Source** | PEND handout §2 Q7 (on-off control and its drawbacks), Q14 (on-off vs P) |
| **Status** | Firmware 2.1.0; simulation EXECUTED; **hardware NOT_EXECUTED** |
| **Run it** | `enr312_lab` → **LAB · HANGING · On-off**; `$exp=22`; compare with **T9** at K = [4 0] (P only) |

## 1. Objective and physical question
Drive the arm with bang-bang control, u = +u_on·sign(r − θ) outside a dead band and 0
inside, and compare it with proportional control. **Physical question:** why does
switching full effort on and off never settle?

## 2. Model
On the rotor θ̈ = u. With u = ±u_on the motion is a sequence of parabolas. The system
is conservative: the "energy" ½θ̇² + u_on|e| is constant between switches, so the arm
**oscillates forever between 0 and 2r**, whatever u_on is (u_on only sets the period,
which scales with √(r/u_on)). A dead band stops the switching only if the arm arrives
slowly enough, which it never does from a step. P control alone (u = −k1 e) is a
harmonic oscillator on a double integrator and also never settles. **Both need a
velocity (D) term.** That last part is specific to an acceleration-commanded
actuator. A DC motor or servo has its own velocity damping, so the handout's
Arduino P controller can settle.

## 3. Predictions (simulation, step 20°)
| | overshoot | oscillation amplitude | pendulum peak |
|---|---|---|---|
| on-off 200, dead band 0.5° | 100.8 % | ±20.2° | **35.9°** |
| on-off 200, no dead band | 100.2 % | ±20.1° | 37.0° |
| on-off 50 | 100.2 % | ±20.0° (slower) | 3.9° |
| P only, k1 = 4 (T9 with k2 0) | 100.2 % | ±19.7° (sinusoidal) | 3.1° |

On-off shakes the pendulum about 10× harder than P control for the same arm motion: every
switch is a step in acceleration, and the pendulum responds to θ̈.

## 4. Hypotheses and acceptance
* **H22-1** The arm oscillates at about ±r and never settles; the dead band does not change that.
* **H22-2** The pendulum swings far more under on-off (≥ 20°) than under P (≤ 5°).
Limits: the 120° pendulum limit can trip if u_on is raised; start at 200.
Procedure `../PROCEDURE_SUSPENDED.md`. **Measured data: none yet.**

> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP009/`.

# EXP009: Full-state feedback by pole placement (rotor, hanging)

| | |
|---|---|
| **Source** | Tutorial 9. Safety class LOW (hanging, pendulum gains 0). |
| **Status** | Firmware 2.1.0 implemented and host-tested; simulation EXECUTED; emulator e2e PASS; **hardware NOT_EXECUTED** |
| **Depends on** | EXP001 (actuator scale), EXP002 (rotor as 1/s²) |
| **Run it** | `enr312_lab` → **T9**; `$exp=9` |

## 1. Objective and physical question
Replace the PD transfer function by **state feedback** u = −Kx on the rotor state
x = [θ − r, θ̇] and place the closed-loop poles where you want them.
**Physical question:** if every state is fed back, can the poles go anywhere, and
what does the actuator say about it?

## 2. Law, units
u = −(k1(θ − r) + k2 θ̇) − b θ̇ [deg/s²]. θ̇ is the **commanded stepper rate**, exact while
no steps are missed (a stepper knows its velocity; no differentiation of an encoder is
needed). b emulates the Tutorial 9/10 rotor plant 1/(s² + bs) (0 = pure double integrator).
Sequence: 1 s idle, step 20° (15 s), back (15 s), DONE.

## 3. Model
θ̈ = u ⇒ closed loop s² + (k2 + b)s + k1. Pole placement: **k1 = ωN², k2 = 2ζωN** (b = 0).
The poles can go anywhere for a controllable plant; the price shows up as actuator
effort and, on this rig, as the limits below.

**Stepper-specific prediction (found in simulation, checked in the target code).** The
step generator rests below 2 microsteps/s (0.225 deg/s, `STEP_MIN_RATE`). Near the
target the law asks for a creep speed below that, so the arm parks short of r by up to
(k2 + b)·0.225/k1 degrees. That is a velocity dead zone, like friction.

## 4. Predictions (firmware simulation, `PEND_sim` / `EXP006-023_sim_metrics.csv`)
| Design | K | poles | overshoot | settling | final (ref 20°) |
|---|---|---|---|---|---|
| reference ωN 1, ζ 1 | [1 2] | −1, −1 | 0 % | 5.94 s (Tutorial 9: 5.8 s) | 19.80° |
| ωN 2, ζ 0.2 | [4 0.8] | −0.4 ± 1.96j | 53 % | 9.9 s | 19.97° |
| 16 % OS, 4 s | [3.94 2] | −1 ± 1.72j | 15.9 % | 4.2 s | 20.02° |

Pendulum (hanging, uncontrolled) peaks 0.45–1.65°: the faster the arm, the more it swings.

## 5. Hypotheses
* **H9-1** Rig settling and overshoot within 10 % of the simulation for each design
  (emulator: 5.92 s vs 5.94 s).
* **H9-2** The final value is short of 20° by ≤ (k2 + b)·0.225/k1 (≤ 0.45° for the reference).
* **H9-3** The ζ 0.2 design rings at ≈ 1.96 rad/s (period 3.2 s).

## 6. Acceptance, procedure, results
AC9-1 three designs run and saved; AC9-2 H9-1..3 evaluated with `odyssix.sim.metrics`.
Procedure `../PROCEDURE_SUSPENDED.md`. **Measured data: none yet.**

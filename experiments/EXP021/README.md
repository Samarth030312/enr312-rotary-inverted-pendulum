> **Pre-registration, not yet run on the rig.** Every number below is a simulation
> prediction ([`results/tables/`](../../results/tables/)), written before any hardware run.

# EXP021 (PEND): Stop a swing, then hold an angle (suspended dual PID)

| | |
|---|---|
| **Source** | PEND handout §1 task 7.1, §3 A5; the "hold the arm at a given angle" request |
| **Status** | Firmware 2.1.0; simulation EXECUTED; emulator e2e PASS (stops in 1.70 s, holds 20° to 0.008°); **hardware NOT_EXECUTED** |
| **Depends on** | EXP003 (the same suspended dual-PD law) |
| **Run it** | `enr312_lab` → **LAB · HANGING · PID** (pluck, RUN; ARM GO TO); `$exp=21`, live `$ref=deg`; Python `run_experiment.py --exp 21 --ref 20@10` |

## 1. Objective and physical question
Pluck the hanging pendulum, then let the controller stop the swing while it holds the
arm at a set-point that the student can change at any time. **Physical question:**
which gain actually removes the swing energy, and how precisely can a stepper hold an
arbitrary angle?

## 2. Law
Suspended dual PD (Tutorial 3 design 1): u = u_rotor + u_pend, rotor 6 / 4.8 (D filter
10 Hz), pendulum 10 / 5. REGULATE until Stop run. Live set-point r slewed at 90 deg/s.

## 3. Model
Free pendulum: ψ̈ + γψ̇ + ωg²ψ = ωr² θ̈. Uncontrolled, the amplitude decays as e^(−γt/2):
from 20° to 1° takes 2 ln 20/γ = **21.4 s** (γ = 0.28 s⁻¹, Q 27). Only the pendulum D term
(Kdp) adds damping directly: the arm acceleration it commands, ωr²Kdp ψ̇, opposes the
pendulum's velocity.

## 4. Predictions (simulation, 20° pluck)
| Gain set | time to stop (inside 1°) |
|---|---|
| 1: rotor 6/4.8, pendulum 10/5 | **1.58 s** |
| 2: pendulum Kd 15 | 2.65 s |
| 3: rotor only (pendulum 0/0) | 21.3 s (= free decay) |

Largest effect: **pendulum Kd**. Without it the controller cannot remove swing energy,
and too much of it is slower again (set 2). Go to 20°: reached in 2.1 s, held to
< 0.01°. The arm is a stepper, so the hold is exact to the microstep (0.1125°).

**Known rig effect (EXP003, 2026-10-12):** pivot friction left the hanging pendulum
2–4 counts (0.3–0.6°) off vertical, and the PD then holds the arm offset by
Kpp·ψ/Kp ≈ 0.5–1°. Expect that in the hold error.

## 5. Hypotheses and acceptance
* **H21-1** Gain set 1 stops a 20° swing in < 3 s; set 3 takes > 15 s.
* **H21-2** A commanded angle is held to within 1° (friction offset included).
AC21: three gain sets × 2 plucks each saved; hold at three angles (−30, 20, 45°).
Procedure `../PROCEDURE_SUSPENDED.md`. **Measured data: none yet.**

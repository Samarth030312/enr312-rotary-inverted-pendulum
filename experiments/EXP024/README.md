> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP024/`.

# EXP024 (PEND): energy control, swing-up and pendulum target

| | |
|---|---|
| **Source** | PEND handout §3 C12 (energy swing-up; why linear PID cannot), plus the request to put the pendulum at a chosen angle |
| **Status** | Firmware 2.2.0 swing-up **run on the rig 2026-10-21: caught 3 of 3** (7.1–8.0 s); firmware 2.3.0 (pendulum target, gentler catch, upright auto-trim) simulated and host-tested, **not yet on the rig** |
| **Run it** | `enr312_lab` → LAB → PENDULUM [target] SWING; `$exp=24 $amp=180`; Python `rig.configure(24, amp=90)` |

## 1. Question
How do you bring a hanging pendulum upright with an arm whose only effect is its
acceleration, and why can't a linear controller do it? Can the pendulum be put at any
angle?

## 2. First principles
Nonlinear pendulum, ψ from hanging, arm acceleration u (rad/s²):

    ψ̈ = −ωg² sin ψ + ωr² cos ψ · u − γ ψ̇

Normalised energy E = ψ̇²/(2ωg²) + 1 − cos ψ: 0 hanging still, 2 upright still.

    dE/dt = (ψ̇/ωg²)(ωr² cos ψ · u − γ ψ̇)

- The arm can change E only through **ψ̇ cos ψ**. Pushing with sign(ψ̇ cos ψ) adds
  energy fastest. Below the horizontal, cos ψ changes sign, so the same arm
  acceleration pushes the other way. A linear law with fixed gains (which assumes
  cos ψ ≈ −1, near upright) has the wrong sign over half the circle. It also has no
  notion of energy, and sin ψ ≈ ψ is wrong by 36 % at 90°. **That is why linear PID
  cannot swing up.**
- **Rest points.** At rest ψ̈ = ψ̇ = 0, so 0 = −ωg² sin ψ + ωr² cos ψ · u, which gives
  u = (ωg²/ωr²) tan ψ (arm not spinning). Holding the pendulum still at ψ would need that
  constant arm acceleration forever: impossible within the arm's travel, and infinite at 90°.
  **Only 0° and 180° are rest points.** Any other angle can be reached as a swing
  height, E* = 1 − cos a. That is what the pendulum target controls.

## 3. Law (enr312_ctrl.c)
- **amp ≥ 179 (swing-up):** u = u_on·sat(10(2 + δ − E))·sign(ψ̇ cos ψ) − (Kp θ + Kd θ̇).
  - δ is the energy the pivot friction drains on each climb. It is learnt swing by
    swing: an apex short of upright raises δ, a pass over the top too fast lowers it.
    With a fixed target E = 2 the pendulum always arrived about 30° short (simulation
    trace).
  - The catch happens at |α| ≤ 7° and |α̇| ≤ 60 deg/s with E ≥ 1.8. The 4-state LQR of
    EXP023 takes over, holds the arm where it caught for 2 s, then walks it home.
  - Upright auto-trim removes the encoder's upright offset.
- **0 < amp < 179 (pendulum target):** u = u_on·sat(5(E* + δ − E)·ψ̇ cos ψ/ωg) with
  E* = 1 − cos a. This is the Åström–Furuta law: it removes energy only above the
  target and fades out near it.
- **amp 0:** the same law with E* = 0 brakes the swing.
- `$amp` can be changed live. ωg² (`$wg2`) is taken from the free-swing measurement.

## 4. Predictions and evidence
| | Simulation (2.3.0) | Rig |
|---|---|---|
| swing-up, caught after | 5–11 s typical (9 pendulum variants; Q 12: 25 s) | **7.1 / 7.1 / 8.0 s (2.2.0)** |
| arm travel | ≤ 156° | 99–138° (2.2.0) |
| target 45 / 90 / 135° | 46.2 / 91.8 / 136.3° (mismatched plants) | — |
| stop a 40° swing | inside 4° in 9 s (free decay 19 s) | — |

Figures: `results/figures/2026-10-21_swingup_rig_vs_sim.png`, `2026-10-21_pendulum_target.png`.
Report: `results/reports/2026-10-21_rig_session.md`.

## 5. Safety and procedure
Hanging, pendulum still, then **SWING** (the app confirms). Clear the arm's sweep for a
half turn either way and keep hands away from overhead. The upright bounds apply from
the catch on (15°, 10° for 100 ms). A fall after the catch stops the motor. The 40 s
timeout ends a swing-up that never catches. Procedure: `../PROCEDURE_SUSPENDED.md`.

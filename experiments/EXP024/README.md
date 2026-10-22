> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP024/`.

# EXP024 (PEND): energy control, swing-up and pendulum target

| | |
|---|---|
| **Source** | PEND handout §3 C12 (energy swing-up; why linear PID cannot), plus the request to put the pendulum at a chosen angle |
| **Status** | Rig, 2026-10-21: firmware 2.2.0 **caught 3 of 3** (7.1–8.0 s, one fell right after the catch); 2.3.0 caught **1 of 3** (38.9 s), and the pendulum target swung to **91.8°** for a 90° target. Cause identified from the data: the firmware's ωg² (57.01, Tutorial) against the measured 48 ± 1. Firmware 2.3.2/2.3.3 with the measured ωg²: **caught 4 of 4** (3.88, 5.60, 5.80, 5.64 s); while balancing, 15 of 17 hand pushes recovered |
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
  - The catch (2.3.1) happens at |α| ≤ 7° with E ≥ 1.8 when the pendulum is either slow
    (≤ 60 deg/s) or coming towards upright from 2–7° at ≤ 100 deg/s, and only if the
    LQR's first command is within twice the arm's limit. The 4-state LQR of EXP023 then
    takes over, holds the arm where it caught for 2 s, and walks it home.
  - Why: on the rig the pendulum went over the top at 75–120 deg/s, swing after swing,
    and 2.3.0 waited for < 60 deg/s; it caught once in three tries. Every rig catch that
    held was coming towards upright, and the one that fell was moving away.
  - The fast passes came mainly from the pendulum constant. The firmware was told
    ωg² = 57.01, but the rig measures 47.6–49.5
    (`matlab/identification/identify_pendulum_20261021.m`). Too large an ωg² makes E too
    small near the bottom, so the pump overshoots.
  - In 2.3.2, δ may go down to −0.3 (`CTRL_SW_DELTA_MIN`) to take back that excess. The
    real fix is to set `$wg2` from a free swing.
  - Upright auto-trim removes the encoder's upright offset.
- **0 < amp < 179 (pendulum target):** u = u_on·sat(5(E* + δ − E)·ψ̇ cos ψ/ωg) with
  E* = 1 − cos a. This is the Åström–Furuta law: it removes energy only above the
  target and fades out near it.
- **amp 0:** the same law with E* = 0 brakes the swing.
- `$amp` can be changed live. ωg² (`$wg2`) is taken from the free-swing measurement.

## 4. Predictions and evidence
| | Simulation | Rig |
|---|---|---|
| swing-up on the identified pendulum (36 cases each) | told ωg² 57.01: 2.2.0 19, 2.3.0 8, 2.3.1 18, 2.3.2 35 caught; told the measured 48.5: 36 for every version | 2.2.0: **7.1 / 7.1 / 8.0 s**; 2.3.0: 38.9 s, no catch, stopped; **2.3.2, ωg² 48.5: 3.88 s** (simulation of the same: 4.23 s) |
| arm travel | ≤ 156° | 99–138° (2.2.0), 85–89° (2.3.0) |
| target 45 / 90 / 135° | 46.2 / 91.8 / 136.3° (mismatched plants) | 90°: **91.8°** (median of undisturbed peaks) |
| stop a 40° swing | inside 4° in 9 s (free decay 19 s) | — |

Figures: `results/figures/2026-10-21_swingup_rig_vs_sim.png`, `2026-10-21_pendulum_target.png`,
`2026-10-21b_swingup_passes_and_catches.png`, `2026-10-21b_pendulum_target_90_rig.png`.
Reports: `results/reports/2026-10-21_rig_session.md` (morning), `2026-10-21b_rig_session.md` (evening).

## 5. Safety and procedure
Hanging, pendulum still, then **SWING** (the app confirms). Clear the arm's sweep for a
half turn either way and keep hands away from overhead. The upright bounds apply from
the catch on (15°, 10° for 100 ms). A fall after the catch stops the motor. The 40 s
timeout ends a swing-up that never catches. Procedure: `../PROCEDURE_SUSPENDED.md`.

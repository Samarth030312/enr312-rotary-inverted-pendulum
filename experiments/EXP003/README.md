> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP003/`.

# EXP003 — Control of MIMO Systems: Control Effort (Suspended Mode)

| | |
|---|---|
| **Source** | Tutorial 3 |
| **Status** | Software complete; **hardware NOT_EXECUTED**; **MATLAB DEFERRED** |
| **Depends on** | EXP001, EXP002 |
| **Unlocks** | EXP004 |

## Objective

Control **two outputs with one actuator**, then design the outer rotor controller to meet
settling and overshoot limits while **minimising control effort**.

## What EXP003 adds

1. **A second loop.** A single pendulum loop can stabilise `θ` but leaves `φ` free to
   drift — a structural consequence of an unconstrained degree of freedom, not a tuning
   defect (Tutorial 3 §3).
2. **A cost.** Until now "better" meant faster and less overshoot. Tutorial 3 introduces
   control effort — the actuator amplitude, power and energy that performance is bought
   with.

## Validation against the source

Tutorial 3 publishes Design 1 (`K_P=6, T_d=0.8`). Reproducing it validates the whole
formulation at once:

| Metric | Tutorial 3 | Computed | Error |
|---|---|---|---|
| Settling (2 %) | 2.1 s | 2.095 s | −0.2 % |
| Overshoot | 31.4 % | 32.43 % | +3.3 % |
| `CE_Max` | 477 | 480 | +0.6 % |
| `CE_Max_Power` | 2.27×10⁵ | 2.304×10⁵ | +1.5 % |
| `CE_Total` | 11.0 | 10.90 | −0.9 % |

## Designs

| | `K_P` | `T_d` | `K_d` | Settling | Overshoot | `CE_Total` | Reduction |
|---|---|---|---|---|---|---|---|
| Design 1 (given) | 6.00 | 0.80 | 4.80 | 2.10 s | 32.4 % | 10.90 | — |
| **Design 2** (≤4 s) | 1.50 | 1.15 | 1.725 | 3.99 s | 26.0 % | **3.78** | **2.88×** |
| **Design 3** (<10 s) | 0.30 | 2.50 | 0.75 | 9.15 s | 24.5 % | **1.65** | **6.59×** |

Both beat Tutorial 3's targets (`< 5` and `< 2.5`).

## Two findings worth carrying forward

**1. `CE_Total` is `∫|u|dt`, not `∫u dt`.** Tutorial 3 writes the signed integral, but for
this loop `CE` has zero DC gain so the signed integral is **zero**. Only `∫|u|dt` (10.88)
reproduces the tutorial's own published 11.0. `∫u²dt` gives 1.17×10³. The conflict is
recorded, not silently corrected.

**2. `CE_Max` is not a property of the plant.** `CE(s)` is improper, so its step response
contains a Dirac delta and any finite `CE_Max` depends on the derivative realisation.
`CE_Max` scales linearly with the filter corner `N`; `CE_Total`, settling and overshoot
vary under 5 % over a 20× range of `N`. Tutorial 3's 477 corresponds to `N = 99.4 rad/s`
(dt ≈ 10 ms). **Every `CE_Max` figure here is quoted with its `N`**, and the design
conclusions rest on the metrics that are insensitive to it.

## The inner loop's real job

With the supplied gains, the inner characteristic polynomial becomes
`s² + 4.29465 s + 65.04` — `ζ = 0.266` against the open-loop `ζ = 0.0185` (`Q = 27`). The
inner loop **damps the pendulum resonance by a factor of 14**. That, not setpoint
tracking, is what it is for.

## Artifacts

| Path | What |
|---|---|
| `firmware/enr312/{inc,src}/enr312_exp003.*` | Dual-PID, single saturation on the sum, online CE metrics |
| `firmware/enr312/test/test_enr312_exp003.c` | 43 host checks incl. full MIMO closed loop |
| `scripts/exp003_mimo_control_effort.py` | Design tool — **executed** |
| `matlab/models/exp003_*.m`, `matlab/experiments/EXP003/` | **NOT_EXECUTED** |
| `results/figures/EXP003_fig{1,2}_*.png` | Figures |
| `results/tables/EXP003_design_results.csv` | Numerical results |

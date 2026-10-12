> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP004/`.

# EXP004 — MIMO Performance Analysis with Sensitivity Functions

| | |
|---|---|
| **Source** | Tutorial 4 |
| **Status** | Software complete; **hardware NOT_EXECUTED**; **MATLAB DEFERRED** |
| **Depends on** | EXP001–EXP003 · **Unlocks** EXP005 |

## Objective

Constrain **M_S** — the robustness of closed-loop behaviour to plant variation — while
minimising settling time, and meet objectives on **both** outputs.

## What EXP004 adds

1. **A second output to satisfy.** A rotor command *necessarily* displaces the pendulum;
   they share one actuator.
2. **A robustness constraint.** `S(s) = 1/(1+PC)` is literally the factor by which a
   *fractional* plant error reaches closed-loop behaviour.

## Validation

| Quantity | Tutorial 4 | Computed | Agreement |
|---|---|---|---|
| `M_S` (`K_P=6, K_d=4.8`) | 2.7 dB | **2.794 dB** | 0.094 dB |
| Nyquist identity `M_S = 1/min\|1+L\|` | asserted | verified | **1.1×10⁻¹⁶** |
| `M_S` measured on hardware (Fig. 11) | 2.4 dB | — | not reproduced, no rig |

## Designs

| | `K_P` | `K_d` | `M_S` | `ω_SC` | Rotor settle | OS | Pend. peak |
|---|---|---|---|---|---|---|---|
| Reference | 6.00 | 4.80 | 2.794 dB | 3.63 | 2.09 s | 30.7 % | 0.258 |
| **A** (<1 dB) | 1.20 | 1.50 | **0.995 dB** | 1.29 | 4.49 s | 25.7 % | **0.100** |
| **B** (<3 dB) | 0.25 | 4.80 | 1.857 dB | **4.60** | **1.89 s** | **9.0 %** | 0.237 |

## The finding Tutorial 4 does not state

Tutorial 4 has **no control-effort constraint**. Scoring its designs with EXP003's metrics:

| Design | `M_S` | `CE_Total` |
|---|---|---|
| Reference | 2.794 dB | 10.90 |
| **A** | **0.995 dB** | **3.30** |
| **B** | 1.857 dB | **10.27** |

**Design A is simultaneously the most robust and the cheapest** — that alignment is not
obvious in advance. **Design B is not**: it wins on settling and overshoot while
satisfying `M_S < 3 dB`, yet costs as much as the unconstrained reference. Its `T_d` is
19.2 s — nearly pure derivative — and since the control-effort transfer function *is* the
noise sensitivity function, it also amplifies measurement noise.

**EXP003's and EXP004's objectives are not automatically compatible.** Neither tutorial
alone reveals it.

## Firmware

**EXP004 needs almost no new firmware.** Its analysis runs offline on the step-response
data EXP003 already logs — which is what Tutorial 4's own tools do. The one addition is
`enr312_metrics.c`: a step-metric accumulator applied to **both** channels, with two
settling conventions, because the pendulum returns to zero and has no non-zero final
value to settle to.

An on-target frequency-response computation was **deliberately not added** — it would cost
flash and RAM for something the host does better.

## Artifacts

| Path | What |
|---|---|
| `firmware/enr312/{inc,src}/enr312_metrics.*` | Dual-output step metrics, 12 host checks |
| `scripts/exp004_mimo_sensitivity.py` | Design tool — **executed** |
| `matlab/models/exp004_*.m`, `matlab/experiments/EXP004/` | **NOT_EXECUTED** |
| `results/figures/EXP004_fig{1,2}_*.png` | Sensitivity+Nyquist; both outputs |
| `results/tables/EXP004_design_results.csv` | Numerical results |

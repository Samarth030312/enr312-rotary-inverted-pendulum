> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP003/`.

# EXP003 — Measurements

> ## STATUS: NO MEASURED DATA EXISTS
> No hardware attached. Every table is an **empty template**. Do not fill from simulation.

## Run record

| Field | Value |
|---|---|
| Experiment | EXP003 (Tutorial 3) |
| Date / operator | *(not executed)* |
| Source revision | |
| Parameter set | PS-EDUKIT01-v1 |
| Raw data file | *(none)* |
| EXP001 + EXP002 procedures complete? | ☐ yes ☐ no — **must be yes** |
| Configuration | ☐ suspended (required) ☐ inverted (**wrong experiment**) |
| Inner gains (must be 10 / 0 / 5) | |
| Derivative filter corner used | ______ Hz — **required for CE_Max to mean anything** |

## R2 — Single-loop rotor drift (`K_rotor = 0`)

| Field | Value |
|---|---|
| Drift observed? | ☐ yes ☐ no — **expect yes** |
| Drift rate | ______ deg/s |
| Direction | |
| Pendulum returned near zero? | ☐ yes ☐ no |

> If **no** drift, an unmodelled restoring effect exists (friction, detent torque). Record
> it — it changes the plant model.

## Designs

| | `K_P` | `T_d` | `K_d` | Predicted | **Measured** |
|---|---|---|---|---|---|
| **Design 1** | 6.00 | 0.80 | 4.80 | | |
| settling (2 %) [s] | | | | 2.10 | |
| overshoot [%] | | | | 32.4 | |
| `CE_Max` @ N=____ | | | | 480 | |
| `CE_Max_Power` | | | | 2.30e5 | |
| `CE_Total` | | | | 10.90 | |
| **Design 2** | 1.50 | 1.15 | 1.725 | | |
| settling [s] | | | | 3.99 | |
| overshoot [%] | | | | 26.0 | |
| `CE_Total` | | | | 3.78 | |
| **reduction vs D1** | | | | **2.88×** | **______×** (≥2 required) |
| **Design 3** | 0.30 | 2.50 | 0.75 | | |
| settling [s] | | | | 9.15 | |
| overshoot [%] | | | | 24.5 | |
| `CE_Total` | | | | 1.65 | |
| **reduction vs D1** | | | | **6.59×** | **______×** (≥2 required) |

## Acceptance

| Check | Limit | Design 2 | Design 3 |
|---|---|---|---|
| Settling | ≤4 s / <10 s | ☐ | ☐ |
| Overshoot | ≤30 % / <30 % | ☐ | ☐ |
| `CE_Total` reduction | ≥2× | ☐ | ☐ |

## Saturation

| Design | Saturated samples | Valid? |
|---|---|---|
| 1 / 2 / 3 | | must be 0 |

## MATLAB execution record

| Field | Value |
|---|---|
| MATLAB version / release | *(not executed)* |
| Toolboxes used | *(expected: none beyond base)* |
| Date / repository revision | |

## Metadata sidecar template

```yaml
experiment_id: EXP003
date: YYYY-MM-DD
operator: ""
source_revision: ""
parameter_set_id: PS-EDUKIT01-v1
configuration: suspended
controllers:
  pendulum: { kp: 10.0, ki: 0.0, kd: 5.0 }     # FIXED by Tutorial 3
  rotor:    { kp: 0.0, td: 0.0, kd: 0.0 }      # design under test
  deriv_lowpass_hz: 10.0
  output_limit: 800.0
excitation: { rotor_step_deg: 2.0, predicted_u_peak: 0.0 }
pendulum_parameters_status: ASSUMED_FROM_TUTORIAL_12   # OI-9, not measured on this rig
sampling: { nominal_period_s: 0.002, timing_verified: false }
execution_status: NOT_EXECUTED
```

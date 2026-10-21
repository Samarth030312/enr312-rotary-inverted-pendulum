> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP002/`.

# EXP002 — Measurements

> ## STATUS: NO MEASURED DATA EXISTS
>
> No hardware is attached (`st-info --probe` → 0 programmers). Every table below is an
> **empty template**. Any value here not marked as measured, with a date and a data file,
> is not a measurement.
>
> **Do not fill these from simulation, from the model, or from expectation.**

## Run record

| Field | Value |
|---|---|
| Experiment | EXP002 (Tutorial 2) |
| Date / time | *(not executed)* |
| Operator | |
| Source revision | *(`git rev-parse --short HEAD` at run time)* |
| Parameter set | PS-EDUKIT01-v1 |
| Raw data file | *(none — `data/raw/EXP002/` is empty)* |
| EXP001 procedure completed? | ☐ yes ☐ no — **must be yes** |
| Encoder polarity (from EXP001) | |
| Rotor polarity (from EXP001) | |
| Pendulum removed/clamped? | ☐ yes ☐ no |

## Pre-flight linearity check

| Field | Value |
|---|---|
| `K_P` | |
| `K_d` | |
| `α` (derivative filter) | |
| Reference amplitude `A` [deg] | |
| Predicted `u_peak = A(K_P + K_d α/T_s)` | |
| Output limit | |
| `u_peak` < limit? | ☐ yes ☐ no — **must be yes** |

## Q1 — Complementary sensitivity `T(s)`

| Quantity | Model | **Measured** | Error | Within tolerance? |
|---|---|---|---|---|
| final value | 1.0000 | | | |
| peak value | 1.2676 | | | |
| peak time [s] | 1.055 | | | ±10 % |
| overshoot [%] | 26.76 | | | ±5 pp |
| settling 2 % [s] | 3.239 | | | ±10 % |

**Verdict:** ☐ PASS ☐ FAIL

## Q2 — Load-disturbance sensitivity `S_D(s)`

| Quantity | Model | **Measured** | Error | Within tolerance? |
|---|---|---|---|---|
| steady-state offset | 0.2000 = 1/K_P | | | ±5 % |
| peak value | 0.2241 | | | |
| peak time [s] | 1.694 | | | |
| overshoot [%] | 12.03 | | | |
| settling to 2 % of own final [s] | 2.617 | | | |
| settles to **zero**? | **no — permanent offset** | ☐ yes ☐ no | | must be "no" |

**Verdict:** ☐ PASS ☐ FAIL

## Q3 — Plant model check (open item OI-7)

| Field | Value |
|---|---|
| `K_P` used | |
| Predicted `ω_n = √K_P` [rad/s] | |
| **Measured `ω_n`** [rad/s] | |
| Within ±10 %? | ☐ yes ☐ no |

> If this fails, the rotor plant is **not** `1/s²`. Record the observed behaviour rather
> than adjusting gains to hide it. Likely causes: friction (adds a real pole), stepper
> acceleration profiling, transport delay.

## Q6 — Linearity

| Field | Value |
|---|---|
| Saturated samples | ______ *(must be 0)* |
| Response scales with amplitude? | ☐ yes ☐ no |

## Redesign (`K_P = 6.55, K_d = 4.0`)

| Quantity | Model | **Measured** |
|---|---|---|
| `T` overshoot [%] | 18.49 | |
| `T` settling [s] | 1.961 | |
| `S_D` offset | 0.1527 | |
| `S_D` overshoot [%] | 1.96 | |
| `S_D` settling [s] | 1.412 | |

## MATLAB execution record

| Field | Value |
|---|---|
| MATLAB version / release | *(not executed)* |
| Toolboxes used | *(expected: none beyond base)* |
| Execution date | |
| Repository revision | |
| `exp002_validate_sensitivity_model` output | |

## Anomalies

| # | What happened | When | Action |
|---|---|---|---|
| | | | |

## Metadata sidecar template

Save as `data/metadata/EXP002/EXP002_<...>.yaml`:

```yaml
experiment_id: EXP002
date: YYYY-MM-DD
operator: ""
source_revision: ""
parameter_set_id: PS-EDUKIT01-v1
controller:
  kp: 0.0
  kd: 0.0
  td: 0.0
  deriv_lowpass_hz: 10.0
  output_limit: 400.0
excitation:
  reference_step_deg: 2.0
  disturbance_step: 1.0
  predicted_u_peak: 0.0
sampling:
  nominal_period_s: 0.002
  timing_verified: false      # remains false until EXP003
units:
  reference_deg: deg
  rotor_deg: deg
  error_deg: deg
  u: plant-input units
hardware_configuration:
  pendulum_removed_or_clamped: true
  encoder_polarity: 0
  rotor_polarity: 0
execution_status: NOT_EXECUTED
```

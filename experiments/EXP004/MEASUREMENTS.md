> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP004/`.

# EXP004 — Measurements

> ## STATUS: NO MEASURED DATA EXISTS
> No hardware attached. Empty templates. Do not fill from simulation.

## Run record
| Field | Value |
|---|---|
| Experiment | EXP004 (Tutorial 4) |
| Date / operator | *(not executed)* |
| Source revision / parameter set | / PS-EDUKIT01-v1 |
| Configuration | ☐ suspended (required) |
| Inner gains (must be 10/0/5) | |
| Controller realisation | ☐ ideal ☐ filtered at ____ Hz |

## Results

| | `K_P` | `K_d` | `M_S` pred. | **`M_S` meas.** | `ω_SC` pred. | **meas.** | Rotor settle pred./meas. | OS pred./meas. |
|---|---|---|---|---|---|---|---|---|
| Reference | 6.00 | 4.80 | 2.794 dB | | 3.63 | | 2.09 s / | 30.7 % / |
| Design A | 1.20 | 1.50 | 0.995 dB | | 1.29 | | 4.49 s / | 25.7 % / |
| Design B | 0.25 | 4.80 | 1.857 dB | | 4.60 | | 1.89 s / | 9.0 % / |

## Second output (Tutorial 4's added requirement)

| | Pend. peak pred. | **meas.** | Pend. settling pred. | **meas.** |
|---|---|---|---|---|
| Reference | 0.258 | | 2.60 s | |
| Design A | 0.0995 | | 2.56 s | |
| Design B | 0.237 | | 2.60 s | |

## Acceptance

| Check | Limit | Ref | A | B |
|---|---|---|---|---|
| `M_S` | — / <1 dB / <3 dB | | ☐ | ☐ |
| Overshoot | <30 % | ☐ | ☐ | ☐ |
| Both outputs settle | — | ☐ | ☐ | ☐ |

## S2 — Nyquist identity

| Design | `min\|1+L\|` meas. | `1/M_S` meas. | Agree? |
|---|---|---|---|
| Reference | | | ☐ |

## S3 — Pendulum returns to zero

| Field | Value |
|---|---|
| Steady deflection after settling? | ☐ yes ☐ **no (expected)** |
| If yes, magnitude | ______ deg |

> A steady deflection contradicts `G_pend(0) = 0`. Record it; do not tune around it.

## Observations on Design B

| Field | Value |
|---|---|
| Actuator noise audible? | ☐ yes ☐ no |
| Command signal visibly noisy? | ☐ yes ☐ no |

> Predicted: `T_d = 19.2 s` is nearly pure derivative, with control effort equal to the
> unconstrained reference and heavy noise amplification.

## MATLAB execution record
| Field | Value |
|---|---|
| Version / release / toolboxes | *(not executed)* |
| Date / repository revision | |

## Metadata sidecar
```yaml
experiment_id: EXP004
date: YYYY-MM-DD
operator: ""
source_revision: ""
parameter_set_id: PS-EDUKIT01-v1
configuration: suspended
controllers:
  pendulum: { kp: 10.0, ki: 0.0, kd: 5.0 }   # FIXED by Tutorial 4 section 7
  rotor:    { kp: 0.0, kd: 0.0 }
  realisation: ideal            # or "filtered", with corner_hz
excitation: { rotor_step_deg: 2.0 }
analysis:
  ms_db: null
  w_sc_rad_s: null
  nyquist_min_1_plus_L: null
pendulum_parameters_status: ASSUMED_FROM_TUTORIAL_12   # OI-9
execution_status: NOT_EXECUTED
```

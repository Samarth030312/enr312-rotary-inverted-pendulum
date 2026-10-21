> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP005/`.

# EXP005 — Measurements

> ## STATUS: NO MEASURED DATA EXISTS
> No hardware attached. Empty templates. Do not fill from simulation.

## Run record
| Field | Value |
|---|---|
| Experiment | EXP005 (Tutorial 5) |
| Date / operator / **second person** | *(not executed)* / / |
| Source revision / parameter set | / PS-EDUKIT01-v1 |
| Configuration | ☐ **inverted** (required) |
| **EXP003 timing verified? (OI-10)** | ☐ yes ☐ no — **must be yes** |
| Inner gains (must be 300 / 0 / **30**) | |
| Rotor sign inversion active? | ☐ yes ☐ no — **must be yes** |

## Pre-flight
| Check | Done |
|---|---|
| Dry run passed, incl. capture gate and 15° abort | ☐ |
| Swing path clear for a full rotation | ☐ |
| Power switch within reach | ☐ |

## U1 — Open-loop instability
| Field | Value |
|---|---|
| Released from upright, time to fall past 15° | ______ s (predicted ~0.4 s from 0.5°) |
| Consistent with a 137 ms time constant? | ☐ yes ☐ no |

## Balance results

| | `K_P` | `K_d` | Balanced? | Settling pred./meas. | OS pred./meas. | **Undershoot pred./meas.** |
|---|---|---|---|---|---|---|
| Stable System 1 | 9 | 9 | ☐ | 2.75 s / | 23.6 % / | **−33.2 % /** |
| Quasi-Stable System 2 | 10 | 3.33 | ☐ | 11.74 s / | 70.8 % / | −11.6 % / |
| System 1 design | 6.25 | 7.00 | ☐ | 3.25 s / | 24.8 % / | −24.2 % / |
| System 2 design | 0.50 | 10.75 | ☐ | 0.83 s / | 6.4 % / | −39.5 % / |

## U4 — Non-minimum-phase signature (**the key observation**)

| Field | Value |
|---|---|
| Did the arm move the **wrong way first**? | ☐ **yes (expected)** ☐ no |
| Undershoot magnitude | ______ % |
| Visible to the naked eye? | ☐ yes ☐ no |

> **If no reverse motion, the plant model is wrong.** Record it; do not tune around it.

## U5 — Margins

| | `φ_M` pred. | **meas.** | `GM` pred. | **meas.** | `M_S` pred. | **meas.** |
|---|---|---|---|---|---|---|
| Stable System 1 | 47.3° | | 6.01 dB | | 6.37 dB | |
| System 1 design | 50.6° | | 8.23 dB | | 4.52 dB | |

Tolerance: ±10° on `φ_M`, ±3 dB on `GM`/`M_S`.

## U6 — Quasi-Stable System 2 behaviour
| Field | Value |
|---|---|
| Balanced at all? | ☐ yes ☐ no |
| Visible ringing? | ☐ yes ☐ no |
| Lost balance? | ☐ yes ☐ no — after ______ s |
| Qualitative description | |

## U7 — The unresolved discrepancy
Tutorial 5 §13 calls System 2 *"improved performance"*; the model says the opposite.

| Field | Value |
|---|---|
| Which actually performed better, and on what measure? | |
| Any measure on which System 2 was better? | |
| Conclusion | |

## System 2 design — effort/noise caveat
| Field | Value |
|---|---|
| Actuator sounded harsh? | ☐ yes ☐ no |
| Command signal visibly noisy? | ☐ yes ☐ no |

## Aborts
| # | Reason code | Phase | Pendulum angle | What happened |
|---|---|---|---|---|
| | | | | |

## MATLAB execution record
| Field | Value |
|---|---|
| Version / release / toolboxes / date | *(not executed)* |

## Metadata sidecar
```yaml
experiment_id: EXP005
date: YYYY-MM-DD
operator: ""
second_person: ""
source_revision: ""
parameter_set_id: PS-EDUKIT01-v1
configuration: inverted
safety:
  timing_verified_oi10: false     # MUST be true before running
  capture_gate_deg: 2.0
  pendulum_abort_deg: 15.0
controllers:
  pendulum: { kp: 300.0, ki: 0.0, kd: 30.0 }   # FIXED; note Kd=30, NOT 150
  rotor:    { kp: 0.0, kd: 0.0, sign: -1 }
  deriv_lowpass_hz: 10.0
  u_limit: 1500.0
analysis: { phi_M_deg: null, GM_db: null, Ms_db: null, undershoot_pct: null }
pendulum_parameters_status: ASSUMED_FROM_TUTORIAL_5   # OI-9; inverted set differs from suspended
execution_status: NOT_EXECUTED
```

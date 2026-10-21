> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP001/`.

# EXP001 — Measurements

> ## STATUS: NO MEASURED DATA EXISTS
>
> No target hardware is attached to this machine (`st-info --probe` → 0 programmers;
> no `/dev/ttyACM*`). Every table below is an **empty template**. Any value appearing
> here that is not marked as measured, with a date and a data file, is not a measurement.
>
> **Do not fill these tables from simulation, from the reference project, or from
> expectation.**

---

## Run record

| Field | Value |
|---|---|
| Experiment ID | EXP001 |
| Date / time | *(not executed)* |
| Operator | *(not executed)* |
| Source revision | *(record `git rev-parse --short HEAD` at run time)* |
| Parameter set | PS-EDUKIT01-v1 |
| Firmware build | *(record the ELF checksum)* |
| Raw data file | *(none — `data/raw/` is empty)* |
| Toolchain | arm-none-eabi-gcc 13.2.1 |

---

## 0. Rig confirmation (procedure step 0.1)

| Item | Expected (PS-EDUKIT01-v1) | Observed | Matches? |
|---|---|---|---|
| MCU board silkscreen | NUCLEO-F401RE | | |
| Motor driver marking | L6474 on X-NUCLEO-IHM01A1 | | |
| Stepper part number | NEMA-17 17HS19-2004S | | |
| Encoder body marking | LPD3806-600BM-G5-24C | | |
| Encoder PPR from label | 600 | | |
| Supply | 12 V | | |

> **This table resolves open item OI-1.** If the rig turns out to use a DC servo motor
> rather than a stepper (as the course outline suggests), EXP001 must be re-derived —
> the actuation chain would then be torque-commanded, not position-commanded, and the arm
> would require its own encoder. That is a different experiment, not a parameter change.

## 0.2 Pin map confirmation (OI-4)

| Signal | Expected | Observed | Matches? |
|---|---|---|---|
| Encoder A | PB4 (TIM3_CH1) | | |
| Encoder B | PB5 (TIM3_CH2) | | |
| Encoder pull-up | internal, or external ____ Ω | | |
| L6474 STCK | PC7 | | |
| L6474 DIR | PA8 | | |
| L6474 RESET | PA9 | | |
| L6474 FLAG | PA10 | | |
| L6474 CS | PB6 | | |
| SPI1 SCK/MISO/MOSI | PA5 / PA6 / PA7 | | |

## 0.3 Travel limit used (OI-5)

| Field | Value |
|---|---|
| Rotor travel limit applied | ______ ° |
| Justification (cable length/routing) | |

---

## P2 — Encoder resolution

| Trial | `c_start` | `c_end` | \|Δcounts\| | Expected | Within ±4? |
|---|---|---|---|---|---|
| 1 | | | | 2400 | |
| 2 | | | | 2400 | |
| 3 | | | | 2400 | |

**Verdict:** ☐ PASS ☐ FAIL
**If Δ ≈ 600 →** timer decoding X1. **If ≈ 1200 →** X2. Correct
`ENR312_ENCODER_DECODE_X`, rebuild, repeat. **Do not** apply a scale factor downstream.

---

## P2b — Sign convention  *(this defines `s` for this rig)*

| Field | Value |
|---|---|
| Direction rotated, in unambiguous prose | e.g. "clockwise viewed from the encoder end" |
| Sign of Δcounts for that direction | ☐ + ☐ − |
| **Therefore `ENR312_ENCODER_POLARITY` =** | |
| Count monotonic throughout the rotation? | ☐ yes ☐ no |

> Write the direction in words. "+1" alone is not reproducible by another engineer.
> The reference rig used −1; that has **no authority** here.

---

## P4 — Count integrity (missed edges)

| Repetition | Residual (counts) | Residual (deg) |
|---|---|---|
| 1 | | |
| 5 | | |
| 10 | | |

**Growing with repetitions?** ☐ yes ☐ no  **Verdict:** ☐ PASS ☐ FAIL

Growth ⇒ missed edges. Repeat at slower hand speed: if the residual disappears, suspect
the pull-up (open-collector output with only the internal ~40 kΩ).

---

## P1 — Commanded vs achieved arm angle

| Commanded (°) | Commanded (microsteps) | **Measured physical (°)** | Error (°) | Within ±1.8°? |
|---|---|---|---|---|
| 0 | 0 | | | |
| +45 | +400 | | | |
| 0 | 0 | | | |
| −90 | −800 | | | |
| 0 | 0 | | | |

| Field | Value |
|---|---|
| Measuring instrument | |
| Instrument resolution | |
| Step rate used | ______ steps/s |
| Direction agrees with the commanded sign? | ☐ yes ☐ no |
| **Therefore `ENR312_ROTOR_POLARITY` =** | |

**Verdict:** ☐ PASS ☐ FAIL

> No script can fill this table. There is no arm sensor — the protractor is the only
> evidence.

---

## P3 — Step fidelity

| Field | Value |
|---|---|
| Cycles completed | ______ / 10 |
| Step rate used | ______ steps/s |
| Final commanded position (from telemetry) | ______ microsteps *(must be 0)* |
| **Physical residual at the index mark** | ______ ° |
| Within ±1.8°? | ☐ yes ☐ no |

Intermediate readings, to distinguish drift from offset:

| After cycle | Physical residual (°) |
|---|---|
| 1 | |
| 5 | |
| 10 | |

**Verdict:** ☐ PASS ☐ FAIL — **Assumption A2 (no lost steps) is ☐ supported ☐ refuted at
______ steps/s.**

| Pattern | Interpretation |
|---|---|
| Residual grows ~linearly | Steps lost each cycle |
| Fixed offset, no growth | Backlash, or origin latched during motion |
| Sign varies between runs | Marginal torque, near stall |
| Zero | A2 holds **at this rate only** |

---

## P5 — Step-rate quantisation

**STATUS: DEFERRED — requires an oscilloscope or logic analyser (not available).**

| Commanded (steps/s) | Predicted ARR | Predicted actual | **Measured** | Error (%) | Within ±0.1 %? |
|---|---|---|---|---|---|
| 200 | 409 | 200.076 | | | |
| 500 | 163 | 500.191 | | | |
| 1000 | 81 | 1000.381 | | | |
| 2000 | 40 | 2000.762 | | | |

Indicative stopwatch substitute (~1 % resolution, **not** a P5 pass):

| Move (microsteps) | Rate (steps/s) | Predicted (s) | Measured (s) | Error (%) |
|---|---|---|---|---|
| 36000 | 1000 | 35.99 | | |

---

## P6 — Velocity granularity

| Field | Value |
|---|---|
| Non-zero velocity samples with stationary pendulum | ______ *(should be 0)* |
| All non-zero values integer multiples of 1.308997 rad/s? | ☐ yes ☐ no |
| Observed σ of velocity during slow motion | ______ rad/s |
| Predicted σ (eq. 14) | 0.534 rad/s |

---

## Anomalies and deviations from procedure

| # | What happened | When | Action taken |
|---|---|---|---|
| | | | |

---

## Metadata sidecar template

Save alongside the raw file as `data/metadata/EXP001_<...>.yaml`:

```yaml
experiment_id: EXP001
date: YYYY-MM-DD
time_utc: HH:MM
operator: ""
source_revision: ""          # git rev-parse --short HEAD
parameter_set_id: PS-EDUKIT01-v1
firmware_elf_sha256: ""
raw_data_file: data/raw/EXP001_<...>.csv
sampling:
  nominal_period_s: 0.002
  nominal_rate_hz: 500
  timing_verified: false     # remains false until EXP003
units:
  rotor_cmd_microsteps: microsteps
  rotor_cmd_deg: deg
  encoder_counts: counts
  pendulum_deg: deg
  pendulum_vel_rad_s: rad/s
hardware_configuration:
  rig: STEVAL-EDUKIT01
  rig_confirmed_by_inspection: false
  encoder_pull_up: ""        # "internal" or "external <value> ohm"
  step_rate_hz: 0
  motor_current_ma: 800
  rotor_travel_limit_deg: 0
acquisition_conditions:
  ambient_temperature_c: null
  notes: ""
processing:
  script: scripts/exp001_process_measurements.py
  script_revision: ""
execution_status: NOT_EXECUTED
```

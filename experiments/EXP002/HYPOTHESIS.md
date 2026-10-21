> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP002/`.

# EXP002 — Hypotheses and Falsifiable Predictions

Every prediction is numeric, has a tolerance, and has a defined way to fail.
All hardware predictions are **UNTESTED** — no rig is attached.

---

## Q1 — Complementary sensitivity matches the model

For `K_P = 5, K_d = 2.5`, a reference step produces `T`-step metrics:
peak 1.2676, peak time 1.055 s, overshoot 26.76 %, settling 3.239 s.

- **Tolerance:** ±10 % on peak time and settling; ±5 percentage points on overshoot.
- **Falsified if:** measured overshoot ≈ 12 % (derivative kick lost — see Q5), or metrics
  differ by more than tolerance (plant is not `1/s²`, refuting B1/OI-7).
- **Status:** software-verified against the model; **hardware NOT_EXECUTED**.

## Q2 — Load-disturbance steady state equals `1/K_P`

A unit load-disturbance step leaves a permanent offset of exactly `1/K_P` (0.2000 for the
Tutorial 1 design).

- **Tolerance:** ±5 %.
- **Falsified if:** the response returns to zero (integral action present where it should
  not be), or the offset differs from `1/K_P` (disturbance injected at the wrong point, or
  the plant is not `1/s²`).
- **Diagnostic value:** this is the sharpest single check in EXP002 — it is an exact
  closed-form prediction with no tuning freedom.
- **Status:** **SOFTWARE-TESTED** (`test_closed_loop_SD_offset`, exact to 1e-4);
  hardware NOT_EXECUTED.

## Q3 — Measured `ω_n` equals `√K_P`

- **Tolerance:** ±10 %.
- **Falsified if:** it differs — which would confirm **OI-7**, that the rotor plant is not
  `1/s²`. Likely culprits: friction (adds a real pole), stepper acceleration profiling, or
  transport delay.
- **Status:** hardware NOT_EXECUTED. This is the prediction most likely to fail on the
  real rig, and its failure would be the most informative result of EXP002.

## Q4 — `S + T = 1`

- **Tolerance:** 1e-9 in the model; on hardware, within measurement noise.
- **Falsified if:** violated in the model — that would be an implementation error, since
  the identity is algebraic.
- **Status:** **SOFTWARE-TESTED** in the MATLAB validation (`S_plus_T_equals_1`).

## Q5 — Derivative kick is present

`T(s)` has a zero at `−K_P/K_d = −2 rad/s`, which raises overshoot from ~12 % (no zero) to
~27 %.

- **Falsified if:** measured overshoot ≈ 12 %, indicating the derivative contribution was
  lost — because the step landed on the controller's first sample, or the derivative acts
  on measurement instead of error.
- **Status:** **SOFTWARE-TESTED**. This was observed for real during development: an early
  test applied the step on tick 0 and measured 11.3 % instead of 26.8 %. The sequencer's
  IDLE phase prevents it.

## Q6 — The loop stays linear over the excitation

With a 2° reference step and a 400 output limit, no sample clips.

- **Falsified if:** any saturation occurs — the measured response is then of a nonlinear
  system and **is not a sensitivity function**.
- **Prediction:** peak demand `= 2 × 152.61 = 305.2 < 400`.
- **Status:** **SOFTWARE-TESTED** (`test_predict_step_demand`); the data pipeline counts
  saturated samples on every run.

---

## Status summary

| ID | Claim | Testable now? | Status |
|---|---|---|---|
| Q1 | `T(s)` matches model | model yes, rig no | SOFTWARE-TESTED / NOT_EXECUTED |
| Q2 | `S_D` offset `= 1/K_P` | model yes, rig no | SOFTWARE-TESTED / NOT_EXECUTED |
| Q3 | `ω_n = √K_P` | **rig only** | NOT_EXECUTED |
| Q4 | `S + T = 1` | **yes** | SOFTWARE-TESTED |
| Q5 | derivative kick present | **yes** | SOFTWARE-TESTED |
| Q6 | loop stays linear | **yes** | SOFTWARE-TESTED |

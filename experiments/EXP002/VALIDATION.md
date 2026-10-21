> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP002/`.

# EXP002 — Acceptance Criteria and Evidence

Categories: `IMPLEMENTED` · `COMPILED` · `SOFTWARE-TESTED` · `NUMERICALLY CHECKED` ·
`MATLAB SIMULATED` · `PHYSICALLY TESTED` · `EXPERIMENTALLY VALIDATED` · `DEFERRED`

Evaluated 2026-08-19 on the working tree at `exp001-verified` + EXP002 work.

## Summary

| | Count |
|---|---|
| Criteria satisfiable without hardware/MATLAB | 7 |
| **Of those, satisfied** | **7** |
| Criteria requiring the rig | 4 |
| Criteria requiring MATLAB | 1 |
| **Fabricated or assumed results** | **0** |

---

## AC2-1 — PD controller implements `C(s) = K_P + K_d·s` — **SATISFIED**

`firmware/enr312/src/enr312_pd.c`. Discrete backward-difference derivative with a
first-order low-pass, `a = 1 − exp(−2π f_c T_s)`. At 10 Hz / 2 ms, `a = 0.11808862`,
asserted to 1e-8. Noise gain `√(a/(2−a)) = 0.2506`, reproducing the EXP001 figure.

Derivative acts on **error**, preserving `T(s)`'s zero at `−K_P/K_d`. This is required:
derivative-on-measurement would change `T(s)` and invalidate the comparison.

## AC2-2 — Injection points correct — **SATISFIED**

Unit-tested individually (`test_enr312_pd.c`):
- `D` at the **plant input**: does not appear in the error, does not pass through `C`,
  appears in `U`.
- `N` at the **sensor**: produces an error even when `R = Y = 0`.

Getting either wrong yields a plausible measurement of the wrong quantity, so each is
asserted separately rather than jointly.

## AC2-3 — Firmware reproduces the analytic closed loop — **SATISFIED**

`test_closed_loop_T_matches_model` closes the loop around a discrete `1/s²` model
(exact ZOH for a double integrator) and compares against
`scripts/exp002_sensitivity_design.py`:

| Quantity | Analytic | Firmware | Tolerance |
|---|---|---|---|
| `T` peak | 1.2676 | within 0.02 | ±0.02 |
| `T` peak time | 1.055 s | within 0.05 | ±0.05 s |
| `T` overshoot | 26.76 % | within 2.0 | ±2 pp |
| `T` settling | 3.239 s | within 0.30 | ±0.30 s |

Tolerances admit the deliberate 10 Hz derivative filter, which the ideal `C(s)` lacks.

## AC2-4 — `S_D` steady state `= 1/K_P` exactly — **SATISFIED**

`test_closed_loop_SD_offset`: settles to 0.2000 within 1e-4 for `K_P = 5`. The test also
asserts the converse — that measured against **zero** the response never settles, checked
over the final 100 samples. Both conventions are pinned so neither can drift.

## AC2-5 — Sequencer and abort paths — **SATISFIED**

`test_enr312_exp002.c`, 27 checks:
- Six-phase order verified explicitly.
- **`R` and `D` never simultaneously non-zero** — the structural property without which
  `T` and `S_D` cannot be separated from one record.
- Dry run completes and commands zero motion.
- Saturation abort, rotor-limit abort, operator abort (sticky, zeroes output), and abort
  active while disarmed — every path executed here rather than first on hardware.
- CSV field count matches the header.

## AC2-6 — Target cross-compilation — **SATISFIED**

`make arm` under `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion
-Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wdouble-promotion`.
**Zero warnings.**

| | EXP001 | EXP002 | Δ |
|---|---|---|---|
| text | 2 086 B | 3 763 B | **+1 677 B** |
| data | 0 B | 0 B | 0 |
| bss | 0 B | 0 B | **0** |

Static RAM remains zero: all state is caller-owned.

## AC2-7 — Design meeting all six objectives — **SATISFIED**

`scripts/exp002_sensitivity_design.py`, executed. 3595 feasible designs found.
Tutorial 1's own gains already satisfy all six. Selected design
`K_P = 6.55, T_d = 0.611, K_d = 4.00`. `K_d` lies on the admissible boundary, so the
constraint is active and the design is limited by the tutorial's bound, not the physics.

## AC2-8 — Linearity guard — **SATISFIED**

`ENR312_PD_PredictStepDemand` returns `A·(K_P + K_d·α/T_s)`. Tested: 152.61 per degree;
the 2° default gives 305.2 inside the 400 limit; a 10° step gives 1526 and would clip.
The data pipeline counts saturated samples on every run.

**This was a real finding, not a precaution.** The first self-test used a 10° step and a
50 limit, clipped, and measured 11.3 % overshoot instead of 26.8 % — the clipped loop is
nonlinear and its "sensitivity function" was not one.

## AC2-9 — MATLAB — **DEFERRED — MATLAB EXECUTION ENVIRONMENT REQUIRED**

`which matlab` → not found. `which octave` → not found.

Delivered: `matlab/models/exp002_sensitivity_model.m`, `exp002_step_response.m`,
`matlab/validation/exp002_validate_sensitivity_model.m` (15 self-checking assertions with
stated expected values), `matlab/experiments/EXP002/exp002_run_analysis.m`,
`matlab/plotting/exp002_plot_sensitivity.m`, `matlab/ENVIRONMENT.md`.

**Toolbox-free by construction** — step responses come from a closed-form pole/residue
expansion, so Control System Toolbox is not required. **Never executed.**

## AC2-10…AC2-13 — Hardware — **NOT_EXECUTED — BLOCKED**

`st-info --probe` → 0 programmers. No serial devices.

Blocked: Q1 (measured `T`), Q2 (measured `S_D` offset), Q3 (measured `ω_n`, which would
resolve OI-7), and the redesign verification.

**No measured value is claimed anywhere in EXP002.**

---

## Open items

| ID | Item | Blocks | Resolution |
|---|---|---|---|
| OI-2 | Sign conventions undetermined | **All EXP002 hardware** | EXP001 P1/P2b |
| OI-3 | No board-support layer | Hardware execution | Write against the rig |
| OI-7 | Plant `1/s²` unverified | Q1, Q3 | Measure `ω_n` |
| OI-8 | Selected design's 2° step demands 485 > 400 limit | Step 5 of procedure | Reduce `A` to 1.5°, or raise the limit deliberately and record it |

---

## Gate decision

**EXP002 is complete to the limit this environment permits. It is not complete as an
experiment.**

**EXP003 must not begin.** Tutorial 3 adds the pendulum plant and a second loop, and its
design starts from EXP002's *measured* sensitivity results. Beginning it would mean
building a MIMO controller on an unverified plant model (OI-7) with unverified sign
conventions (OI-2).

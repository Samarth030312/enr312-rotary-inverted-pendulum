> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP002/`.

# EXP002 — Performance Analysis by Sensitivity Function Measurement

| | |
|---|---|
| **Source** | Tutorial 2 |
| **Status** | Software complete; **hardware NOT_EXECUTED**; **MATLAB DEFERRED** |
| **Depends on** | EXP001 (Tutorial 1) |
| **Unlocks** | EXP003 (Tutorial 3) — **gated, do not begin** |
| **Parameter set** | `PS-EDUKIT01-v1` |

## Objective

Measure and design against **both** reference tracking and load-disturbance rejection for
the rotor loop, and show that a controller good at one is not automatically good at the
other.

## Physical question

*With the loop closed, how well does the rotor follow a command — and how well does it
reject a load it cannot see?*

## Scope

Rotor loop only: `P(s) = 1/s²`, `C(s) = K_P + K_d·s`. The pendulum plant, the second loop
and the MIMO structure are **EXP003** and appear nowhere here.

## Documents

| File | Contents |
|---|---|
| `FIRST_PRINCIPLES.md` | Signal topology, the four transfer functions, units, conventions, error sources |
| `HYPOTHESIS.md` | Predictions Q1–Q6 with tolerances and failure conditions |
| `PROCEDURE.md` | Hardware procedure, safety, abort criteria |
| `VALIDATION.md` | Acceptance criteria with per-criterion evidence |
| `MEASUREMENTS.md` | Data template — **empty, no data exists** |
| `CONCLUSION.md` | What is concluded now; what remains open |

## Key results (model + independent numerical check, **not** measured)

| | `T(s)` tracking | `S_D(s)` disturbance |
|---|---|---|
| **Tutorial 1 design** `K_P=5, K_d=2.5` | OS 26.76 %, settle 3.239 s | offset 0.2000, OS 12.03 %, settle 2.617 s |
| **EXP002 selected** `K_P=6.55, K_d=4.0` | OS 18.49 %, settle 1.961 s | offset 0.1527, OS 1.96 %, settle 1.412 s |

Both meet all six Tutorial 2 objectives. 3595 feasible designs exist; `K_d = 4.0` sits on
the admissible boundary, so the constraint is active.

## The two things to take away

**1. `S_D` never settles to zero.** It holds a permanent offset of `1/K_P`. A PD
controller has no integral action, so finite DC loop gain leaves a constant error under a
constant load. No choice of gains removes it — larger `K_P` only shrinks it. This is
Tutorial 2's "extended settling time" and it is the reason integral action exists
(Tutorial 6).

**2. Derivative-on-error makes a step expensive.** Peak demand is
`A·(K_P + K_d·α/T_s) ≈ 152·A` — about 30× the proportional term. A 10° step demands 1525
and clips any sane limit, and **a clipped loop is nonlinear, so its measured "sensitivity
function" is not one.** The excitation amplitude and the output limit must be chosen
together; `ENR312_PD_PredictStepDemand()` exists to check this before a run, not after.

## Artifacts

| Path | What |
|---|---|
| `firmware/enr312/{inc,src}/enr312_pd.*` | Discrete PD, filtered derivative, saturation |
| `firmware/enr312/{inc,src}/enr312_exp002.*` | Sensitivity sequencer, R/D/N injection |
| `firmware/enr312/test/test_enr312_{pd,exp002}.c` | 66 host checks |
| `scripts/exp002_sensitivity_design.py` | Design tool — **executed** |
| `scripts/exp002_process_measurements.py` | Data pipeline — self-tested on synthetic input |
| `matlab/models/exp002_*.m`, `matlab/validation/`, `matlab/experiments/EXP002/` | **NOT_EXECUTED** |
| `results/figures/EXP002_fig{1,2}_*.png` | Generated figures |
| `results/tables/EXP002_design_results.csv` | Numerical results |

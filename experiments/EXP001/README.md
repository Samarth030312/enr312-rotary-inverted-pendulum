> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP001/`.

# EXP001 — Actuator and Angle Sensing

| | |
|---|---|
| **Experiment ID** | EXP001 |
| **Status** | Software complete; **hardware NOT_EXECUTED** |
| **Rig** | STEVAL-EDUKIT01 (NUCLEO-F401RE + X-NUCLEO-IHM01A1 + NEMA17 + 600 PPR encoder) |
| **Parameter set** | `PS-EDUKIT01-v1` |
| **Source revision** | 44bda39 |
| **Prerequisites** | none — EXP001 is the root of the chain |
| **Unlocks** | EXP002 |

---

## Objective

Establish the two chains that every later experiment assumes are correct:

1. **Actuation** — how a software command becomes physical arm motion, and with what
   scale, sign, and fidelity.
2. **Sensing** — how physical pendulum motion becomes a number, and with what scale,
   sign, origin, resolution and noise.

## Physical question

*When the software says "move 45 degrees", does the arm move 45 degrees — and when the
pendulum moves, does the reported angle mean what we think it means?*

## Why this is first

A sign error, a factor-of-four resolution error, or silent step loss does not announce
itself. It propagates into the model, the identified parameters, and the controller
gains, and then presents as a physics problem that is not a physics problem. EXP001
exists so that every later discrepancy can be attributed to dynamics rather than to
plumbing.

## Scope

| | |
|---|---|
| Firmware | yes — sensing/actuation core + experiment sequencer |
| Numerical analysis | yes — executed |
| MATLAB simulation | **DEFERRED** — no MATLAB on this machine |
| Hardware | **BLOCKED** — no target attached |
| Dynamics / plant model | **explicitly out of scope** |

## Documents

| File | Contents |
|---|---|
| `FIRST_PRINCIPLES.md` | Full derivation of both chains, equations (1)–(14) |
| `HYPOTHESIS.md` | Predictions P1–P6, H4, each with a tolerance and a failure condition |
| `PROCEDURE.md` | Step-by-step hardware procedure, safety, abort criteria |
| `VALIDATION.md` | Acceptance criteria AC-1…AC-12 with per-criterion evidence |
| `MEASUREMENTS.md` | Data-recording template — **empty, no data exists** |
| `CONCLUSION.md` | What is concluded now; what remains open |

## Artifacts

| Path | What it is |
|---|---|
| `firmware/enr312/` | EXP001 sensing/actuation core, sequencer, and host tests |
| `shared/parameters/edukit01_rig.yaml` | Parameter set with per-value provenance |
| `shared/experiment_contracts/EXP001.yaml` | Machine-readable contract |
| `scripts/exp001_sensing_analysis.py` | Numerical analysis + figures (executed) |
| `scripts/exp001_process_measurements.py` | Measured-data pipeline (self-tested only) |
| `matlab/experiments/exp001_*.m` | MATLAB sources — **NOT_EXECUTED** |
| `results/figures/EXP001_fig1..4_*.png` | Generated figures |
| `results/tables/EXP001_sensing_analysis.csv` | Numerical results |

## Key numbers established analytically

| Quantity | Value |
|---|---|
| Encoder resolution | 2400 counts/rev = 0.150 °/count = 2.618 mrad/count |
| Angle quantisation noise | σ = 0.0433° = 7.56×10⁻⁴ rad |
| Arm command increment | 3200 microsteps/rev = 0.1125 °/microstep |
| Velocity granularity at 500 Hz | 1.309 rad/s = 75 °/s per count |
| Velocity noise, unfiltered | σ = 0.534 rad/s = 30.6 °/s |
| Velocity noise, 10 Hz filtered | σ = 0.136 rad/s |
| Counter-wrap aliasing threshold | 6827 rev/s — unreachable by five orders of magnitude |

## The one thing to take away

The encoder is on the pendulum, not the arm, because a stepper's position is *commanded
and remembered* rather than measured. That makes the arm's position exactly as
trustworthy as the assumption that no step is ever lost — an assumption with no error
signal behind it. Prediction P3 is the only check in the system, which is why it is not
optional.

> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP002/`.

# EXP002 — Conclusion

**Date:** 2026-08-19 · **Source:** Tutorial 2 · **Parameter set:** PS-EDUKIT01-v1

## Verdict

**Complete to the limit of this environment; not complete as an experiment.** The
sensitivity functions are derived, implemented, and verified *as software* against an
independent numerical model. Nothing has been measured — no hardware is attached and
MATLAB is absent.

## What is established

**As fact (software):**

1. The controller implements `C(s) = K_P + K_d·s` with correct signal topology, verified
   injection points, and a derivative filter whose corner is *derived* from EXP001's noise
   measurements rather than inherited.
2. The closed-loop firmware reproduces the analytic `T(s)` and `S_D(s)` — 66 EXP002 checks
   pass, 185 across the whole core, zero warnings, and the EXP002 core adds **0 bytes of
   static RAM**.
3. Tutorial 1's gains already satisfy all six of Tutorial 2's objectives; 3595 feasible
   designs exist; the disturbance-optimal one sits on the `K_d ≤ 4` boundary.

**As prediction only:** every metric above. The plant model `1/s²` is unverified on this
rig (OI-7), and both sign conventions remain undetermined (OI-2).

## The two results worth carrying forward

**1. A PD controller cannot reject a constant load.**
`S_D(0) = 1/K_P ≠ 0`, so a constant disturbance leaves a permanent offset. Measured
against its own final value it settles in 2.6 s; measured against **zero** — which is what
rejection means — it never settles at all. This resolves Tutorial 2's warning about
"extended settling time": the warning is about the second convention. No choice of gains
fixes it, because finite DC loop gain is structural. This is exactly why Tutorial 6
introduces integral action, and EXP002 now has the reason rather than the assertion.

**2. Derivative-on-error makes a reference step expensive, and clipping silently destroys
the measurement.**
Peak demand is `A·(K_P + K_d·α/T_s) ≈ 152·A` — around 30× the proportional term. A 10°
step demands 1525. If that clips, the loop is nonlinear and **the measured "sensitivity
function" is not a sensitivity function** — it just looks like one. This was discovered by
the self-test producing 11.3 % overshoot instead of 26.8 %. The excitation amplitude and
the output limit must therefore be chosen together, and
`ENR312_PD_PredictStepDemand()` exists so that check happens before a run.

## Failures found and fixed

| # | Defect | Consequence | Fix |
|---|---|---|---|
| 1 | Saturation abort fired on legitimate dry runs | Dry runs — the safest way to validate before power — always aborted, making them useless | Abort only when armed; detect clipping by comparing `u` against `u_unsat` rather than re-testing a threshold against an exponentially decaying tail |
| 2 | Test applied the step on tick 0 | Derivative kick suppressed; overshoot 11.3 % vs 26.8 %; would have been read as a model error | Warm up before stepping, matching the sequencer's IDLE phase |
| 3 | Default 10° step with a 50 limit | Clipped; nonlinear; invalid measurement | Predictor added; defaults set to 2° / 400 from the derivation |
| 4 | Expected `α` constant wrong in the test | Test wrong, firmware right | Corrected to 0.11808862 |
| 5 | Design tool grid search infeasibly slow | 15 000 numerical step responses; timed out at 6 min | Replaced with an exact closed-form pole/residue expansion — ~4 orders of magnitude faster **and** exact |

Defect 1 is the instructive one: a safety mechanism that fires on correct behaviour is not
a safety mechanism, it is an obstacle, and it would have trained the operator to ignore it.

## What EXP002 has *not* shown

Nothing measured. No confirmation that the rotor plant is `1/s²` — the single most likely
prediction to fail on real hardware, and the most informative if it does. No timing
verification (EXP003). No pendulum dynamics whatsoever.

## Open items

| ID | Item | Blocks |
|---|---|---|
| OI-2 | Sign conventions undetermined | all EXP002 hardware |
| OI-3 | No board-support layer | hardware execution |
| OI-7 | Plant `1/s²` unverified | Q1, Q3 |
| OI-8 | Selected design's 2° step demands 485 > 400 limit | procedure step 5 |

## Gate

**EXP003 must not begin.** Tutorial 3 adds the pendulum plant and a second control loop,
starting from EXP002's *measured* results. Building a MIMO controller on an unverified
plant model with unverified signs would repeat, at greater cost, exactly the mistake this
sequence is designed to prevent.

## Reproducibility

```bash
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"
cd firmware/enr312 && make test && make arm && cd ../..
python3 scripts/exp002_sensitivity_design.py
python3 scripts/exp002_process_measurements.py --selftest
```

## Next step

The smallest justified next action is **EXP001's hardware procedure step 0.1** — inspect
the rig and record part numbers. It resolves OI-1, which gates OI-2, OI-3 and OI-7, and
therefore gates every measurement in EXP002.

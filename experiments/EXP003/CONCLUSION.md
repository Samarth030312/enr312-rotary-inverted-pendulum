> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP003/`.

# EXP003 — Conclusion

**Date:** 2026-08-19 · **Source:** Tutorial 3 · **Parameter set:** PS-EDUKIT01-v1

## Verdict

**Complete to the limit of this environment; not complete as an experiment.** The MIMO
structure and control-effort machinery are derived, implemented and validated against
Tutorial 3's own published numbers. Nothing has been measured.

## What is established

**As fact (software):**

1. The formulation reproduces Tutorial 3's Design 1 across **all five** published metrics
   within 3.3 %. That single result validates the plants, both controllers, the loop
   algebra and the control-effort definitions together.
2. `CE_Total` is `∫|u|dt`. The source's written formula (`∫u dτ`) gives exactly zero.
3. `CE_Max` is realisation-dependent and must always be quoted with its derivative-filter
   corner; `CE_Total`, settling and overshoot are not.
4. Designs meeting Tutorial 3's Step 2 and Step 4 targets exist and were found:
   2.88× and 6.59× effort reduction respectively.
5. 43 EXP003 host checks pass (271 across the core), zero warnings.

**As prediction only:** every metric above, and critically the pendulum parameters
themselves.

## The three results worth carrying forward

**1. The inner loop exists to damp, not to track.** With the supplied gains the inner
characteristic polynomial becomes `s² + 4.29465s + 65.04` — `ζ = 0.266` against an
open-loop `ζ = 0.0185`. A factor of **14** in damping. Tutorial 3 supplies these gains
without explaining why they work; this is why.

**2. Performance is bought, and the exchange rate is steep.** Going from Design 1 to
Design 3 costs a 4.4× increase in settling time and buys a 6.6× reduction in `CE_Total`
and a **6.4× reduction in peak amplitude**. For the surgical-robot motivation Tutorial 3
gives, that is the whole design question.

**3. A metric that depends on your solver is not a metric.** `CE(s)` is improper. Half the
"control effort" numbers one could report scale linearly with an arbitrary filter corner.
Recognising which metrics are realisation-independent — and resting the conclusions on
those — is the difference between a result and an artefact.

## What EXP003 has *not* shown

Nothing measured. The rotor drift that motivates the entire experiment (R2) has never been
observed on this rig. And the pendulum parameters are **not this rig's** (OI-9).

## Failures found and fixed

| # | Defect | Consequence | Fix |
|---|---|---|---|
| 1 | Test probed the run's final sample for tracking | That sample is in the SETTLE phase after the reference returns to zero, so it measured the return-to-zero and reported "rotor does not track" on a correctly tracking system | Capture the end of the excitation phase explicitly |
| 2 | Design sweep simulated every grid point at full resolution | Ran >15 min and had to be killed twice | Coarse sweep at dt = 10 ms plus local refinement; documented resolution |
| 3 | `pkill -f` pattern matched the shell running it | Killed my own session twice (exit 144) | Terminate by PID |

## Open items

| ID | Item | Blocks |
|---|---|---|
| OI-2 | Sign conventions undetermined | all hardware |
| OI-3 | No board-support layer | hardware execution |
| OI-7 | Rotor plant unverified | R1 |
| **OI-9** | **Pendulum parameters are another rig's** | every pendulum prediction |

## Gate

**EXP004 may begin.** Its input is the MIMO structure EXP003 establishes, which is
complete in software.

## Reproducibility

```bash
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"
cd firmware/enr312 && make test && make arm && cd ../..
python3 scripts/exp003_mimo_control_effort.py      # ~3 min
```

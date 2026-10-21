> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP004/`.

# EXP004 — Conclusion

**Date:** 2026-08-19 · **Source:** Tutorial 4

## Verdict
**Complete to the limit of this environment; not complete as an experiment.** Nothing
measured.

## What is established

1. `M_S` = 2.794 dB for the reference design against Tutorial 4's published 2.7 dB.
2. The Nyquist identity `M_S = 1/min|1+L|` verified to **1.1×10⁻¹⁶** by two independent
   computational routes.
3. Designs meeting Step 1 (`M_S` < 1 dB) and Step 2 (`M_S` < 3 dB) found.
4. Both outputs instrumented with the correct — and different — settling conventions.
5. 12 new host checks; **252 across the core**; zero warnings.

## The three results worth carrying forward

**1. `S` is not "the disturbance transfer function". It is a transmission ratio.**
Tutorial 4 derives it from `[δT/T]/[δP/P]`, which makes `|S| = 0.5` mean something
concrete: a 10 % plant error produces a 5 % behaviour change. Every robustness claim in
this laboratory rests on that reading, and it is worth stating in those terms rather than
as a formula.

**2. `M_S` and the stability margin are the same fact.** `1/S = 1 + L` is the vector from
`−1` to the Nyquist curve, so `M_S` is the reciprocal of its closest approach. A design
with large `M_S` is a design that passes close to `−1`. Verifying this numerically rather
than quoting it turned an identity into a check on the implementation.

**3. Satisfying one tutorial's objective can violate another's.** Tutorial 4 imposes no
control-effort constraint, and its `M_S < 3 dB` optimum (Design B) costs as much as the
unconstrained reference — 10.27 against 10.90 — because it is nearly a pure derivative
controller (`T_d = 19.2 s`). Since the control-effort transfer function *is* the noise
sensitivity function, it also amplifies measurement noise. **Design A, by contrast, is
both the most robust and the cheapest.** Neither tutorial alone shows this; it emerges
only from carrying EXP003's metrics into EXP004.

## What EXP004 has *not* shown
Nothing measured. And `M_S` inherits `G_pend`, so **OI-9 propagates into every robustness
number here**.

## Engineering decisions recorded

- **No derivative filter for frequency-domain metrics.** Evidenced against the source
  (2.794 vs 2.7 dB ideal; 3.121 dB filtered). A deliberate, documented difference from
  EXP003, whose `CE_Max` genuinely needs a realisation.
- **No on-target frequency-response computation.** Tutorial 4's own tools work offline on
  step-response data; adding an on-target FFT would cost flash and RAM for something the
  host does better.
- **No new control structure.** EXP004 reuses EXP003's dual PID unchanged. The only
  firmware addition is the dual-output metrics accumulator, which Tutorial 4's
  both-outputs requirement genuinely needs.

## Gate
**EXP005 may begin.**

## Reproducibility
```bash
cd firmware/enr312 && make test && make arm && cd ../..
python3 scripts/exp004_mimo_sensitivity.py     # ~4 min
```

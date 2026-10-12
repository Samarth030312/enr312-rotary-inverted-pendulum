> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP004/`.

# EXP004 — Acceptance Criteria and Evidence

| | Count |
|---|---|
| Satisfiable without hardware/MATLAB | 7 |
| **Satisfied** | **7** |
| Requiring the rig | 4 |
| Requiring MATLAB | 1 |
| **Fabricated or assumed results** | **0** |

## AC4-1 — Reproduces Tutorial 4's `M_S` — **SATISFIED**
2.794 dB computed against 2.7 dB published: **0.094 dB**. Achieved with the *ideal*
controller; `N=100` gives 3.121 dB and `N=50` gives 3.457 dB, both further from the
source — evidence that the tutorial computes `M_S` without a derivative realisation, as
a frequency-domain metric of a proper transfer function should be.

## AC4-2 — Nyquist identity verified — **SATISFIED**
`min|1+L| = 0.724935` against `1/M_S = 0.724935`, residual **1.1×10⁻¹⁶**. Computed by
two independent routes (magnitude of `S` over frequency; distance from `−1` to `L`), so
agreement is meaningful rather than tautological.

## AC4-3 — Sensitivity derived, not asserted — **SATISFIED**
`FIRST_PRINCIPLES.md` §2 carries Tutorial 4's derivation from the fractional-change
definition through `dT/dP = C/(1+PC)²` to `S = 1/(1+PC)`, establishing *why* `S` is the
right object: it is the transmission factor from fractional plant error to fractional
behaviour change.

## AC4-4 — Both outputs measured, with correct conventions — **SATISFIED**
`enr312_metrics.c`, 12 host checks. Two settling conventions:
`ENR312_SETTLE_TO_FINAL` (rotor, band about a non-zero final value) and
`ENR312_SETTLE_TO_ZERO` (pendulum, band about zero scaled to its own peak). Applying the
rotor convention to the pendulum would divide by a final value of ~0; the guard is
tested, as are NaN rejection and the zero-final-value case.

## AC4-5 — Designs meeting Steps 1 and 2 — **SATISFIED**
Design A: `M_S` 0.995 dB < 1 dB, overshoot 25.65 %, settling 4.492 s.
Design B: `M_S` 1.857 dB < 3 dB, overshoot 9.00 %, settling 1.887 s.

## AC4-6 — Target cross-compilation — **SATISFIED**
Zero warnings under the strict set.

## AC4-7 — Control-effort cost of the `M_S`-optimal designs quantified — **SATISFIED**
Not required by Tutorial 4, but the omission is the point: scoring EXP004's designs with
EXP003's metrics shows Design A is both most robust *and* cheapest (`CE_Total` 3.30) while
Design B matches the unconstrained reference's cost (10.27 vs 10.90). **EXP003's and
EXP004's objectives are not automatically compatible.**

## AC4-8 — MATLAB — **DEFERRED — MATLAB EXECUTION ENVIRONMENT REQUIRED**
Artifacts written, toolbox-free, never executed.

## AC4-9…AC4-12 — Hardware — **NOT_EXECUTED — BLOCKED**
S1 (measured `M_S`), S2 (measured Nyquist closest approach), S3 (pendulum returns to
zero), S6 (both outputs settle). **No measured value is claimed.**

## Limitations

1. **OI-9 still dominates.** `M_S` depends on `T_rotor`, which depends on `G_pend` —
   whose `ω_r², ω_g², Q` are another rig's values.
2. **Design A's margin is tight.** Predicted `M_S = 0.995 dB` against a 1 dB limit: a
   0.5 % model error breaches it. Recorded so a measured 1.05 dB is read as a tight
   design rather than a failure.
3. **`M_S` is not perfectly realisation-independent** — it moves ~0.3 dB between the
   ideal and `N=100` controllers. Far weaker than `CE_Max`'s linear scaling, but not zero.
4. **Search grid** 0.05 in both gains over Tutorial 4's stated range; a finer grid could
   shift the optimum slightly.

## Gate
**EXP005 may begin.** The MIMO structure, sensitivity machinery and both-output metrics
EXP005 needs are complete in software.

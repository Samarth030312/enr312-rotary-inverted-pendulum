> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP003/`.

# EXP003 — Hypotheses and Falsifiable Predictions

All hardware predictions are **UNTESTED** — no rig is attached.

## R1 — Design 1 reproduces the published metrics
Settling 2.1 s, overshoot 31.4 %, `CE_Max` 477, `CE_Max_Power` 2.27×10⁵, `CE_Total` 11.0.
- **Tolerance:** ±20 % on hardware (Tutorial 3 explicitly permits simulation/measurement
  disagreement).
- **Falsified if:** metrics differ by more than that, implicating `G_pend` (OI-9) or
  `G_rotor` (OI-7).
- **Status:** **NUMERICALLY CHECKED** — all five within 3.3 %. Hardware NOT_EXECUTED.

## R2 — Single-loop control leaves rotor angle drifting
With `K_rotor = 0` and only the pendulum loop active, a pendulum disturbance produces
**unbounded rotor drift** (Tutorial 3 Figure 3).
- **Falsified if:** the rotor returns to a fixed angle unaided — which would mean an
  unmodelled restoring effect (friction, detent torque).
- **Status:** hardware NOT_EXECUTED. This is the experiment that *motivates* the second
  loop, and it is worth running first.

## R3 — Performance costs effort, monotonically
Reducing `K_P-Rotor` reduces `CE_Max` and `CE_Total` and increases settling time.
- **Falsified if:** a design is found that is both faster and cheaper — which would mean
  the search or the metric is wrong.
- **Status:** **SOFTWARE-TESTED** (`test_lower_gain_costs_less_effort`) and confirmed by
  the design sweep.

## R4 — `CE_Total` reduction of at least 2× is achievable and measurable
Design 2 predicts 2.88×, Design 3 predicts 6.59×.
- **Tolerance:** Tutorial 3 requires the **factor** to be observed even if absolute values
  disagree.
- **Status:** **NUMERICALLY CHECKED**; hardware NOT_EXECUTED.

## R5 — Inner loop damps the pendulum resonance
Closed inner loop gives `ζ = 0.266` versus open-loop `ζ = 0.0185`.
- **Falsified if:** measured ring-down is not visibly faster with the loop closed.
- **Status:** analytic; hardware NOT_EXECUTED.

## R6 — `CE_Max` scales with the derivative realisation
Doubling the filter corner `N` doubles `CE_Max`, while `CE_Total`, settling and overshoot
change by under 5 %.
- **Status:** **NUMERICALLY CHECKED** across `N` ∈ [25, 1600].

| ID | Testable now? | Status |
|---|---|---|
| R1 | model yes, rig no | NUMERICALLY CHECKED / NOT_EXECUTED |
| R2 | **rig only** | NOT_EXECUTED |
| R3 | **yes** | SOFTWARE-TESTED |
| R4 | model yes, rig no | NUMERICALLY CHECKED / NOT_EXECUTED |
| R5 | analytic | analytic only |
| R6 | **yes** | NUMERICALLY CHECKED |

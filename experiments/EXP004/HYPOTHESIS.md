> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP004/`.

# EXP004 — Hypotheses and Falsifiable Predictions

## S1 — `M_S` for the reference design is ≈2.7 dB
- **Tolerance:** ±0.5 dB on hardware (Tutorial 4's own sim-vs-measurement gap is 0.3 dB).
- **Falsified if:** measured `M_S` differs by more — implicating `T_rotor`, hence `G_pend`
  (OI-9) or `G_rotor` (OI-7).
- **Status:** **NUMERICALLY CHECKED** (2.794 dB, 0.094 dB from the published value).
  Hardware NOT_EXECUTED.

## S2 — `M_S = 1/min|1+L|`
- **Falsified if:** the two differ by more than numerical noise — an algebraic identity,
  so any disagreement is an implementation error.
- **Status:** **NUMERICALLY CHECKED** to 1.1×10⁻¹⁶.

## S3 — A rotor step displaces the pendulum, which then returns to zero
Predicted peak 0.258 per unit rotor step for the reference design.
- **Falsified if:** the pendulum holds a steady non-zero deflection — which would mean
  `G_pend(0) ≠ 0`, contradicting the `s²` numerator.
- **Status:** analytic; hardware NOT_EXECUTED. This is a **structural** prediction and a
  good early check of the pendulum model.

## S4 — Lower `M_S` costs settling time
Design A (0.995 dB) settles in 4.49 s; the reference (2.794 dB) in 2.09 s.
- **Falsified if:** a design is both more robust and faster — possible in principle, so
  worth testing rather than assuming.
- **Status:** **NUMERICALLY CHECKED**. Note Design B is a partial counter-example: it is
  both more robust *and* faster than the reference, but only by spending full control
  effort.

## S5 — `M_S` is realisation-independent, unlike `CE_Max`
- **Status:** **NUMERICALLY CHECKED** — ideal 2.794 dB, `N=100` 3.121 dB, `N=50` 3.457 dB.
  Strictly, `M_S` *does* depend on the realisation, but far more weakly than `CE_Max`
  (which scales linearly with `N`), and the ideal value is the one matching the source.

## S6 — Both outputs meet their settling objectives
- **Status:** **NUMERICALLY CHECKED** for all three designs; hardware NOT_EXECUTED.

| ID | Testable now? | Status |
|---|---|---|
| S1 | model yes, rig no | NUMERICALLY CHECKED / NOT_EXECUTED |
| S2 | **yes** | NUMERICALLY CHECKED |
| S3 | analytic; rig no | NOT_EXECUTED |
| S4 | **yes** | NUMERICALLY CHECKED |
| S5 | **yes** | NUMERICALLY CHECKED |
| S6 | model yes, rig no | NUMERICALLY CHECKED / NOT_EXECUTED |

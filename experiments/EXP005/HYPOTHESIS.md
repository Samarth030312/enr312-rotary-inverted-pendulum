> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP005/`.

# EXP005 — Hypotheses and Falsifiable Predictions

## U1 — The open-loop inverted pendulum is unstable
RHP pole at +7.2888 rad/s; 137 ms e-folding.
- **Falsified if:** it does not fall, or falls far slower — implicating `ω_g²` or `Q`
  (OI-9).
- **Status:** **SOFTWARE-TESTED** — the simulation is verified to diverge *before* any
  claim that the controller stabilises it, so "it balanced" is not vacuous.
  Hardware: trivially observable (release the pendulum). NOT_EXECUTED.

## U2 — The supplied inner controller stabilises it
`K_pend = 300 + 30s` → `ζ = 0.899`, `ω_n = 13.6 rad/s`.
- **Status:** **SOFTWARE-TESTED** (closed-loop simulation balances to completion,
  pendulum stays within the linear region). Hardware NOT_EXECUTED.

## U3 — The outer loop requires sign inversion
- **Falsified if:** the non-inverted sign balances on hardware.
- **Status:** **NUMERICALLY CHECKED** — non-inverted makes *both* of Tutorial 5's own
  designs unstable. Corroborated by the UCLA firmware's mode-dependent gain signs.
  This is the prediction whose failure would be most instructive.

## U4 — The step response undershoots (NMP zero signature)
Predicted −33 % (System 1), −11.6 % (System 2), −24 % / −40 % (designed systems).
- **Falsified if:** no initial reverse motion is observed — which would mean `T_rotor` has
  no RHP zero, contradicting the plant model.
- **Status:** **NUMERICALLY CHECKED**; hardware NOT_EXECUTED. **This is the single most
  diagnostic hardware observation in EXP005** — it is visible to the naked eye and
  directly confirms the structure.

## U5 — Measured margins match the model
`φ_M` 47.3°, `GM` 6.01 dB, `M_S` 6.37 dB for Stable System 1.
- **Tolerance:** ±10° on `φ_M`, ±3 dB on `GM`/`M_S` (EXP004's sim-vs-measurement gap was
  0.3 dB, but that was a *stable* plant).
- **Status:** NOT_EXECUTED.

## U6 — Quasi-Stable System 2 is observably closer to instability
`φ_M` 17.5° and `M_S` 10.3 dB should show as ringing, sensitivity to disturbance, and
possible loss of balance.
- **Status:** NOT_EXECUTED. **Run it last, and be ready to catch the pendulum.**

## U7 — Tutorial 5's "improved performance" claim for System 2
The model contradicts it (11.7 s vs 2.75 s settling).
- **Falsified if:** hardware shows System 2 performing better on some measure.
- **Status:** **UNRESOLVED.** Do not assume either reading.

| ID | Testable now? | Status |
|---|---|---|
| U1 | **yes** (model) | SOFTWARE-TESTED |
| U2 | **yes** (model) | SOFTWARE-TESTED |
| U3 | **yes** | NUMERICALLY CHECKED |
| U4 | model yes, rig no | NUMERICALLY CHECKED / NOT_EXECUTED |
| U5 | model yes, rig no | NOT_EXECUTED |
| U6 | **rig only** | NOT_EXECUTED |
| U7 | **rig only** | UNRESOLVED |

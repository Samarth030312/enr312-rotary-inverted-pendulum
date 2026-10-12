> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP001/`.

# EXP001 — Hypotheses and Falsifiable Predictions

Every prediction below is numeric, has a stated tolerance, and has a defined way to fail.
A prediction with no failure condition is not a prediction.

Parameter set: `PS-EDUKIT01-v1`. All predictions are **UNTESTED** — no hardware has been
connected (see the 2026-08-19 bring-up survey (internal notes, not published) §4).

---

## H1 — The arm is an open-loop position device

**Hypothesis.** Commanded net microsteps map to physical arm angle by
`theta_r = n * 0.1125 deg`, with no sensor and no correction, and this holds to within
one full step provided no step is lost.

### P1 — Commanded vs achieved arm angle
Commanding +45.0° (400 microsteps) and −90.0° (−800 microsteps) at ≤1000 steps/s
produces physical arm rotations of 45.0° and −90.0°.

- **Tolerance:** ±1.8° (one full step) per move.
- **Falsified if:** protractor-measured motion differs by more than 1.8°, or if the
  commanded-vs-measured relation is non-linear across the tested range.
- **Measured how:** protractor/angle gauge on the arm; commanded value from telemetry.

### P3 — Step fidelity (return-to-origin)
After a closed sequence of moves summing to zero net microsteps, the arm returns to its
starting mark.

- **Tolerance:** ±1.8° after 10 repetitions of a ±90° cycle.
- **Falsified if:** cumulative drift exceeds 1.8°, which is direct evidence of **lost
  steps** and refutes A2.
- **Why this matters:** this is the only test in EXP001 that can detect the open-loop
  chain's single failure mode. A drift that grows with repetition count is
  step loss; a fixed offset is a backlash or origin-latching problem.

### P5 — Step-rate quantisation
Requested step rates are achieved to +0.038 % at ≤2000 steps/s, degrading to +2.54 % at
10 000 steps/s (derivation §2.3, equations 2-3).

- **Tolerance:** ±0.1 % at ≤2000 steps/s.
- **Falsified if:** measured step frequency departs from equation (3).
- **Measured how:** oscilloscope or logic analyser on the STCK pin, or timing a long
  known move. **This prediction requires an instrument not present** — see limitation L1.

---

## H2 — The encoder measures pendulum angle with 0.15°/count and a fixed sign

**Hypothesis.** `theta_p = s * (c - c_0) * 0.15 deg` with `s` constant over the run.

### P2 — Encoder resolution
One full revolution of the pendulum shaft by hand produces exactly 2400 counts.

- **Tolerance:** ±4 counts (±0.6°), covering hand-positioning error at the start/end mark.
- **Falsified if:** the count is 600, 1200, or 4800 — each of which identifies a specific
  wrong decode mode (X1, X2, or a 1200-PPR encoder read X4) and is *diagnostically useful*
  rather than merely a failure.
- **Note:** this is the test that converts A4 from assumption to fact.

### P2b — Sign convention
Rotating the pendulum in one consistent hand-defined direction produces a monotonic count
change of one consistent sign.

- **Falsified if:** the count is non-monotonic during smooth one-directional rotation
  (indicates missed edges or channel noise, refuting A5).
- **Recorded as:** the observed sign is *written down* as the definition of `s` for this
  rig. It is not compared against the reference's `s = -1`; the reference has no authority
  over this rig's wiring.

### P4 — Count integrity (no missed edges)
Returning the pendulum by hand to a marked start position returns the counter to its
starting value.

- **Tolerance:** ±4 counts after 10 back-and-forth rotations.
- **Falsified if:** the residual grows with repetitions — evidence of missed edges from an
  inadequate pull-up or electrical noise, refuting A5.
- **Diagnostic value:** a residual that grows only during *fast* hand rotation implicates
  edge-rate/pull-up (the internal ~40 kΩ pull-up may be too weak for the open-collector
  output); a residual present even at slow rotation implicates wiring or contact.

---

## H3 — Quantisation sets a hard floor on velocity estimation

**Hypothesis.** Backward-difference velocity from this encoder at 500 Hz has granularity
1.309 rad/s and standard deviation 0.534 rad/s (derivation §3.5, equations 13-14).

### P6 — Velocity noise floor
With the pendulum held mechanically at rest, the raw backward-difference velocity estimate
is identically zero; with the pendulum moving slowly, the estimate takes only integer
multiples of 1.309 rad/s.

- **Falsified if:** non-zero velocity is reported from a stationary pendulum (indicates
  electrical noise producing spurious edges), or if the estimate takes values that are not
  multiples of `q/Ts`.
- **Status of the derivation itself:** equations (11)-(14) are pure consequences of the
  quantisation model and are verified **numerically and by simulation** in
  `scripts/exp001_sensing_analysis.py` — that part is not blocked on hardware.

---

## H4 — The wrap-safe decoder is unconditionally correct at this sample rate

**Hypothesis.** The modular-difference accumulator (equations 8-9) reconstructs pendulum
angle correctly across arbitrary 16-bit counter wraps, because the physical velocity
required to defeat it is ~6827 rev/s (equation 10) — five orders of magnitude beyond the
rig.

- **Falsified if:** a counter-value sequence exists, within the physical velocity bound,
  for which the accumulator produces a discontinuity.
- **Status:** this is a **software** claim, and it is tested exhaustively on the host in
  `firmware/enr312/test/test_enr312_encoder.c` — **not** blocked on hardware. See
  `VALIDATION.md` AC-6.

---

## Prediction status summary

| ID | Claim | Can be tested now? | Status |
|---|---|---|---|
| P1 | Commanded vs achieved arm angle | No — needs rig | NOT_EXECUTED |
| P2 | 2400 counts/rev | No — needs rig | NOT_EXECUTED |
| P2b | Sign convention | No — needs rig | NOT_EXECUTED |
| P3 | Step fidelity / no lost steps | No — needs rig | NOT_EXECUTED |
| P4 | No missed encoder edges | No — needs rig | NOT_EXECUTED |
| P5 | Step-rate quantisation | No — needs rig **and** a logic analyser | NOT_EXECUTED |
| P6 | Velocity granularity/noise | Numerically yes; on rig no | **SIMULATED** (numeric part) |
| H4 | Wrap-safe decoding | **Yes — pure software** | **SOFTWARE-TESTED** |

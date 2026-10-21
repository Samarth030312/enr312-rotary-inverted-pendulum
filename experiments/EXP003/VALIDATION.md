> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP003/`.

# EXP003 — Acceptance Criteria and Evidence

| | Count |
|---|---|
| Criteria satisfiable without hardware/MATLAB | 9 |
| **Of those, satisfied** | **9** |
| Requiring the rig | 4 |
| Requiring MATLAB | 1 |
| **Fabricated or assumed results** | **0** |

## AC3-1 — Reproduces Tutorial 3 Design 1 — **SATISFIED**

All five published metrics within **3.3 %** (table in `README.md`). This validates
`G_pend`, `G_rotor`, `K_pend`, the inner/outer loop algebra, the `CE` definition and the
`∫|u|` reading of `CE_Total` **simultaneously** — it is the strongest single check
available for EXP003. Independent self-consistency: `477² = 2.276×10⁵` matches the
tutorial's own published `CE_Max_Power`.

## AC3-2 — `CE_Total` definition resolved by evidence — **SATISFIED**

Tutorial 3 writes `∫u dτ`; its table implies 11.0. Signed integral is **0** (CE has zero
DC gain); `∫u²dt` is 1.17×10³; **`∫|u|dt` is 10.88**. Decision recorded in
`FIRST_PRINCIPLES.md` §6 and the contract, not silently applied.

## AC3-3 — Dual-PID summation, single saturation — **SATISFIED**

`test_summation_and_single_saturation`: `u = u_rotor + u_pend` verified with independent
errors in each branch; saturation applied **once to the sum**, with each branch's
unsaturated value still reported. Clamping per branch would silently change the loop
structure Tutorial 3 defines.

## AC3-4 — Inner controller fixed — **SATISFIED**

`test_inner_controller_is_fixed`: `K_P-Pend = 10`, `K_d-Pend = 5` hard-coded, not
arguments. Tutorial 3 supplies these and defers their design, so they must not drift
between runs or between students.

## AC3-5 — Closed-loop MIMO simulation — **SATISFIED**

`test_closed_loop_tracks_and_settles` simulates **both** plants. The pendulum ODE is
derived, not assumed: since `s²φ = u`,
`θ̈ + (ω_g/Q)θ̇ + ω_g²θ = ω_r²u` — no algebraic loop. Verified: rotor reaches 2° by the end
of the excitation, pendulum returns within 0.2° of zero, rotor returns to zero when the
reference does, and `CE_Max_Power = CE_Max²` by construction.

> A defect was found here: the test initially probed the final sample of the whole run,
> which lies in the SETTLE phase after the reference returns to zero — measuring the
> return-to-zero rather than the tracking. The helper now captures the end of the
> excitation phase explicitly.

## AC3-6 — Performance costs effort — **SATISFIED**

`test_lower_gain_costs_less_effort`: lower `K_P` gives strictly lower `CE_Max` **and**
`CE_Total`. This is Tutorial 3's central thesis, so it is asserted rather than assumed.

## AC3-7 — Abort paths — **SATISFIED**

Pendulum limit, rotor limit, operator abort (sticky, zeroes output), saturation
(armed-only, since a disarmed run legitimately holds a standing error). Every path
executes in the host tests rather than first on hardware.

## AC3-8 — Target cross-compilation — **SATISFIED**

Zero warnings under the strict warning set. Footprint growth recorded in `CONCLUSION.md`.

## AC3-9 — Designs 2 and 3 meet Tutorial 3 targets — **SATISFIED**

Design 2: `CE_Total` 3.78 (< 5), 2.88× reduction, settling 3.99 s ≤ 4 s, overshoot 26 % ≤ 30 %.
Design 3: `CE_Total` 1.65 (< 2.5), 6.59× reduction, settling 9.15 s < 10 s, overshoot 24.5 % < 30 %.

## AC3-10 — MATLAB — **DEFERRED — MATLAB EXECUTION ENVIRONMENT REQUIRED**

`which matlab` / `which octave` → not found. Artifacts written, toolbox-free, never
executed.

## AC3-11…AC3-14 — Hardware — **NOT_EXECUTED — BLOCKED**

R1 (measured Design 1), R2 (single-loop drift), R4 (measured reduction factors ≥2×), R5
(inner-loop damping). **No measured value is claimed anywhere in EXP003.**

## Open items

| ID | Item | Blocks |
|---|---|---|
| OI-2 | Sign conventions undetermined | all hardware |
| OI-3 | No board-support layer | hardware execution |
| OI-7 | Rotor plant `1/s²` unverified | R1 |
| **OI-9** | **`ω_r², ω_g², Q` are Tutorial 12 REFERENCE values, not measured on this rig** | R1, R5 — and every EXP003 prediction |

> **OI-9 is the dominant uncertainty in EXP003.** All pendulum-dependent predictions rest
> on parameters measured on a *different* rig. Identifying them on this rig requires a
> ring-down or frequency-response measurement, which is a system-identification task not
> included in Tutorials 1–5.

## Gate

**EXP004 may begin.** Tutorial 4 applies sensitivity-function analysis to the MIMO system
EXP003 establishes; the structure, plants and control-effort machinery are complete and
validated in software, which is what EXP004 consumes.

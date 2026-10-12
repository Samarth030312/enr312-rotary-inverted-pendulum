> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP005/`.

# EXP005 — Acceptance Criteria and Evidence

| | Count |
|---|---|
| Satisfiable without hardware/MATLAB | 9 |
| **Satisfied** | **9** |
| Requiring the rig | 5 |
| Requiring MATLAB | 1 |
| **Fabricated or assumed results** | **0** |

## AC5-1 — Open-loop instability verified before claiming stabilisation — **SATISFIED**
`test_open_loop_is_unstable` confirms the simulated plant diverges from 0.5° to >100° in
1 s, consistent with a 137 ms time constant. **This test exists so that "the controller
balanced it" is not a vacuous claim about an accidentally-stable model.**

## AC5-2 — Supplied inner controller stabilises the unstable plant — **SATISFIED**
Analytic: `s² + 24.4637s + 185.05`, poles −12.232 ± 5.953j, `ζ = 0.899`.
Simulation: `test_controller_stabilises_unstable_plant` balances to completion, pendulum
stays inside the linear region, rotor tracks 2°, pendulum near upright at the end.

## AC5-3 — Outer-loop sign inversion established by evidence — **SATISFIED**
Not assumed. With the non-inverted sign **both** of Tutorial 5's published designs are
unstable (max Re(pole) +2.4613, +1.8915); with the inversion both are stable (−1.7915,
−0.3497) **and their relative stability reproduces the Tutorial's own "Stable" /
"Quasi-Stable" naming**. Corroborated independently by the UCLA firmware's mode-dependent
gain signs. Asserted in `test_rotor_branch_is_negated`.

## AC5-4 — NMP zero and bandwidth ceiling identified — **SATISFIED**
`T_rotor`'s numerator is `den_pend`, so the RHP pole at +7.2888 rad/s becomes a RHP zero.
Bandwidth ceiling ≈ `z/2 = 3.64 rad/s`. Predicted undershoot −11 % to −40 % across designs
— the observable signature.

## AC5-5 — Capture gate — **SATISFIED**
`test_capture_gate`: does not leave WAIT_CAPTURE while the pendulum is off-upright (5°
held for 10 s), completes once within ±2° for 1 s, and **commands nothing while waiting**.
Closing the loop on a falling pendulum would throw the arm at a travel limit.

## AC5-6 — Safety bounds tightened and layered — **SATISFIED**
`test_safety_bounds_are_tighter_than_exp003` asserts 15° < 120° and warning band < hard
bound. `test_warning_band_aborts_before_hard_limit` confirms a sustained deviation inside
the hard bound still aborts within the warning window — converting a fall into a
controlled stop. `test_pendulum_lost_abort` confirms the abort is sticky and zeroes the
output even if the pendulum subsequently recovers.

15° is derived, not inherited: `sin(15°) = 0.2588` versus 0.2618 rad — 1.2 % — so the
small-angle linearisation the entire design rests on is still valid there.

## AC5-7 — Designs meeting System 1 and System 2 objectives — **SATISFIED**
System 1: `φ_M` 50.62° > 50°, `GM` 8.23 > 8 dB, `M_S` 4.52 < 5 dB, settling 3.25 < 4 s,
overshoot 24.78 < 25 %. **All five simultaneously**, and several are tight.
System 2: `φ_M` 58.57°, `GM` 4.76 dB, `M_S` 7.86 dB, settling 0.83 s, overshoot 6.4 %.

## AC5-8 — Source conflicts documented — **SATISFIED**
Three, all recorded rather than silently corrected:
1. `K_d_pend`: stated `K_P=300, T_d=0.5, K_d=K_P·T_d=30` is arithmetically impossible.
   Resolved to `K_d=30` on two independent sources; implied `T_d=0.1 s`.
2. System 2 `K_d`: table 3.33 vs transcript 3.00. 3.33 used; both evaluated.
3. **"Improved performance"** for System 2 — model contradicts it. **UNRESOLVED**, flagged
   for hardware.

## AC5-9 — Target cross-compilation — **SATISFIED**
Zero warnings under the strict set.

## AC5-10 — MATLAB — **DEFERRED — MATLAB EXECUTION ENVIRONMENT REQUIRED**

## AC5-11…AC5-15 — Hardware — **NOT_EXECUTED — BLOCKED**
U1 (open-loop fall), U4 (undershoot — the key diagnostic), U5 (measured margins),
U6 (quasi-stable behaviour), U7 (the discrepancy). **No measured value is claimed.**

## Limitations, in order of importance

1. **OI-10 — timing has never been measured.** EXP005 is the first experiment where slow
   or jittery timing causes a **fall** rather than a poor response. A 500 Hz loop gives
   ~68 samples per fall time constant, which is ample *if* the timing is as assumed —
   and that has never been checked. **Do not run EXP005 on unverified timing.**
2. **OI-9 doubly** — the inverted parameters (`ω_g²=55.85, Q=20`) differ from the
   suspended ones, and **both sets are another rig's**.
3. **The `T_d` conflict affects the inner loop**, which is what keeps the pendulum up. If
   `K_d=150` were the intended value, the inner dynamics change substantially. The
   evidence for 30 is strong (two independent sources) but it remains an inference.
4. **System 2 design is derivative-dominant** (`T_d = 21.5 s`) — same pattern as EXP004's
   Design B. Satisfies every stated constraint; Tutorial 5 constrains neither effort nor
   noise.
5. **The linear model is only valid near upright.** Every prediction assumes small angles;
   nothing here describes the swing-up or the fall.

## Gate
**EXP006+ is outside the scope of this release** (docs/ENGINEERING_STANDARDS.md §5).

> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP001/`.

# EXP001 — Acceptance Criteria and Evidence

Status vocabulary (ENVIRONMENT.md / task categories):

`IMPLEMENTED` · `COMPILED` · `SOFTWARE-TESTED` · `SIMULATED` · `PHYSICALLY-TESTED` ·
`EXPERIMENTALLY-VALIDATED` · `DEFERRED` · `NOT_EXECUTED`

Evaluated at source revision 44bda39 + this working tree, 2026-08-19.

---

## Summary

| | Count |
|---|---|
| Criteria satisfiable without hardware | 8 |
| **Of those, satisfied** | **8** |
| Criteria requiring the rig | 3 |
| Criteria requiring an instrument not present | 1 |
| **Fabricated or assumed results** | **0** |

---

## AC-1 — Rig identity established from an authoritative source

**Status: SATISFIED.**

Evidence: `course material Edukit_Student_Lab_Handout.pdf` is headed
"ENR312 — Rotary Inverted Pendulum Lab" and states the per-station equipment as
"STEVAL-EDUKIT01 rig (NUCLEO-F401RE + X-NUCLEO-IHM01A1 + NEMA17 stepper + encoder)".
Its "Experiment 1 — Digital Motor Actuator & Angle Sensing" is EXP001.

Recorded in the 2026-08-19 bring-up survey (internal notes, not published) §2 and
`shared/parameters/edukit01_rig.yaml`.

**Caveat, recorded not hidden:** `docs/references/ENR312.pdf` (the course outline)
describes sessions 9–10 as an inverted pendulum driven by a *DC servo motor*. That
conflicts with the handout. See open item **OI-1**. Physical confirmation is procedure
step 0.1.

---

## AC-2 — Firmware reconnaissance completed; authority correctly assigned

**Status: SATISFIED.**

Evidence: the 2026-08-19 bring-up survey (internal notes, not published). Principal finding — the firmware
in `Core/` is an autonomous-vehicle application (BNO085 IMU, ESC/servo PWM,
`bfmc_msgs/ControlCommand`), contains no encoder, stepper or SPI, and cannot host EXP001.
The pin conflict is tabulated pin-by-pin in §3.

Consequence applied: `Core/` and `odyssix_stm32_core.ioc` were **not modified**. The
EXP001 core lives in `firmware/enr312/` with its own build.

---

## AC-3 — Baseline build reproducible and characterised

**Status: SATISFIED (COMPILED).**

Evidence: `make clean && make -j$(nproc)` with arm-none-eabi-gcc 13.2.1:

```
text     data      bss      dec      hex
142092   1752    94128   237972    3a194
```

Flash 143 844 / 524 288 B = 27.4 %. RAM 95 880 / 98 304 B = 97.5 %.

Four pre-existing warnings, none introduced by this work: three `-Wunused-result` in
`Core/Src/freertos.c` (lines 172, 173, 437) and one benign linker warning
(`_gettimeofday`). All four are diagnosed in RECONNAISSANCE §5. The two at lines 172–173
are a genuine defect in the vehicle application and are recorded as such; they are **not
fixed**, because doing so would change runtime behaviour in an application outside
EXP001's scope, and `Core/` is deliberately unmodified.

Verified unmodified: `git status --short Core/ Makefile odyssix_stm32_core.ioc
STM32F401RETX_FLASH.ld Drivers/ Middlewares/` reports nothing, and the rebuilt ELF is
byte-identical in size to the pre-work baseline.

---

## AC-4 — First-principles derivation, with units and sign conventions

**Status: SATISFIED.**

Evidence: `FIRST_PRINCIPLES.md`, equations (1)–(14). Both chains derived from the
physical mechanism. Every quantity carries a unit. Both sign conventions are declared to
be *chosen and then measured*, and are explicitly **not** inherited from the reference.
Eight assumptions A1–A8 tabulated with consequences and test locations.

---

## AC-5 — Rig constants derived, cross-checked, and provenance-tagged

**Status: SATISFIED.**

Evidence: `shared/parameters/edukit01_rig.yaml`. Every value carries a provenance tag.
Independent cross-check — constants derived here from part geometry reproduce the UCLA
reference's constants exactly:

| Derived here | Reference constant | Agreement |
|---|---|---|
| 2400 counts/rev → 6.666667 counts/deg | `ENCODER_READ_ANGLE_SCALE = 6.666667` | exact |
| 3200 microsteps/rev → 8.888889 /deg | `STEPPER_READ_POSITION_STEPS_PER_DEGREE = 8.888889` | exact |
| ratio 0.75 | implied by the two above | exact |

Asserted in `test_enr312_rotor.c::test_actuation_constants` and
`test_enr312_encoder.c::test_resolution_constants`.

**No parameter is MEASURED.** All are predictions until EXP001/EXP002 execute.

---

## AC-6 — Sensing chain implemented and proved correct in software

**Status: SATISFIED (IMPLEMENTED, SOFTWARE-TESTED).**

Evidence: `firmware/enr312/src/enr312_encoder.c`; 38 checks in
`test_enr312_encoder.c`, all passing:

- Wrapped difference (eq. 8) verified **exhaustively** over all 65 536 signed deltas at
  seven starting points — 458 752 cases, zero failures. This is a complete proof over
  the input domain, not a sample.
- 100 forward and 100 reverse revolutions across multiple 16-bit wraps: exact.
- 200 000-sample pseudo-random walk tracked against independently computed truth: exact.
- Half-modulus boundary verified in **both** directions — correct at +32767, and shown to
  alias at +32768 exactly as the theory predicts. A guarantee whose failure mode is
  untested is not a guarantee.
- Aliasing threshold confirmed at 6826.67 rev/s (eq. 10).
- Velocity granularity confirmed at 1.308997 rad/s (eq. 13); zero on the first sample;
  zero for a stationary input; no divide-by-zero at `Ts = 0`.
- Invalid polarity coerced to +1 rather than stored raw.

This satisfies hypothesis **H4** without hardware.

---

## AC-7 — Actuation chain implemented and its command model tested

**Status: SATISFIED (IMPLEMENTED, SOFTWARE-TESTED).**

Evidence: `firmware/enr312/src/enr312_rotor.c`; 49 checks in `test_enr312_rotor.c`.

- +45° = 400 microsteps and −90° = −800 microsteps, exactly (eq. 1).
- Ten zero-net cycles leave the commanded position at exactly 0.
- Travel limits clamp at ±2133 microsteps and count the event; a clamp truncates rather
  than rejects, so the model stays consistent with what the hardware was told.
- Non-finite arguments rejected without changing state.
- Timer arithmetic (eqs. 2–3) verified: ARR 81 → 1000.381 steps/s (+0.038 %);
  ARR 40 → 2000.762 (+0.038 %); ARR 7 → 10253.906 (**+2.54 %**), confirming P5's
  predicted degradation at high rates.
- Rate cap enforced; zero rate and NULL output rejected.

**Limit of this criterion:** these verify the *command model*, not physical motion.
Nothing measures the arm. P1 and P3 need the rig.

---

## AC-8 — Experiment sequencer implemented, with exercised safety paths

**Status: SATISFIED (IMPLEMENTED, SOFTWARE-TESTED).**

Evidence: `firmware/enr312/src/enr312_exp001.c`; 32 checks in `test_enr312_exp001.c`.

- Dry run (`armed = false`) completes the whole sequence and commands **exactly zero**
  motion — the intended pre-power validation.
- Armed run visits every P1 and P3 setpoint and returns the commanded position to
  exactly zero.
- Pendulum-excursion abort fires past ±120°, records its reason, and is **sticky**.
- The safety check runs during dry runs and during IDLE, so no abort path reaches the rig
  having never executed.
- Operator abort freezes commanded motion permanently.
- No arm motion is commanded during IDLE or SENSE_ONLY — the phases in which the operator
  is handling the pendulum.
- CSV field count matches the header, so the analysis parser cannot silently mis-column.

**Two defects were found and fixed by these tests**, both of which would have reached
hardware:
1. The P3 phase skipped its closing return-to-zero, leaving the arm parked at −90° and
   the "zero-net-motion" test not ending at zero net motion — silently invalidating P3.
2. The step-tick rate was truncated from 82031.25 Hz to 82031 Hz, biasing every predicted
   step rate and putting the firmware out of agreement with the derivation.

---

## AC-9 — Target cross-compilation

**Status: SATISFIED (COMPILED).**

`make arm` in `firmware/enr312/` compiles the core for `cortex-m4 / fpv4-sp-d16 /
hard-float` with `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion
-Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wdouble-promotion`.

**Zero warnings.** Footprint: text 2086 B, data 0 B, bss 0 B — all state is
caller-owned, so the core adds nothing to static RAM.

---

## AC-10 — Numerical analysis executed and independently cross-checked

**Status: SATISFIED (SIMULATED — numerical).**

Evidence: `scripts/exp001_sensing_analysis.py`, executed. Outputs in
`results/tables/EXP001_sensing_analysis.csv` and four figures.

The analytic results (eqs. 11 and 14) are confirmed by a 4×10⁶-sample Monte-Carlo
simulation that assumes neither:

| Quantity | Analytic | Simulated | Ratio |
|---|---|---|---|
| σ_θ | 7.557497×10⁻⁴ rad | 7.555111×10⁻⁴ rad | 0.9997 |
| σ_ω | 0.534396 rad/s | 0.534222 rad/s | 0.9997 |

Mean residual 1.66×10⁻⁷ rad — bias-free, as the uniform model requires. The script
asserts these ratios, so a future change to the derivation that breaks them fails loudly.

Figures, each answering a stated engineering question:

| Figure | Question answered |
|---|---|
| `EXP001_fig1_quantisation_effect.png` | What does quantisation do to a slow, small motion? |
| `EXP001_fig2_velocity_noise_tradeoff.png` | Does sampling faster or resolving finer reduce differentiation noise? |
| `EXP001_fig3_step_rate_quantisation.png` | Over what rate range is the achieved step rate trustworthy? |
| `EXP001_fig4_wrap_safety.png` | Does the wrap-safe accumulator track truth across 16-bit wraps? |

Every figure is titled "ALGORITHMIC, not measured".

---

## AC-11 — MATLAB simulation

**Status: DEFERRED — MATLAB EXECUTION ENVIRONMENT REQUIRED.**

`which matlab` → not found. `which octave` → not found. Verified on this machine.

Delivered instead: portable, path-independent MATLAB sources under
`matlab/`, with parameters, expected values, and self-checking validation.
**They have never been executed.** Execution procedure in `matlab/README_EXP001.md`.

---

## AC-12 — Hardware execution

**Status: NOT_EXECUTED — BLOCKED.**

`st-info --probe` → "Found 0 stlink programmers". No `/dev/ttyACM*` or `/dev/ttyUSB*`.
No ST-LINK USB device (VID 0483). The rig is not attached to this machine.

Blocked predictions: **P1, P2, P2b, P3, P4** (need the rig) and **P5** (needs the rig
*and* an oscilloscope or logic analyser, neither present).

Procedure ready in `PROCEDURE.md`. Data templates ready in `MEASUREMENTS.md`. Analysis
pipeline ready and self-tested in `scripts/exp001_process_measurements.py`.

**No measured value is claimed anywhere in this experiment.**

---

## Open items

| ID | Item | Blocks | Resolution |
|---|---|---|---|
| **OI-1** | Course outline says DC servo motor; lab handout says NEMA17 stepper | AC-1 fully | Physical inspection, procedure step 0.1 |
| **OI-2** | Sign conventions for both chains are undetermined | EXP002 | P1 and P2b |
| **OI-3** | No board-support layer: TIM3 encoder init, L6474 SPI driver, step-clock ISR, telemetry UART | AC-12 | Write against the rig once present; see `CONCLUSION.md` |
| **OI-4** | Pin map is `REFERENCE_UNVERIFIED` | AC-12 | Procedure step 0.2 |
| **OI-5** | Travel limits inherited from the reference | AC-12 | Procedure step 0.3 |
| **OI-6** | Mechanical parameters (masses, lengths, inertias) unknown | EXP004 | Direct measurement — not needed by EXP001 |

---

## Gate decision

**EXP001 is COMPLETE to the limit this environment permits, and is NOT complete as an
experiment.**

Everything that does not require the rig has been done and evidenced. Everything that
does require the rig is blocked, documented, and prepared.

**EXP002 must not begin.** EXP002 is sensor calibration and sign conventions — it
consumes exactly the outputs (P2, P2b, P4) that are blocked. Starting it would mean
calibrating against assumed constants, which is the specific failure mode EXP001 exists
to prevent.

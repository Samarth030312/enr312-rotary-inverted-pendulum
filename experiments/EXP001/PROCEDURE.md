> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP001/`.

# EXP001 — Hardware Procedure

**STATUS: NOT_EXECUTED.** No ST-LINK programmer and no serial device are attached to
this machine (`st-info --probe` → 0 programmers; no `/dev/ttyACM*`). Nothing below has
been performed. This document is the procedure to follow when the rig is available.

**Firmware flashing and all physical operation are deliberate operator actions.** The developer
does not flash, does not energise the motor, and does not move the mechanism.

---

## 0. Before anything is powered

### 0.1 Confirm the rig — do not skip this

The rig identity comes from a course document, not from measurement. Confirm by
inspection and record in `MEASUREMENTS.md`:

- [ ] MCU board is a NUCLEO-F401RE (read the silkscreen; **not** F411, **not** F446).
- [ ] Motor shield is an X-NUCLEO-IHM01A1 with an L6474 (read the chip marking).
- [ ] Stepper is a NEMA-17; record the full part number from its label.
- [ ] Encoder body markings — record verbatim, especially the PPR figure.
- [ ] Supply is 12 V and adequately rated.

**If any of these differ from `PS-EDUKIT01-v1`, STOP.** Update the parameter set first.
Every constant in the firmware derives from these parts.

### 0.2 Confirm the pin map

The pin map in the parameter set is `REFERENCE_UNVERIFIED`. Before flashing:

- [ ] Encoder A/B land on PB4/PB5 (TIM3_CH1/CH2).
- [ ] Encoder needs a pull-up (open-collector output). Confirm whether the internal
      pull-up is being relied on, or an external resistor is fitted. Record which.
- [ ] The IHM01A1 occupies PA5/PA6/PA7 (SPI1), PB6 (CS), PA8 (DIR), PA9 (RESET),
      PA10 (FLAG), PC7 (STCK).

> **PA5 is both the Nucleo LD2 LED and SPI1_SCK.** With the shield fitted, LD2 flickers
> with SPI traffic. That is expected and is not a fault.

### 0.3 Confirm travel limits against *this* rig's cabling

`±240°` rotor travel is inherited from the reference. Check the actual cable length and
routing on this rig and reduce the limit if 240° would strain or wrap a cable. Record
the value used.

### 0.4 Mechanical preparation

- [ ] Rig on a flat, stable surface; nothing within the swing path.
- [ ] Pendulum hangs freely; it must be able to rotate a full revolution by hand for P2.
- [ ] Apply an index mark to the arm and a matching mark on the base — P3 is read off
      these marks and cannot be done without them.
- [ ] Apply an index mark to the pendulum shaft for the P2 revolution count.

### 0.5 Safety review

- Keep fingers, hair and cables clear of the swing path.
- **Never connect or disconnect the motor with the 12 V supply on.** Power on last, off
  first.
- If the motor buzzes loudly, gets hot, or the arm slams a limit: cut power or press
  RESET immediately.
- Do not force the arm by hand while it is powered and holding position.
- Motor current is configured to 800 mA against a 2.0 A-rated motor. **Do not raise it.**

---

## 1. Build

```bash
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"

# EXP001 core: host unit tests, then target cross-compile check
cd firmware/enr312
make test        # must print ALL EXP001 HOST TESTS PASSED
make arm         # must print: EXP001 core cross-compiles clean for the target
```

> **The EXP001 core is not yet integrated into a flashable application.** The board
> layer (TIM3 encoder init, L6474 SPI driver, step-clock ISR, telemetry UART) does not
> exist — see `CONCLUSION.md`, open item OI-3. This procedure documents the intended
> sequence; step 2 cannot be performed until that layer is written and the rig is
> present to write it against.

---

## 2. First power-up — DRY RUN, motor de-energised

Run the sequencer with `armed = false`.

- [ ] 12 V supply **off**; USB only.
- [ ] Flash; open the telemetry stream.
- [ ] Confirm the phase sequence advances IDLE → SENSE_ONLY → STEP_P1 → RETURN_P3 → DONE.
- [ ] Confirm `rotor_cmd_microsteps` stays 0 for the entire run.
- [ ] While in SENSE_ONLY, rotate the pendulum by hand and confirm `encoder_counts`
      changes.

**Do not proceed until the dry run completes cleanly.** A dry run that aborts, stalls, or
commands non-zero motion indicates a firmware or wiring fault, and diagnosing it with the
motor live is strictly worse.

---

## 3. P2 / P2b — encoder resolution and sign (motor still de-energised)

Performed during the SENSE_ONLY phase, or as a standalone sensing-only build.

1. Align the pendulum index mark to a fixed reference. Record `encoder_counts` as `c_start`.
2. Rotate the pendulum by hand through **exactly one full revolution**, in a direction you
   describe unambiguously in writing (e.g. "clockwise when viewed from the encoder end").
   Rotate slowly and smoothly.
3. Re-align the index mark. Record `encoder_counts` as `c_end`.
4. **P2:** `|c_end − c_start|` should be 2400 ± 4.
   - 600 → the timer is decoding X1. 1200 → X2. Fix `ENR312_ENCODER_DECODE_X`.
   - Anything else → the encoder is not 600 PPR. Re-read its label.
5. **P2b:** record the *sign* of `c_end − c_start` together with the direction you turned.
   **This defines the sign convention for this rig.** Write it in prose, not just as a
   number — "counts increase when the pendulum tip moves toward the operator" is
   unambiguous; "+1" is not.
6. **P4:** repeat the out-and-back rotation ten times, returning to the index mark each
   time. The residual should stay within ±4 counts and must not grow with repetitions.
   Growth indicates missed edges — suspect the pull-up.

---

## 4. P1 — commanded vs achieved arm angle (**motor energised**)

**First powered motion. Hand on the power switch.**

1. Clear the swing path. Confirm the arm index mark is aligned to its base mark.
2. Power the 12 V supply on.
3. Run the sequencer with `armed = true`, step rate capped at 1000 steps/s (112.5 °/s).
4. During STEP_P1 the arm visits 0°, +45°, 0°, −90°, 0°, dwelling 1 s at each.
5. At each dwell, measure the **physical** arm angle with a protractor/angle gauge
   referenced to the base mark. Record measured vs commanded.
6. **P1 passes** if each measured angle is within ±1.8° (one full step) of commanded.

> The firmware cannot check this. There is no arm sensor. The protractor reading is the
> only evidence, and it must be entered by hand into `MEASUREMENTS.md`.

**Abort immediately if:** the motor buzzes without moving (stalling — steps are being
lost), the arm moves in the direction opposite to the command, or motion is jerky or
noisy.

---

## 5. P3 — step fidelity (**motor energised**)

Performed by the RETURN_P3 phase: ten cycles of 0 → +90° → 0 → −90° → 0. Net commanded
motion per cycle is exactly zero.

1. Before the phase begins, confirm the arm index mark is aligned.
2. Let all ten cycles run without interference.
3. At the end, measure the physical offset between the arm mark and the base mark.
4. **P3 passes** if the residual is within ±1.8°.

Interpreting a failure — this is the diagnostically richest test in EXP001:

| Observation | Most likely cause |
|---|---|
| Residual grows roughly linearly with cycle count | Steps lost every cycle — reduce rate, or raise current with justification |
| Fixed offset, does not grow | Backlash, or the origin was latched while the arm was moving |
| Residual varies in sign run to run | Marginal torque; the motor is near its stall limit |
| Zero residual | A2 holds at this rate — the open-loop position model is trustworthy here |

**A2 is only established at the rate tested.** It says nothing about higher rates.

---

## 6. P5 — step-rate quantisation (**instrument required**)

Requires an oscilloscope or logic analyser on the STCK pin (PC7).

1. Command 200, 500, 1000 and 2000 steps/s in turn.
2. Measure the actual pulse frequency at each.
3. **P5 passes** if each is within ±0.1 % of the value predicted by equation (3).

**No such instrument is available.** P5 is DEFERRED — see `VALIDATION.md`, AC-11.

A weaker substitute that needs no instrument: command a long move (e.g. 36 000
microsteps) at a known rate and time it with a stopwatch. This resolves ~1 % over a 36 s
move — enough to catch a gross rate error, not enough to confirm the 0.038 % prediction.
Record it as an indicative check, never as P5 passing.

---

## 7. Shutdown

1. Command the arm back to 0°.
2. **12 V supply off first.**
3. USB off.
4. Save the telemetry CSV to `data/raw/` under an immutable name:
   `EXP001_<YYYYMMDD>_<HHMM>_<short-git-rev>.csv`
5. Write the metadata sidecar in `data/metadata/` (template in `MEASUREMENTS.md`).
6. **Never edit a file in `data/raw/`.**

---

## 8. Analysis

```bash
python3 scripts/exp001_process_measurements.py data/raw/EXP001_<...>.csv
```

Then complete `MEASUREMENTS.md` (including the protractor readings, which no script can
obtain) and `CONCLUSION.md`, and update `VALIDATION.md` status for AC-9…AC-12.

---

## Abort criteria — any one of these stops the experiment

| Trigger | Action |
|---|---|
| \|pendulum angle\| > 120° | Firmware aborts automatically and stops commanding motion |
| Rotor travel limit reached | Firmware aborts automatically |
| Motor buzzing, stalling, or hot | **Cut 12 V immediately** |
| Arm moves opposite to command | Cut power; the actuation sign is wrong |
| Cable strain or wrap | Cut power; reduce the travel limit |
| Anything unexpected | Cut power first, diagnose second |

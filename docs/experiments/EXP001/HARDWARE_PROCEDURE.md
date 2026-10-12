> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`FIRST_FLASH.md`](FIRST_FLASH.md).

# EXP001 — Hardware Bring-Up Procedure

**Date:** 2026-08-20 · **Revision:** `73c7d31` · **Status: NOT EXECUTED**

> # ⛔ READ BEFORE TOUCHING ANYTHING
> This is a **first-power-on** procedure for hardware nobody has inspected. Its stages are
> ordered so that **no stage can damage anything if the previous stage passed**, and every
> stage is reversible.
>
> **The actuator is not energised until Stage 8**, and its first motion is one step.
>
> If any stage fails, **stop at that stage**. Do not proceed hoping the next one clarifies
> it.

**Companion documents — read all four first:** `HARDWARE_INVENTORY.md`, `WIRING_MAP.md`,
`POWER_SAFETY.md`, `SIGNAL_PATH.md`.

---

## Stage 0 — Blocking prerequisites

| # | Item | Why blocking |
|---|---|---|
| 0.1 | **OI-1: is the actuator a stepper?** | The course outline says DC servo; the handout says NEMA17 stepper. **If it is a servo, this entire procedure is wrong** — stop and re-derive EXP001 |
| 0.2 | **STM32F401 datasheet obtained**, 5 V tolerance of PB4/PB5 recorded | Encoder is 5 V open-collector; connecting it blind can destroy the MCU |
| 0.3 | **IHM01A1 user manual obtained** | Motor supply range and jumper configuration are `UNKNOWN` |
| 0.4 | **Board-support layer written (OI-3)** | TIM3 encoder init, L6474 SPI driver, step ISR, telemetry UART **do not exist** |

**All four must be satisfied.** Stages 1–7 can be rehearsed without 0.4; **Stage 8 onward
cannot happen at all** until the driver layer exists.

```
[ ] 0.1 rig identified as stepper-based        [ ] 0.3 IHM01A1 manual obtained
[ ] 0.2 STM32F401 datasheet obtained           [ ] 0.4 board-support layer written
```

---

## Stage 1 — Inspection (no power, nothing connected)

- [ ] Nucleo silkscreen reads **NUCLEO-F401RE** (not F411/F446)
- [ ] Shield reads **X-NUCLEO-IHM01A1**; driver IC marked **L6474**
- [ ] Stepper label — record the **full** part number
- [ ] Encoder body — record markings, especially **PPR** and supply voltage
- [ ] PSU label — record output voltage, **current rating**, connector type
- [ ] Photograph every label. Record all of it in `PHYSICAL_PARAMETERS.md` §7

**Compare against `HARDWARE_INVENTORY.md`. Any mismatch → stop and update the inventory
before continuing.**

---

## Stage 2 — Power-off continuity and polarity

Multimeter only. **Nothing connected to mains. Nothing powered.**

- [ ] **PSU polarity** — with the PSU *unplugged*, identify centre/sleeve. Then plug it
      in **with nothing attached** and measure: record **which conductor is positive** and
      the actual voltage
- [ ] PSU unplugged again before proceeding
- [ ] **Common ground** — continuity between the PSU negative terminal and a Nucleo `GND`
      pin, once the shield is seated. **Expect continuity. If absent, stop** — the signals
      have no shared reference (`WIRING_MAP.md` §4)
- [ ] **No output-to-output** — check the pin-conflict table in `WIRING_MAP.md` §5
- [ ] Encoder leads: confirm Red/Black are supply/ground **before** connecting them

```
[ ] PSU polarity measured: positive = ____________  voltage = ______ V
[ ] Common ground confirmed
[ ] No output-to-output conflicts
```

---

## Stage 3 — Encoder electrical check ⚠ (the MCU-damage stage)

**The encoder is NOT connected to the STM32 during this stage.**

1. Connect **only** encoder Red → 5 V and Black → GND. Leave A and B **floating**.
2. Power the 5 V rail (USB is sufficient). **12 V stays OFF.**
3. Measure encoder A and B against ground with the MCU **disconnected**:

```
[ ] A idle-high = ______ V        [ ] B idle-high = ______ V
[ ] Rotate by hand -- both toggle
[ ] External pull-up fitted?  yes / no    value ______  to rail ______
```

4. **Compare against the STM32 input rating from Stage 0.2.**

> **If the idle-high voltage exceeds the STM32 input rating, STOP.**
> Do not connect A/B. A 3.3 V pull-up or a level shifter is required.
> This is the single most likely way to destroy the MCU during bring-up.

5. Only if within rating: power down, connect A → PB4, B → PB5.

---

## Stage 4 — Logic-only power-up

**12 V supply DISCONNECTED. Motor DISCONNECTED from the shield.**

- [ ] USB connected; Nucleo enumerates; ST-LINK detected (`st-info --probe` ≥ 1)
- [ ] Flash the **pendulum** firmware
- [ ] Nothing gets warm

> ### ⛔ DO NOT FLASH THE INHERITED VEHICLE FIRMWARE WITH THE SHIELD FITTED
> `build/odyssix_stm32_core.elf` drives **PA5** as a GPIO heartbeat into the L6474's SPI
> clock and **PA9/PA10** as USART1 into `nRESET`/`nFLAG`. See `WIRING_MAP.md` §5.

---

## Stage 5 — Communication

- [ ] Telemetry appears over the ST-LINK virtual COM port
- [ ] Header matches `ENR312_Exp001_CsvHeader()` exactly
- [ ] Rate ≈ 500 lines/s, no dropouts or corruption

**If the header does not match exactly, stop** — the analysis pipeline refuses mismatched
columns by design.

---

## Stage 6 — Sensor check (motor still de-energised)

Encoder only. The pendulum is moved **by hand**.

- [ ] `encoder_counts` changes when the pendulum is rotated
- [ ] Motion is **monotonic** during smooth one-directional rotation — non-monotonic means
      missed edges (weak pull-up, `POWER_SAFETY.md` §4)
- [ ] **P2 — resolution:** one full revolution against an index mark. Record the count.
      **Expect 2400 ± 4.** 600 → X1 decode; 1200 → X2. Fix `ENR312_ENCODER_DECODE_X`,
      rebuild, repeat. **Do not apply a scale factor downstream**
- [ ] **P2b — sign:** record which way counts increase, **in prose**
      ("counts increase when the tip moves toward the operator"). This *defines*
      `ENR312_ENCODER_POLARITY`. The reference's −1 has no authority here
- [ ] **P4 — integrity:** ten out-and-back rotations; residual within ±4 counts and **not
      growing**

```
[ ] P2 counts/rev = ______   [ ] P2b polarity = ____  direction: ______________
[ ] P4 residual after 10 = ______ counts    growing? yes / no
```

---

## Stage 7 — Actuator dry run (**still de-energised**)

**12 V still disconnected.** Run the sequencer with `armed = false`.

- [ ] Phase sequence IDLE → SENSE_ONLY → STEP_P1 → RETURN_P3 → DONE
- [ ] `rotor_cmd_microsteps` stays **0** throughout
- [ ] Abort paths fire when provoked (tilt the pendulum past 120°)

**Do not proceed until the dry run completes cleanly.** Diagnosing a fault with the motor
live is strictly worse.

---

## Stage 8 — First energised motion: ONE STEP

**First time the actuator is powered. Hand on the 12 V switch.**

1. Clear the swing path. Mark the arm and base positions.
2. Connect the motor to the shield **with 12 V off** (handout: never connect the motor
   with the supply on).
3. **Logic first, motor supply last** (`POWER_SAFETY.md` §6 — the sources conflict; the
   handout's order is used).
4. Command **one single microstep**.

```
[ ] Arm moved?  yes / no       [ ] Direction: ______________
[ ] Motor quiet (no buzz, no stall)      [ ] Motor not warm
```

**Abort immediately if** the motor buzzes without moving (stalling), gets warm, or the arm
moves unexpectedly far.

> **Never begin with a large or continuous actuator command.** One step, observed, then
> stop.

---

## Stage 9 — Low-amplitude motion and the ×2 resolution ⚠

Step rate capped at **1000 steps/s** (112.5 °/s).

1. Command **+45°** (400 microsteps at the current constant).
2. **Measure the physical arm angle with a protractor.**

```
[ ] Commanded +45 deg -> measured ______ deg
```

> ### THIS RESOLVES THE FACTOR-OF-TWO CONFLICT
> | Measured | Meaning |
> |---|---|
> | **≈ 45°** | UCLA reference code is right; EXP001's constant stands |
> | **≈ 22.5°** | **Edukit Manual is right** — the control gain is 17.778 steps/°, and **every commanded angle in EXP001–EXP005 is out by 2×** |
> | anything else | Neither — record it and stop |
>
> See `SIGNAL_PATH.md` §2. **Do not adjust firmware until this is measured.**

3. **P1** — repeat for −90°, and 0° between each. Tolerance ±1.8° (one full step).
4. **P1 direction** — does the arm move the commanded way? This defines
   `ENR312_ROTOR_POLARITY`.

---

## Stage 10 — Sign and angle verification

- [ ] Encoder polarity from Stage 6 written into `enr312_rig_config.h`
- [ ] Rotor polarity from Stage 9 written in
- [ ] Rebuild, re-flash, confirm both signs behave as recorded

**Both were placeholders (`+1`) precisely so an unmeasured value could not masquerade as
a measured one.**

---

## Stage 11 — Controlled EXP001 run

Full sequencer, `armed = true`, 1000 steps/s, 2° excitation.

- [ ] **P3** — ten zero-net cycles; physical residual within ±1.8°, not growing
- [ ] Telemetry captured for the whole run
- [ ] Saved to `data/raw/EXP001/EXP001_<YYYYMMDD>_<HHMM>_<git-rev>.csv` + metadata sidecar

```bash
python3 scripts/exp001_process_measurements.py data/raw/EXP001/EXP001_<...>.csv
```

Then complete `experiments/EXP001/MEASUREMENTS.md` and update `VALIDATION.md` AC-12.

---

## Stage 12 — Shutdown

1. Command the arm to 0°.
2. **12 V OFF first**, then USB.
3. **Never edit anything in `data/raw/`.**

---

## Abort criteria — any one stops the run

| Trigger | Action |
|---|---|
| Encoder idle-high exceeds the STM32 rating | **Do not connect.** Stop at Stage 3 |
| No common ground | **Stop at Stage 2** |
| Motor buzzes without moving | **Cut 12 V** — stalling, losing steps |
| Motor warm or hot | **Cut 12 V** |
| Arm moves opposite to command | Cut 12 V; record — it is a sign finding, not a fault |
| Encoder count non-monotonic | Stop; suspect the pull-up |
| Measured angle ≈ half commanded | **Stop.** The manual is right; the constant is wrong |
| Anything unexpected | **Cut power first, diagnose second** |

---

## What this procedure resolves

| Open item | Resolved at |
|---|---|
| **OI-1** rig identity | Stage 0.1 / Stage 1 |
| **OI-4** pin map | Stages 1–3 |
| **OI-5** travel limits | Stage 1 (cable inspection) |
| **OI-2** sign conventions | Stages 6 and 9 |
| **Actuator ×2 conflict** | **Stage 9** |
| **OI-3** board layer | must be written *before* Stage 4 |
| OI-7 rotor plant `1/s²` | EXP002, not here |
| OI-9 pendulum parameters | needs system ID; not in Tutorials 1–5 |
| **OI-10 timing** | **not resolved here — blocking for EXP005** |

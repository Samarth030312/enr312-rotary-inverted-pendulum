# ENR312 first flash and first motion

**Read `docs/hardware/PRE_POWER_CHECKLIST.md` first.** Steps 1–9 below need only
USB power and are safe with the 12 V motor supply disconnected. Steps 10–13 move
a motor.

---

## What you are flashing

```
TARGET      ENR312 rotary inverted pendulum
MCU         STM32F401RETx  (NUCLEO-F401RE, device ID 0x433)
FIRMWARE    enr312-target-2.0.8 (protocol 2: closed-loop Tutorials 2-5, 115200 baud)
IMAGE       firmware/enr312/release/enr312_pendulum.elf   (committed release)
TARGET IOC  firmware/enr312/target/enr312.ioc
ELF SHA256  78417888ddf615b6b300407c94c840b35c7dc0ef185fcb2ce411198b6ac50800
BIN SHA256  67241e77952ceae212e5ec04e3192328b78b1df706fc56f10bbc3e326b7b183b
FLASH USE   44 084 / 524 288 B  =  8.41 %
RAM  USE     4 352 /  98 304 B  =  4.43 %  (static; + 0x800 stack  0x200 heap)

```

> Only flash images that carry the ENR312 banner. The flash tool refuses any other
> image: an application built for the same Nucleo with a different pin map can
> drive PA9, the L6474 reset line, as an output.

## The easy way: from MATLAB

`enr312_lab` → **Detect board** → **Flash firmware** flashes the release above
through the programmer inside STM32CubeIDE, after three refusal gates (ENR312
banner, release hash, device ID 0x433). Steps 5–7 below are the same thing by
hand. Before the first flash, run `scripts/flash_ready_check.sh` (16 gates, no
hardware) and the wiring checks in `docs/hardware/ENR312_WIRING.md` §4.

**Record on first boot** (type `t` in a terminal, or read the stream in MATLAB):
`isr_max_us` (worst-case control ISR time, the first loop-timing evidence for
OI-10; the budget is 2000 µs) and `rxerr` (must stay 0).

**Recorded 2026-10-12** (two NUCLEO-F401RE boards, 2.0.4–2.0.6): `isr_max_us` 19–33 µs
(budget 2000 µs), `rxerr` 0. +5° commanded = 44 microsteps, protractor 5° (C-1
resolved: 8.889 microsteps/°); arm turns toward the app's green line (rotor
polarity +1); first pendulum swing opposite to the move with polarity +1, so
2.0.7 sets `ENR312_ENCODER_POLARITY` = −1. Evidence:
`results/evidence/logs/rig_20261012-160027.log`.

**2.0.7 confirmed 2026-10-12** on board 1 (ST-LINK …124223; flash log
`flash_20261012-223653.log`, verified, 0x433). Rig log `rig_20261012-223811.log`:
ARM and START succeeded, ±34.74° = ±309 microsteps, the arm returned to 0.000°, no
faults, `isr_max_us` 32. At every arm start and stop (4 of 4) the pendulum's first
swing had the **same** sign as the arm's acceleration (peaks 2.1–2.9° within 0.4 s):
encoder polarity −1 is correct. `rxerr` read 1 at connect (one status line only, so its trend is unknown; recheck with `t`).

## Behaviour to expect at reset

The firmware boots into **SAFE**: L6474 held in reset, bridges high-Z, step
clock stopped. **Nothing moves, and nothing can move**, until you type `a` then
`s`. There is no autonomous startup sequence.

Note: PA5 is both SPI1_SCK and the Nucleo **LD2** green LED. LD2 will flicker
during SPI traffic and is otherwise dark. That is correct, not a fault — this
target has no heartbeat LED, and reports liveness over the serial console instead.

---

## Procedure

### Power-off, motor supply disconnected

1. **12 V motor PSU unplugged** from the shield. Confirm visually.
2. Pendulum arm hanging free, nothing within its swing radius. Rotate it by hand
   through its full travel — it must not foul anything.
3. Encoder harness connected **only if Stage 2 of the pre-power checklist
   passed**. If E1–E3 are unresolved, leave the encoder disconnected; steps 1–11
   still work, and step 13 is simply deferred.
4. Connect the Nucleo to the host by USB.

### Identify the target

5. Confirm the probe and the part before writing anything:

   ```bash
   STM32_Programmer_CLI -c port=SWD
   ```

   Expect device ID **0x433**, flash size **512 KB**, target voltage ≈ **3.3 V**.
   If the device ID differs, **stop** — it is not an F401xE.

### Program

6. Build fresh, and prove what you built:

   ```bash
   make -C firmware/enr312/target clean && make -C firmware/enr312/target
   make -C firmware/enr312/target isolation
   sha256sum firmware/enr312/target/build/enr312_pendulum.elf
   ```

   The SHA must match the header of this document exactly. The build is
   byte-reproducible — the firmware carries a fixed version string rather than
   `__DATE__`/`__TIME__` precisely so that this check means something. A
   mismatch means the source changed; re-read it before flashing.

7. Program and verify:

   ```bash
   make -C firmware/enr312/target flash
   ```

   which runs `STM32_Programmer_CLI -c port=SWD -w <ENR312 elf> -v -rst`.
   Expect `File download complete` and `Verification OK`.

### Observe the boot — still no motor power

8. Open the ST-LINK virtual COM port at **115200 8N1**:

   ```bash
   picocom -b 115200 /dev/ttyACM0      # or: screen /dev/ttyACM0 115200
   ```

9. Press the black **RESET** button. Expect the banner, ending:

   ```
   THIS IS NOT THE VEHICLE FIRMWARE.
   State: SAFE. L6474 held in reset. No motion possible.
   ```

   Type `t`. Expect `state=SAFE faults=0x00`, and `ticks=` incrementing
   between successive `t` presses — that is the 500 Hz control ISR running.

   **If the banner does not appear, stop here.** Everything downstream assumes a
   working console, because the console is the only abort path.

### Encoder check — still no motor power

10. With the encoder connected: rotate the pendulum by hand and press `t`
    repeatedly. `pend=` must change smoothly and `raw=` must move.
    One full turn of the pendulum = **2400 counts** = 360.00°.

    * If `pend` moves the *wrong way*, set `ENR312_ENCODER_POLARITY` to `-1`
      in `firmware/enr312/inc/enr312_rig_config.h` and rebuild. **Do not**
      "fix" it by negating a gain somewhere downstream.
    * If `raw` never changes, the encoder is not wired, not powered, or the
      pull-ups are not reaching it. Do not proceed to motor power.

    * **Live view in MATLAB (read-only).** Close the serial terminal first —
      only one program can own the port — then in MATLAB:
      `addpath(genpath('matlab')); d = enr312_live_view('Port','/dev/ttyACM0');`
      It sends `r` (50 Hz CSV stream `D,ticks,rotor_mdeg,pend_mdeg,raw,faults,state`)
      and plots both angles. It never sends `a`/`s`/`+`/`-`, so it cannot move the motor.

### First motion — 12 V now required

> From here a motor can move. Keep a hand near the 12 V plug. `x` is abort and
> works from any state, at any time.

11. Connect the 12 V supply. Type `a`.

    * Expect `ARMED. Motor is energised and holding.` The motor will now
      resist being turned by hand. Nothing rotates on its own.
    * `ARM FAILED` means the L6474 did not answer over SPI — check
      pre-power checks R1/R2 (resistor population). Nothing has moved; safe.
    * Type `q` to read the L6474 STATUS register if you want detail.

12. Type `s` (RUNNING), then `+`.

    **Expected: the arm rotates a small amount in one direction and stops.**
    5° commanded at 200 steps/s = 44 microsteps ≈ 0.22 s of motion.

    Then type `-` to return. The arm should come back to where it started.

    Record what you actually observe:

    | Observation | Meaning | Action |
    |---|---|---|
    | moves ≈ **5°** | rotor gain 8.889 microsteps/deg is correct | conflict C-1 resolved in favour of UCLA |
    | moves ≈ **10°** | the Edukit manual's 17.778 is correct | set `ENR312_MOTOR_FULL_STEPS_PER_REV` to 400, rebuild |
    | moves the **wrong way** | DIR convention inverted | set `ENR312_ROTOR_POLARITY` to `-1`, rebuild |
    | **buzzes, does not turn** | motor phase pairs are crossed | power down; redo pre-power check M1 |
    | nothing at all | no drive current | check 12 V at the shield, and `q` for STATUS |

    Measure the actual displacement with a protractor. **This measurement is
    EXP001 Stage 9 and it is the point of the whole exercise** — it is the first
    hardware evidence in this project, and it settles a documented conflict that
    no amount of reading could.

13. Type `x`. Confirm `ABORT -> SAFE` and that the motor goes limp.

---

## If anything is unexpected

Type `x`. If the console is unresponsive, pull the 12 V plug — the Nucleo stays
powered over USB and the L6474 loses drive immediately.

The firmware will also abort itself, within one 2 ms control tick, on: L6474
FLAG (overcurrent / thermal / undervoltage), pendulum beyond ±120°, rotor beyond
±240°, or a missed control deadline.

## After this procedure

Record the results in `data/metadata/` per `docs/DATA_MANAGEMENT.md`, and update
`docs/hardware/WIRING_MAP.md` — the `PHYS` column can finally stop being "NO
everywhere" for the signals this procedure actually exercised.

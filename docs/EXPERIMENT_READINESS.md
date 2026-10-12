> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is `scripts/flash_ready_check.sh` and [`results/reports/`](../results/reports/).

# ENR312 release gate

Four states, deliberately separate. A target can be flash-ready while the
bench is not power-ready, and saying so is more useful than one blended verdict.

Last assessed: **2026-08-22**, after the operator completed the physical checks.

| Gate | State | What it means |
|---|---|---|
| **SOFTWARE BUILD READY** | ✅ **YES** | ENR312 target compiles and links with zero warnings from project code; 276 host checks pass; build is byte-reproducible. |
| **SOFTWARE FLASH READY** | ✅ **YES** | `.elf`, `.bin` and `.hex` exist, are isolated from BFMC/micro-ROS/FreeRTOS, and are pinned by SHA256 in `docs/experiments/EXP001/FIRST_FLASH.md`. |
| **HARDWARE POWER READY** | ✅ **YES — OPERATOR-VERIFIED** | The operator reports hardware inspection, electrical checks, wiring verification and encoder/electrical verification complete, and the rig ready for flashing. See the attestation note below. |
| **FIRST MOTION READY** | ✅ **YES** | Procedure: `docs/experiments/EXP001/FIRST_FLASH.md`. Not yet executed — no firmware has been flashed. |

## Evidence for the two green gates

```
make -C firmware/enr312/target                 -> build/enr312_pendulum.{elf,bin,hex}
                                                  FLASH 16 628 B (3.17 %)
                                                  RAM    2 396 B (2.44 %)
make -C firmware/enr312/target isolation       -> ISOLATION CLEAN
make -C firmware/enr312/target ioc-check       -> IOC AND CODE AGREE (14/14)
make -C firmware/enr312 test                   -> 276 checks, 0 failed
make -j$(nproc)                                -> BFMC unchanged: 142 092 / 1 752 / 94 128
```

## Hardware verification — provenance

**Status: OPERATOR-VERIFIED, 2026-08-22.** The operator states the physical
hardware and electrical checks are complete and the rig is ready for flashing.

Be precise about what that does and does not mean:

* It is an **operator attestation**, not a measurement recorded in this
  repository. The individual values called for by
  `docs/hardware/PRE_POWER_CHECKLIST.md` (encoder output voltages, resistor
  designators, phase-pair resistances, part numbers) were **not supplied**, so
  the checklist's record fields remain blank here.
* No measurement in this repository was taken by the assistant. Nothing in
  `docs/` should be read as instrument data.
* The distinction matters for traceability: a future reader can see that the
  gate was opened on the operator's authority, and can ask for the numbers.

The four items below were the blockers. They are reported cleared by the
operator; the repository holds no independent evidence for any of them.

1. ~~**Encoder 5 V tolerance.**~~ *(reported cleared)* The LPD3806 is 5 V open-collector. Whether PB4/PB5
   are `FT`-marked on the STM32F401RET6 is **UNKNOWN** in this repository
   (`docs/hardware/SOURCE_RECONCILIATION.md:160`), and whether the harness
   carries an external pull-up to +5 V has never been measured.
   → checklist E1–E3. **This one can destroy the MCU.**
2. ~~**IHM01A1 resistor population.**~~ *(reported cleared)* CS and SCK are resistor-selectable (R15/R25,
   R23/R24). The firmware assumes the factory default. If the board was
   re-populated, SPI will not answer and ARM will fail — harmless, but it must
   be known rather than discovered.
   → checklist R1–R2.
3. ~~**Motor phase pairing.**~~ *(reported cleared)* Which two conductors form a coil has not been
   measured. Crossed pairs make the motor buzz instead of turn.
   → checklist M1–M2.
4. ~~**Rig identity.**~~ *(reported cleared)* Shield, Nucleo and encoder part numbers have not been read
   off the hardware by anyone. The encoder's 600 PPR in particular is assumed.
   → checklist P1–P4.

Item 4 also settles the older open question of whether the rig is a
STEVAL-EDUKIT01 or the DC servo named in the course outline.

## What is explicitly NOT claimed

* **No firmware has been flashed to any MCU.** The pendulum image has never run.
* No measured hardware value appears anywhere in this repository.
* No ST-LINK is visible from the development environment (`st-info --probe` →
  *Found 0 stlink programmers*); the operator reports one attached to theirs.
* No hardware measurement of any kind exists in this repository.
* MATLAB has never executed here. All `matlab/` artifacts remain
  `DEFERRED — MATLAB EXECUTION ENVIRONMENT REQUIRED`; the numerical results
  quoted in the experiment records were reproduced in Python, not MATLAB.

## Experiment software status

| | Control core | Host checks | Target integration |
|---|---|---|---|
| EXP001 | implemented | 38 + 49 + 32 | ✅ in the target image |
| EXP002 | implemented | 39 + 27 | ✅ |
| EXP003 | implemented | 43 | ✅ |
| EXP004 | implemented | 12 | ✅ |
| EXP005 | implemented | 36 | ✅ |

All five link into `enr312_pendulum.elf`. Total control-core cost: **7 347 B**
flash, **0 B** static RAM (all state is caller-owned).

None of the five has hardware data. Software-complete is not experiment-complete
— see docs/ENGINEERING_STANDARDS.md §6.

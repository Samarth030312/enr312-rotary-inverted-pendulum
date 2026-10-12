> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`ENR312_WIRING.md`](ENR312_WIRING.md).

# Signal Path — ENR312 Rotary Inverted Pendulum

**Date:** 2026-08-20 · **Revision:** `73c7d31`

Traces every signal from physics to physics. **Status of the physical segments: NOT
VERIFIED.** The software segments are implemented and tested; the hardware segments are
candidates.

---

## 1. Sensing path — pendulum angle `θ`

```
 PHYSICS      pendulum rotates about the arm-tip axis
    │
    │  600 slots/rev disc, two masks 90 deg out of phase
    ▼
 ENCODER      LPD3806-600BM-G5-24C, open collector, 5 V supply     [DOC-REF]
    │         A and B square waves in quadrature
    │  ⚠ level set by whatever pull-up exists -- POWER_SAFETY.md section 4
    ▼
 WIRING       Green/White -> PB4/PB5                    ⚠ ASSIGNMENT UNKNOWN
    │
    ▼
 STM32 PIN    PB4 = TIM3_CH1, PB5 = TIM3_CH2, AF2, internal pull-up   [DOC-REF]
    │
    ▼
 PERIPHERAL   TIM3 in TIM_ENCODERMODE_TI12 (X4), 16-bit, ARR 65535    [DOC-REF]
    │         X4 is a FIRMWARE choice, not an encoder property:
    │         the same encoder yields 600/1200/2400 counts per rev
    ▼
 DRIVER       *** DOES NOT EXIST -- open item OI-3 ***
    │         needs: TIM3 init + HAL_TIM_Encoder_Start
    ▼
 PROCESSING   enr312_encoder.c                                    [IMPLEMENTED, TESTED]
    │         wrapped 16-bit difference (eq. 8), 64-bit accumulate (eq. 9)
    │         theta = polarity * (C - C0) * 2*pi/2400
    │         q = 2.618 mrad/count;  sigma_theta = 0.0433 deg
    │         aliasing threshold 6827 rev/s -- unreachable
    ▼
 CONTROL      enr312_pd.c / exp003 / exp005                       [IMPLEMENTED, TESTED]
```

**Blocking gaps:** wiring assignment (⚠), encoder logic level (⚠), and the missing driver
layer (**OI-3**).

---

## 2. Actuation path — rotor angle `phi`

```
 CONTROL      u = K_rotor*(phi_cmd - phi) + K_pend*(theta_cmd - theta)  [IMPLEMENTED]
    │         single saturation applied to the SUM
    ▼
 COMMAND      enr312_rotor.c: microsteps, travel limits, ARR from step rate
    │         ARR = round(84e6 / 1024 / f_step) - 1
    ▼
 DRIVER       *** DOES NOT EXIST -- open item OI-3 ***
    │         needs: SPI1 + L6474 register config + TIM2 step ISR
    ▼
 STM32 PINS   PC7 STCK (plain GPIO toggled in ISR, NOT hardware PWM)   [DOC-REF]
    │         PA8 DIR, PA9 nRESET, PA10 nFLAG, PB6 nCS
    │         PA5/PA6/PA7 SPI1 SCK/MISO/MOSI
    ▼
 L6474        1/16 microstepping, TVAL 800 mA, OCD 2250 mA           [DOC-REF]
    │
    ▼
 MOTOR        NEMA-17 17HS19-2004S, 200 full steps/rev               [DOC-REF]
    │         ⚠ lead colour order unverified; reference warns of vendor reversal
    ▼
 MECHANICS    coupling motor -> rotor arm                    *** UNKNOWN ***
    │         no gearbox mentioned; direct drive ASSUMED, not stated
    ▼
 PHYSICS      arm rotates; r = 0.14 m
```

### ⚠ CONFLICT — the actuator scale is disputed

| Source | Rotor **control** gain | Rotor **measurement** gain |
|---|---|---|
| Edukit Manual Table 2 | **17.778 steps/°** (0.0563 °/step, 6400/rev) | **8.889 steps/°** (0.1126 °/step, 3200/rev) |
| UCLA reference code | `STEPPER_CONTROL_POSITION_STEPS_PER_DEGREE = 8.888889` | `STEPPER_READ_POSITION_STEPS_PER_DEGREE = 8.888889` |
| **This project (EXP001)** | 8.888889 steps/° | 8.888889 steps/° |

The manual asserts a **factor of two** between commanding and reading; the reference code
uses the **same** value for both, and EXP001 followed the code.

**If the manual is right, every commanded rotor angle in EXP001–EXP005 is out by 2×.**

This is `UNKNOWN — MUST BE PHYSICALLY VERIFIED`, and EXP001 prediction **P1** measures
exactly it: command +45°, measure the physical arm angle with a protractor. A reading of
**22.5°** would confirm the manual and invalidate the current constant.

> Note the manual's own wording is internally inconsistent — it says the position is *"read
> with a factor of two greater gain"* while tabulating the read gain as **half** the
> control gain. **Do not resolve this from documents. Measure it.**

---

## 3. Rotor angle `phi` — there is no sensor

```
 phi is COMMANDED AND REMEMBERED, never measured.
 The feedback path is an integer accumulator in enr312_rotor.c.
```

Valid only while **no step is lost**. There is no error signal anywhere in the system that
could reveal step loss. EXP001 prediction **P3** (ten zero-net-motion cycles, read against
an index mark) is the only check that exists.

---

## 4. Telemetry path

```
 SEQUENCER  exp001/exp003/exp005 -> ENR312_ExpNNN_FormatCsv()      [IMPLEMENTED, TESTED]
    ▼
 UART       USART2 -> ST-LINK virtual COM -> host        *** DRIVER MISSING, OI-3 ***
    ▼
 HOST       data/raw/EXPnnn/*.csv  (immutable)
    ▼
 ANALYSIS   scripts/expNNN_process_measurements.py       [IMPLEMENTED, SELF-TESTED]
```

**Bandwidth sanity:** ~80 B/sample × 500 Hz ≈ 40 kB/s → needs ≥ 400 kbaud. The inherited
vehicle firmware already runs USART2 at 460800, so the rate is achievable on this board.
**Not verified for the pendulum application.**

---

## 5. Signals required per experiment

| Experiment | `θ` (encoder) | `φ` (commanded) | `u` | Excitation | Notes |
|---|---|---|---|---|---|
| **EXP001** | ✔ | ✔ | ✔ | rotor steps ±45°, ±90° | Pendulum free, motor idle for the sensing phase |
| **EXP002** | — | ✔ | ✔ | rotor step + load disturbance | **Pendulum removed or clamped** — rotor loop only |
| **EXP003** | ✔ | ✔ | ✔ | rotor step, suspended | Both loops active |
| **EXP004** | ✔ | ✔ | ✔ | rotor step, suspended | Same acquisition as EXP003; the *analysis* differs |
| **EXP005** | ✔ | ✔ | ✔ | rotor step, **inverted** | Highest risk; second person required |

**No experiment requires micro-ROS.** The laboratory telemetry is a plain CSV line over
UART.

---

## 6. Where the path is broken today

| Segment | Status |
|---|---|
| Physics → encoder | `DOC-REF`, not verified |
| Encoder → STM32 pin | ⚠ **assignment UNKNOWN**, ⚠ **level UNKNOWN** |
| STM32 pin → TIM3 | `DOC-REF` |
| TIM3 → driver | ⛔ **DOES NOT EXIST (OI-3)** |
| Driver → processing | ✔ implemented and tested |
| Processing → control | ✔ implemented and tested |
| Control → command model | ✔ implemented and tested |
| Command → L6474 driver | ⛔ **DOES NOT EXIST (OI-3)** |
| L6474 → motor | `DOC-REF`, ⚠ lead order unverified |
| Motor → arm | ⚠ **coupling UNKNOWN** |
| **Actuator scale** | ⚠ **DISPUTED ×2 — see §2** |

**Everything in software is done. Everything that touches copper is not.**

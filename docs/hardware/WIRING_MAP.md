> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`ENR312_WIRING.md`](ENR312_WIRING.md).

# Wiring Map — ENR312 Rotary Inverted Pendulum

> **2026-10-11:** for wiring the rig and the step-by-step electrical check, use
> [`ENR312_WIRING.md`](ENR312_WIRING.md) (diagrams in `figures/`). This page is the
> earlier candidate map and its evidence trail; its §0 predates the ENR312 target IOC.

**Date:** 2026-08-20 · **Revision:** `73c7d31`

> # ⛔ THIS IS A CANDIDATE MAP. IT IS NOT VERIFIED. DO NOT WIRE FROM IT ALONE.
>
> **PHYSICALLY VERIFIED: NO — for every single row.**
>
> This document exists so that a human can *check* connections against a written
> reference, not so that connections can be made without checking. Its purpose is to make
> it impossible to burn hardware because software guessed a connection.

---

## 0. The single most important fact on this page

**This project's `odyssix_stm32_core.ioc` does NOT describe the pendulum rig.**

It describes an inherited **BFMC autonomous-vehicle** application: BNO085 IMU on I²C1,
ESC and steering-servo PWM on TIM2, micro-ROS over USART2. It contains **no encoder, no
stepper driver, and no SPI peripheral**.

**Consequence:** *no* pendulum pin in this document can carry the status
`VERIFIED AGAINST .IOC`, because the `.ioc` has nothing to verify it against. Every
pendulum pin below is `DOCUMENTED FROM UCLA REFERENCE` only — a project for a *different
rig* that happens to use the same shield and MCU.

That is a strong prior. It is not verification.

---

## 1. Verification-status vocabulary

| Status | Meaning | Any rows? |
|---|---|---|
| `DOC-REF` | Documented from the UCLA reference project | **all pendulum signals** |
| `DOC-COURSE` | Documented from an ENR312 course document | a few |
| `VER-IOC` | Cross-checked against **this** project's `.ioc` | **none** — the `.ioc` is the vehicle |
| `VER-FW` | Cross-checked against **this** project's firmware | **none** — no board layer exists (OI-3) |
| `PHYS` | **Physically verified on the rig** | **NONE. This column is NO everywhere.** |

---

## 2. SIGNAL connections — candidate map

All rows: **`PHYS = NO`**. Logic level on the STM32 side is **3.3 V** unless stated.

| STM32 pin | GPIO / AF config | Peripheral | Timer / ch | DMA | IRQ | External device | Device pin | Signal | Dir | Pull | Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **PB4** | `AF2`, `GPIO_MODE_AF_PP`, **`GPIO_PULLUP`** | TIM3 | TIM3_CH1 | none | none | LPD3806 encoder | ch A (**Green**, per ref) | `ENC_A` | in | **internal pull-up** | UCLA `stm32f4xx_hal_msp.c:214–227`; `main.c:97–98` | `DOC-REF` |
| **PB5** | `AF2`, `GPIO_MODE_AF_PP`, **`GPIO_PULLUP`** | TIM3 | TIM3_CH2 | none | none | LPD3806 encoder | ch B (**White**, per ref) | `ENC_B` | in | **internal pull-up** | as above | `DOC-REF` |
| **PC7** | `GPIO_MODE_OUTPUT_PP`, **not AF** | GPIO | paced by TIM2 update IRQ | none | TIM2 | L6474 / IHM01A1 | STCK | `STEP_CLK` | out | none | UCLA `x_nucleo_ihm01a1_stm32f4xx.h:170–172`; msp `:149` | `DOC-REF` |
| **PA8** | `GPIO_MODE_OUTPUT_PP` | GPIO | — | none | none | L6474 | DIR | `DIR` | out | none | BSP `:185–187` | `DOC-REF` |
| **PA9** | `GPIO_MODE_OUTPUT_PP` | GPIO | — | none | none | L6474 | STBY/RESET | `nRESET` (active low) | out | none | BSP `:200–202` | `DOC-REF` |
| **PA10** | `GPIO_MODE_INPUT` | GPIO | — | none | EXTI (ref) | L6474 | FLAG | `nFLAG` (active low) | in | **UNKNOWN** | BSP `:165–167` | `DOC-REF` |
| **PB6** | `GPIO_MODE_OUTPUT_PP` | GPIO | — | none | none | L6474 | CS | `nCS` | out | none | BSP `:205–207` | `DOC-REF` |
| **PA5** | `AF5` | SPI1 | — | none | none | L6474 | SCK | `SPI_SCK` | out | none | BSP `:236–239` | `DOC-REF` |
| **PA6** | `AF5` | SPI1 | — | none | none | L6474 | MISO | `SPI_MISO` | in | none | BSP `:243–246` | `DOC-REF` |
| **PA7** | `AF5` | SPI1 | — | none | none | L6474 | MOSI | `SPI_MOSI` | out | none | BSP `:249–252` | `DOC-REF` |
| PA2 / PA3 | `AF7` | USART2 | — | opt. | USART2 | ST-LINK VCP → host | — | telemetry | bi | none | Nucleo convention + this repo's `.ioc` | `DOC-REF` |

### Notes that matter

- **PC7 is a plain GPIO, not a timer output.** The reference initialises it
  `GPIO_MODE_OUTPUT_PP` with the alternate-function line **commented out**
  (`stm32f4xx_hal_msp.c:149–152`). The timer runs only as a periodic interrupt source and
  the ISR toggles the pin. Wiring it expecting a hardware PWM output would be wrong.
- **Encoder A/B ↔ Green/White is ambiguous.** The reference says *"White → GPIO Dir3,
  Green → GPIO Dir2"* — it names shield silkscreen positions, not TIM3 channels. **The
  mapping of Green/White onto PB4/PB5 is an inference and is UNKNOWN.** Swapping them
  inverts the measured angle sign — which EXP001 P2b measures anyway, so **do not guess:
  wire it, then measure the sign.**
- **PA10 pull configuration is UNKNOWN.** `nFLAG` is open-drain on the L6474; whether a
  pull-up is provided on the shield or must be enabled internally is not recorded.

---

## 3. POWER connections

| Rail | Nominal | Source | Consumers | Max rating | Evidence | Status |
|---|---|---|---|---|---|---|
| **+12 V** | 12 V DC | Edukit PSU (110/220 V AC mains) | IHM01A1 motor bridge → stepper | **UNKNOWN** | handout; manual | `DOC-COURSE` |
| **+5 V** | 5 V | USB, or Nucleo regulator | Encoder supply (Red lead) | **UNKNOWN** | UCLA `main.c:95` | `DOC-REF` |
| **+3.3 V** | 3.3 V | Nucleo on-board regulator | STM32 I/O | **UNKNOWN** | STM32F4 family | **UNKNOWN** |
| USB 5 V | 5 V | Host PC or USB PSU | Nucleo logic + ST-LINK | **UNKNOWN** | manual | `DOC-COURSE` |

**PSU connector polarity: UNKNOWN — MUST BE PHYSICALLY VERIFIED with a multimeter.**

## 4. GROUND

| Field | Value | Evidence | Status |
|---|---|---|---|
| Ground topology | **UNKNOWN** — not documented anywhere in this repository | — | **UNKNOWN** |
| Encoder ground | Black lead → GND | UCLA `main.c:96` | `DOC-REF` |
| Motor-supply ground ↔ logic ground | **Assumed common via the shield headers. NOT CONFIRMED.** | — | **UNKNOWN — CRITICAL** |

> **A common ground between the 12 V motor return and the STM32 logic ground is REQUIRED
> for the encoder and driver signals to have a defined reference — and its absence is not
> visually obvious.** Confirm continuity between the PSU negative terminal and a Nucleo
> GND pin (power off, multimeter) before connecting any signal line.

---

## 5. Conflicts with this project's own `.ioc` — read before flashing

The inherited vehicle firmware and the pendulum rig **cannot share a pin map**. If the
IHM01A1 is fitted and the *vehicle* firmware is running, these pins are driven for two
different purposes:

| Pin | Vehicle firmware (this `.ioc`) | Pendulum rig (reference) | Conflict |
|---|---|---|---|
| **PB4** | EXTI4, BNO085 interrupt, pull-up, falling edge | TIM3_CH1 encoder A | **YES** |
| **PA5** | GPIO output, LD2 heartbeat | SPI1_SCK to L6474 | **YES** |
| **PA9** | USART1_TX | L6474 nRESET | **YES** |
| **PA10** | USART1_RX | L6474 nFLAG | **YES** |
| **PA0 / PA1** | TIM2_CH1/CH2 servo + ESC PWM | TIM2 used as the step-clock timebase | **YES (peripheral)** |
| PB5, PB6, PC7, PA6, PA7, PA8 | unused | encoder B, nCS, STCK, MISO, MOSI, DIR | no |

> ### ⛔ DO NOT FLASH THE VEHICLE FIRMWARE WITH THE IHM01A1 FITTED
> `build/odyssix_stm32_core.elf` drives **PA5 as a GPIO output** (LD2 heartbeat) while the
> shield connects PA5 to the L6474's **SPI clock**, and drives **PA9/PA10 as USART1** into
> the L6474's **nRESET/nFLAG**. Two outputs may end up connected. Flash only firmware
> written for the pendulum pin map.
>
> **That firmware does not exist yet — open item OI-3.**

---

## 5b. Wire colours — operator-supplied EDUKIT convention (2026-08-20)

The following conventions were supplied by the operator as the expected EDUKIT wiring.
Class: **OPERATOR-STATED** — a new evidence class, ranking with COURSE-DOCUMENTED but not
yet confirmed against the physical harness.

### Motor phases

| Terminal | Operator-stated colour | UCLA reference | Agreement |
|---|---|---|---|
| **M1A** | **red** | `+A` = Red | ✔ **agree** |
| **M1B** | **blue** | `−A` = Blue | ✔ **agree** |
| **M2A** | **yellow** | `−B` = **Green** | ⚠ **CONFLICT** |
| **M2B** | **orange** | `+B` = **Black** | ⚠ **CONFLICT** |

> **Phase 1 reconciles; phase 2 does not.** Both sources pair red+blue as one phase, which
> is meaningful independent agreement. But the second phase is green/black in the UCLA
> reference and yellow/orange in the operator's convention — **entirely different
> conductors**.
>
> Most likely explanation: different motor variants or cable harnesses between the UCLA rig
> and this one. **Not resolvable from documents.** Verify by winding continuity: the two
> conductors of a phase show low resistance to each other and open circuit to the other
> phase (`HARDWARE_PROCEDURE` Stage 2).
>
> **A swapped phase pair reverses rotation; a wire swapped *between* phases prevents
> stepping and can stall the motor.** Measure, do not assume.

Recall the UCLA source also warns: *"motors have been received from the vendor showing
reversal of Motor White and Motor Red"* — a third colour set again (white). Treat all
motor colour mappings as unverified until measured.

### Encoder — **fully reconciled**

| Lead | Operator-stated | UCLA reference | Agreement |
|---|---|---|---|
| **E1** | **red — positive** | Red → 5 V | ✔ **agree** |
| **E2** | **black — ground** | Black → GND | ✔ **agree** |
| **E3** | **white — phase 1** | White → "GPIO Dir3" | ✔ **agree** |
| **E4** | **green — phase 2** | Green → "GPIO Dir2" | ✔ **agree** |

> **This resolves a previously-open UNKNOWN.** Two independent sources now agree on all
> four encoder leads, and the operator's statement supplies the phase ordering the UCLA
> comment left implicit.
>
> **One step remains:** *phase 1* and *phase 2* still have to be mapped onto **TIM3_CH1
> (PB4)** and **TIM3_CH2 (PB5)** — i.e. which is channel A and which is B. Getting that
> backwards inverts the measured angle sign. It is not worth resolving on paper: **EXP001
> P2b measures the resulting sign directly** and defines the convention from the
> measurement.

### Supply implication, unchanged

E1/E2 confirm the encoder is a **5 V-powered, open-collector** device. The question of
whether PB4/PB5 tolerate 5 V remains **UNKNOWN** — see `POWER_SAFETY.md` §4. Colour
agreement does not change the electrical risk.

---

## 6. Summary of what is and is not known

| Category | Count |
|---|---|
| Signal connections documented | 11 |
| …`VERIFIED AGAINST .IOC` | **0** |
| …`VERIFIED AGAINST FIRMWARE` | **0** |
| …**`PHYSICALLY VERIFIED`** | **0** |
| Explicit `UNKNOWN` entries | 9 |
| Pin conflicts with the inherited vehicle firmware | 5 |

### The `UNKNOWN`s, restated so none is lost

1. Encoder phase 1 / phase 2 → PB4/PB5 (channel A vs B). *Lead colours now reconciled
   (§5b); only the channel assignment remains, and EXP001 P2b measures it.*
2. Encoder output logic level (open collector; set by whatever pull-up exists).
3. **Whether PB4/PB5 are 5 V-tolerant** — no STM32F401 datasheet in the repository.
4. PA10 (`nFLAG`) pull configuration.
5. Ground topology, and whether motor and logic grounds are actually common.
6. PSU connector type and **polarity**.
7. All maximum voltage/current ratings.
8. Whether an *external* encoder pull-up is fitted, and to which rail.
9. **Motor phase 2 colours: yellow/orange (operator) vs green/black (UCLA) — CONFLICT.**
   Phase 1 (red/blue) agrees. Resolve by winding-continuity measurement.

**Every one must be resolved by inspection or datasheet before power-up.**

---

## UPDATE 2026-08-22 — the map is now implemented in firmware

Every signal in the table above is implemented in the **ENR312 target**, with a
`file:line` citation into `<UCLA Edukit project>/` for each pin:

* pin map          `firmware/enr312/target/inc/enr312_board.h`
* configuration    `firmware/enr312/target/src/enr312_board.c`
* design record    `firmware/enr312/target/enr312.ioc`
* consistency      `make -C firmware/enr312/target ioc-check` (14/14 agree)

The `VER-IOC` and `VER-FW` rows of the status legend above are **no longer
"none"** — but note what changed and what did not:

| Column | Before | Now |
|---|---|---|
| `DOC-REF` | all pendulum signals | unchanged |
| `VER-IOC` | none — "the `.ioc` is the vehicle" | **all signals**, against `enr312.ioc` |
| `VER-FW` | none — no board layer exists (OI-3) | **all signals** — OI-3 is closed |
| `PHYS` | **NO everywhere** | **still NO everywhere** |

### `PHYS` column — updated 2026-08-22

The operator reports the physical wiring and electrical checks **complete**, and
the rig ready for flashing. The `PHYS` status for the pendulum signals is
therefore **OPERATOR-VERIFIED**.

That is deliberately not the same word as `PHYS`-measured. No per-signal
measurement was supplied to the repository, so the table rows above are left as
`DOC-REF` with this note governing them, rather than silently promoted. If the
continuity and voltage readings are recorded later, promote the individual rows
then — `docs/hardware/PRE_POWER_CHECKLIST.md` holds the fields.

Nothing in this file was measured by the assistant.

Blocker **OI-3** ("board-support layer written") is closed: the layer exists,
builds, links and is byte-reproducible.

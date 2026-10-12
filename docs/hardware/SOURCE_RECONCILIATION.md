> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`ENR312_WIRING.md`](ENR312_WIRING.md).

# Source Reconciliation — Physical ENR312 Rotary Inverted Pendulum

**Date:** 2026-08-20 · **Revision:** `99360ec` · **READ-ONLY.** No firmware, `.ioc` or
experiment was modified.

> # PHYSICALLY-VERIFIED: **NO** — for every row in this document.
> Nothing here has been seen. This reconciles documents against each other; it does not
> verify hardware.

---

## 0. Evidence classes

| Class | Meaning |
|---|---|
| **OFFICIAL-ST-DOCUMENTED** | Retrieved from an ST document during this pass, and quoted |
| **COURSE-DOCUMENTED** | ENR312 manual / study guide / handout in this repository |
| **REFERENCE-DOCUMENTED** | UCLA Edukit project source in this repository |
| **INFERRED** | Follows from two or more of the above by a stated step |
| **PHYSICALLY-VERIFIED** | **Used nowhere in this document** |

### Source availability — what was actually obtained

| # | Source | Status |
|---|---|---|
| 1 | `ENR312.pdf` | ✔ in repo |
| 2 | `Edukit_..._Manual.pdf` | ✔ in repo |
| 3 | `Edukit_..._StudyGuide.pdf` | ✔ in repo |
| 4 | `Edukit_Student_Lab_Handout.pdf` | ✔ in repo |
| 5 | UCLA reference project | ✔ in repo |
| 6 | `edukit_model_starter.m` | ✔ in repo — **contains no hardware information** (control-model only) |
| 7 | **NUCLEO-F401RE official ST docs (UM1724, STM32F401 datasheet)** | ✘ **NOT RETRIEVED** — repeated fetch timeouts |
| 8 | **X-NUCLEO-IHM01A1 official ST doc (UM1857)** | ✔ **RETRIEVED IN FULL** (DocID027377 Rev 1) |

> **This asymmetry governs the whole document.** UM1857 gives the **Arduino connector pin**
> for every L6474 signal — officially. Translating an Arduino pin to an **STM32 port pin**
> requires UM1724, **which was not retrieved**. Every STM32 pin below is therefore
> `INFERRED`, never `OFFICIAL-ST-DOCUMENTED`.
>
> I did not write ST pin tables from memory. A remembered pinout labelled as documented
> would be exactly the fabricated provenance this exercise exists to prevent.

---

## 1. The headline result

**UM1857 independently corroborates the UCLA reference pin map.**

Before this pass, every pendulum pin rested on one source: a UCLA project for a different
rig. UM1857 now supplies the Arduino-connector position of each L6474 signal from ST
itself. Under the standard Nucleo-64 Arduino mapping, those positions land on **exactly
the STM32 pins the UCLA BSP declares** — eight for eight.

Two independent sources agreeing raises confidence materially. It is still not
verification, and one new configuration risk appeared (§4).

---

## 2. Signal connections — reconciled

`VS` = motor supply. STM32-side logic assumed 3.3 V (**not confirmed — §6**).

| Signal | ST connector + pin (UM1857) | Arduino name (INFERRED) | STM32 pin (UCLA) | Direction | Voltage | Confidence | Contradictions |
|---|---|---|---|---|---|---|---|
| L6474 `STBY\RESET` | **CN5 pin 1** | D8 | **PA9** | out | 3.3 V (assumed) | ST + REF agree | none |
| `PWM1` (step clock) | **CN5 pin 2** | D9 | **PC7** | out | 3.3 V (assumed) | ST + REF agree | **generation method — §3** |
| `SPI CS` | **CN5 pin 3** *(default)* | D10 | **PB6** | out | 3.3 V (assumed) | ST + REF agree | **resistor-selectable — §4** |
| `SPI MOSI` | **CN5 pin 4** | D11 | **PA7** | out | 3.3 V (assumed) | ST + REF agree | none |
| `SPI MISO` | **CN5 pin 5** | D12 | **PA6** | in | 3.3 V (assumed) | ST + REF agree | none |
| `SPI SCK` | **CN5 pin 6** *(default)* | D13 | **PA5** | out | 3.3 V (assumed) | ST + REF agree | **resistor-selectable — §4**; also LD2 |
| L6474 `FLAG` output | **CN9 pin 3** | D2 | **PA10** | in | 3.3 V (assumed) | ST + REF agree | pull-up **UNKNOWN — §7** |
| `DIR1` | **CN9 pin 8** | D7 | **PA8** | out | 3.3 V (assumed) | ST + REF agree | table-layout caveat below |
| Ground | CN5 pin 7; CN6 pins 6, 7 | GND | GND | — | 0 V | **OFFICIAL-ST** | none |
| `VDD` | CN6 pin 2 | IOREF | — | — | **UNKNOWN** | **OFFICIAL-ST** | §6 |

**`DIR1` caveat.** UM1857's Table 1 places `DIR1` on "pin 8" in a row whose connector
label is rendered ambiguously by PDF text extraction (the label spans rows). CN6 pin 8 on
a Nucleo-64 power header is `VIN`, which cannot carry `DIR1`; CN9 pin 8 is D7. **CN9 pin 8
is therefore the reading**, and it is corroborated by the UCLA BSP declaring `DIR_1 = PA8`
(= D7). `INFERRED`, with the basis stated.

### The encoder — no ST document applies

The encoder is **not part of the ST product**. UM1857 says nothing about it, so no row
below can ever be `OFFICIAL-ST-DOCUMENTED`.

| Signal | Connector | STM32 pin | Direction | Voltage | Evidence | Confidence | Contradictions |
|---|---|---|---|---|---|---|---|
| Encoder `A` | **UNKNOWN** — no connector documented | **PB4** (TIM3_CH1, AF2) | in | **UNKNOWN — §5** | UCLA `stm32f4xx_hal_msp.c:214–227` | REFERENCE only | **lead colour ↔ channel unresolved** |
| Encoder `B` | **UNKNOWN** | **PB5** (TIM3_CH2, AF2) | in | **UNKNOWN — §5** | as above | REFERENCE only | as above |
| Encoder `+5 V` | **UNKNOWN** | — | — | 5 V | UCLA `main.c:95` ("Red → 5V") | REFERENCE only | none |
| Encoder `GND` | **UNKNOWN** | — | — | 0 V | UCLA `main.c:96` ("Black → GND") | REFERENCE only | none |
| Encoder index `Z` | — | — | — | — | not referenced anywhere | **UNKNOWN** | may not exist |

**Unresolvable from the sources:** UCLA states *"White → GPIO Dir3, Green → GPIO Dir2"* —
silkscreen positions, not TIM3 channels. **Which lead is A and which is B cannot be
determined from any available document.** It is also not worth resolving on paper: EXP001
prediction **P2b** measures the resulting sign directly.

---

## 3. Contradiction: how the step clock is generated — **RESOLVED**

| Source | Statement |
|---|---|
| UM1857 §2 | *"the step clock for each L6474 device is generated by a **PWM**"* |
| UCLA `stm32f4xx_hal_msp.c:149–152` | STCK pin initialised `GPIO_MODE_OUTPUT_PP`, the `Alternate` line **commented out**; TIM2 runs in PWM+IT mode purely as an interrupt source and the ISR toggles the pin |

**Resolution: not a wiring contradiction.** Both drive the *same physical pin* (CN5 pin 2
→ PC7). They differ only in *how the firmware produces edges*: ST's reference design uses
the timer's PWM output; UCLA replaced it with a software toggle — necessarily, because it
reassigned TIM3 to the encoder and PC7 is not a TIM2 alternate-function pin.

**Consequence for wiring: none.** **Consequence for firmware: every step edge costs an
interrupt.** Already recorded in `shared/parameters/edukit01_rig.yaml`
(`actuator.step_clock`).

---

## 4. ⚠ NEW FINDING — SPI CS and SCK are resistor-selectable

UM1857 §2.1, quoted:

> **Table 3: Chip select line selection**
> | R15 | R25 | CS line |
> |---|---|---|
> | Not mounted | 0R | **CN5 pin 3, CN10 pin 17 (default)** |
> | 0R | Not mounted | CN8 pin 3, CN7 pin 32 |
>
> **Table 4** *(SPI clock; the document's caption repeats "Chip select" — an ST typo)*
> | R23 | R24 | line |
> |---|---|---|
> | 0R | Not mounted | **CN5 pin 6, CN10 pin 9 (default)** |
> | Not mounted | 0R | CN9 pin 4, CN10 pin 31 |

**The SPI chip-select and clock pins are not fixed.** They are set by 0 Ω resistors on the
shield. The UCLA map (`CS = PB6`, `SCK = PA5`) corresponds to the **factory default** in
both tables.

**If this rig's board has the alternative resistors fitted, the pin map is wrong** — CS
would be on CN8 pin 3 and SCK on CN9 pin 4. Nothing in the repository records which
resistors are fitted.

> `UNKNOWN — MUST BE PHYSICALLY VERIFIED`: inspect R15/R25 and R23/R24 on the shield and
> record which are mounted.

UM1857 §2.2 additionally states the single-motor default mounts **R1, R4, R7, R12**
(`PWM1\DIR1`), and that *"board configurations for multi-motor setups must be changed
before stacking"*. A single-motor rig should be at that default — **also unverified**.

---

## 5. ⚠ Encoder A/B voltage — **UNRESOLVED, and the highest-consequence gap**

| Fact | Source | Class |
|---|---|---|
| Encoder supplied at **5 V** | UCLA `main.c:95` | REFERENCE |
| Outputs are **open collector**, require a pull-up | UCLA `main.c:101` | REFERENCE |
| UCLA enables the STM32 **internal** pull-up (→ 3.3 V) | `hal_msp.c:224` | REFERENCE |
| **Are PB4/PB5 5 V-tolerant?** | — | **UNKNOWN** |

The STM32F401 datasheet was **not retrieved** this pass. A web search returned only the
generic remark that *"most GPIO pins on STM32 MCUs are 5V tolerant"* — **that is not
adequate evidence for a decision that can destroy the MCU**, and it is not recorded here
as evidence.

**Open-collector means the high level is set by whatever pull-up exists.** Internal
pull-up → 3.3 V, safe. An *external* pull-up to the 5 V rail → **5 V into the pin**.

> `UNKNOWN — MUST BE PHYSICALLY VERIFIED`
> 1. Obtain the STM32F401xD/xE datasheet; record whether PB4/PB5 are marked `FT`.
> 2. Inspect the rig for an external pull-up; record its value and rail.
> 3. Measure encoder A/B idle-high with the MCU **disconnected**.
>
> Procedure already written: `docs/experiments/EXP001/HARDWARE_PROCEDURE.md` Stage 3.

---

## 6. Power — reconciled where possible

| Item | Value | Source | Class | Contradictions |
|---|---|---|---|---|
| **Motor supply range `VS`** | **8 V – 45 V** | UM1857 §1 | **OFFICIAL-ST** | none — resolves a previous UNKNOWN |
| **Motor phase current** | **up to 3 A rms** | UM1857 §1 | **OFFICIAL-ST** | none |
| **Motor supply entry** | **CN1 pin 1 = VS, pin 2 = ground** | UM1857 §1 | **OFFICIAL-ST** | none |
| Supply used by the Edukit | **12 V / 1 A** | StudyGuide §"Under the hood"; handout | COURSE | consistent — 12 V is inside 8–45 V |
| Mains input to PSU | 110 V or 220 V AC | Manual | COURSE | none |
| Nucleo logic power | USB 5 V (or USB adapter) | Manual | COURSE | none |
| **Power-OK / fault LEDs** | green = power OK, red = fault, both light on correct supply | UM1857 §1 step 2 | **OFFICIAL-ST** | **useful bring-up check — see §9** |
| `VDD` / `IOREF` on CN6 pin 2 | present | UM1857 Table 1 | OFFICIAL-ST | value **UNKNOWN** |
| STM32 logic level | 3.3 V | — | **UNKNOWN** | not confirmed from an ST source this pass |
| PSU connector type / **polarity** | — | — | **UNKNOWN** | destructive risk |
| PSU current rating on the label | — | — | **UNKNOWN** | StudyGuide says 1 A; confirm on the unit |

**Resolved this pass:** the motor-supply range, phase-current limit and supply entry point
were `UNKNOWN` in `POWER_SAFETY.md`. They are now **OFFICIAL-ST-DOCUMENTED**. 12 V sits
comfortably inside 8–45 V, and 1 A is well under 3 A rms.

**Still UNKNOWN:** connector polarity, STM32 logic-level confirmation, `IOREF` voltage, and
every absolute-maximum rating.

---

## 7. Fault / emergency signals

| Signal | Connector | STM32 | Behaviour | Class | Contradiction |
|---|---|---|---|---|---|
| L6474 `FLAG` | **CN9 pin 3** | PA10 | active low; overcurrent, thermal, undervoltage | ST (connector) + REF (pin) | none |
| Fault LED (red) | on-shield | — | lights on fault | **OFFICIAL-ST** | none |
| Power-OK LED (green) | on-shield | — | lights when supplied | **OFFICIAL-ST** | none |
| `FLAG` pull-up | — | — | **UNKNOWN** — open-drain; whether the shield provides one is not documented | **UNKNOWN** | — |
| Hardware E-stop | — | — | **none exists** | — | — |

StudyGuide corroborates the protection set: *"overcurrent detection, thermal shutdown,
undervoltage lockout — it will flag a fault pin if something is wrong."* (COURSE)

> **There is no hardware emergency stop.** The 12 V supply switch is the only one, which is
> why `POWER_SAFETY.md` §8 requires it within the operator's reach. Travel limits are
> software-only.

---

## 8. Motor phases

| Terminal | Lead colour | Source | Class | Contradiction |
|---|---|---|---|---|
| −A | Blue (**White** on extension cable) | UCLA `main.c:81,90` | REFERENCE | **see below** |
| +A | Red | UCLA `main.c:82` | REFERENCE | **see below** |
| −B | Green | UCLA `main.c:83` | REFERENCE | none |
| +B | Black | UCLA `main.c:84` | REFERENCE | none |

UM1857 does not name the phase terminals in the retrieved text; **no ST corroboration**.

> **Contradiction flagged by the reference itself** (`main.c:88–91`): *"motors have been
> received from the vendor showing reversal of Motor White and Motor Red. Check rotor
> operation after assembly and in initial testing."*
>
> **Unresolvable from documents.** A swapped phase pair reverses rotation, which EXP001
> **P1** detects directly. Rated current 2.0 A/phase is inside the shield's 3 A rms
> (OFFICIAL-ST).

---

## 9. Power sequencing — contradiction **NARROWED, not eliminated**

| Source | Sequence | Class |
|---|---|---|
| Handout (safety box) | *"Power the supply **on last** and **off first**"* | COURSE |
| Manual §"System Power and Data Interface" | *"Power is **first** applied to the IHM01A1… USB cable is **then** attached"* | COURSE |
| **UM1857 §1** | *"1. Check the jumper position… 2. Connect the board to the STM32 Nucleo… **1. Supply the board through input 1 (VS) and 2 (ground) of CN1. 2. The power OK (green) and fault (red) LEDs turn on.**"* | **OFFICIAL-ST** |

**What ST actually says:** UM1857 describes supplying the board and observing the LEDs as a
*board bring-up* step. It **does not state an ordering constraint** between motor supply
and Nucleo logic power. **ST does not adjudicate the conflict.**

**Decision stands: follow the handout — logic first, motor supply last.** It is the ENR312
course document, it states the rule in an explicit safety box, and it is the order that
lets firmware and sensors be verified with the actuator de-energised.

**Newly usable from ST:** the green power-OK / red fault LEDs give a **direct visual check
the moment 12 V is applied** — before any motion is commanded. Worth adding to Stage 8 of
the bring-up procedure.

---

## 10. Contradiction ledger

| # | Contradiction | Status | Resolution / next step |
|---|---|---|---|
| 1 | Step clock: PWM (ST) vs GPIO-toggle (UCLA) | **RESOLVED** | Same pin; firmware method differs because TIM3 was reassigned to the encoder. No wiring impact |
| 2 | Motor supply range previously UNKNOWN | **RESOLVED** | UM1857: 8–45 V, 3 A rms, CN1 pins 1/2. 12 V/1 A is inside it |
| 3 | `DIR1` connector ambiguous in the extracted table | **RESOLVED** | CN9 pin 8 (D7); CN6 pin 8 is VIN and cannot carry it. Corroborated by UCLA `PA8` |
| 4 | **SPI CS / SCK are resistor-selectable** | **NEW — UNRESOLVED** | Inspect R15/R25, R23/R24. UCLA map = factory default |
| 5 | **Encoder A/B logic level vs STM32 tolerance** | **UNRESOLVED** | Needs the STM32F401 datasheet **and** measurement. Stage 3 |
| 6 | Encoder lead colour ↔ A/B channel | **UNRESOLVABLE from documents** | Measure the sign — EXP001 P2b |
| 7 | Motor White/Red vendor reversal | **UNRESOLVABLE from documents** | Observe direction — EXP001 P1 |
| 8 | Power sequencing: handout vs manual | **NARROWED** | ST is silent; handout order retained |
| 9 | Rotor control gain 17.778 vs 8.889 steps/° | **UNRESOLVED** | Not addressable from ST docs. Protractor — EXP001 Stage 9 |
| 10 | Rig identity: DC servo (outline) vs stepper (handout) | **UNRESOLVED** | Physical inspection — Stage 0.1 |
| 11 | `l` = 0.235 m (manual) vs L ≈ 0.253–0.258 m (tutorials) | **UNRESOLVED** | Possibly different quantities; needs measurement + system ID |

---

## 11. Confidence summary — after reconciliation

| Signal group | Before | After | Change |
|---|---|---|---|
| L6474 control (STCK, DIR, RESET, FLAG) | REFERENCE only | **ST (connector) + REFERENCE (pin)** | ⬆ corroborated |
| SPI (CS, SCK, MOSI, MISO) | REFERENCE only | **ST + REFERENCE**, *default config only* | ⬆ corroborated, ⚠ new config risk |
| Ground pins | UNKNOWN | **OFFICIAL-ST** (CN5-7, CN6-6, CN6-7) | ⬆ resolved |
| Motor supply range / current / entry | UNKNOWN | **OFFICIAL-ST** | ⬆ resolved |
| Fault indication | REFERENCE | **ST + REFERENCE**, plus LEDs | ⬆ improved |
| **Encoder (all)** | REFERENCE only | **REFERENCE only** | ↔ **no ST source exists** |
| **Encoder voltage / 5 V tolerance** | UNKNOWN | **UNKNOWN** | ↔ **datasheet not retrieved** |
| Motor phase colours | REFERENCE | REFERENCE | ↔ no ST corroboration |
| **PHYSICALLY-VERIFIED** | **NO** | **NO** | ↔ unchanged, and unchangeable on paper |

---

## 12. What must still be obtained

| # | Document | Answers | Blocking |
|---|---|---|---|
| 1 | **STM32F401xD/xE datasheet** | Are PB4/PB5 `FT` (5 V-tolerant)? | **Encoder connection — Stage 3** |
| 2 | **UM1724** (Nucleo-64) | Official Arduino ↔ STM32 pin table; power options | Upgrades §2 from INFERRED to OFFICIAL-ST |
| 3 | L6474 datasheet | `FLAG` output structure; pull-up requirement | §7 |
| 4 | LPD3806 datasheet | Supply range; output stage; required pull-up | §5 |
| 5 | Edukit assembly guide | Encoder connector and lead routing | §2 encoder rows |

**All five were attempted or noted this pass. Only UM1857 was obtained.**

---

## 13. Standing conclusion

Reconciliation **strengthened** the pin map: eight L6474 signals now have ST-documented
connector positions matching the UCLA STM32 assignments, and four previously-`UNKNOWN`
power facts are resolved.

It also **surfaced a new risk** — the SPI CS and clock lines are resistor-selectable, so
the correct pin map depends on how *this* board is populated.

And it **did not move** the item that matters most for safety: whether the 5 V
open-collector encoder can be connected to PB4/PB5 is still `UNKNOWN`, because the
STM32F401 datasheet was not retrieved.

**No connection in this document is physically verified. Nothing here authorises wiring.**

---

## Sources retrieved during this pass

- [UM1857 — Stepper motor driver expansion board based on L6474 for STM32 Nucleo (ST, DocID027377 Rev 1)](https://www.st.com/resource/en/user_manual/um1857-stepper-motor-driver-expansion-board-based-on-l6474-for-stm32-nucleo-stmicroelectronics.pdf) — **obtained and quoted**
- [X-NUCLEO-IHM01A1 product page (ST)](https://www.st.com/en/ecosystems/x-nucleo-ihm01a1.html) — VS range, phase current, CN1
- [UM1724 — STM32 Nucleo-64 boards (MB1136) (ST)](https://www.st.com/resource/en/user_manual/um1724-stm32-nucleo64-boards-mb1136-stmicroelectronics.pdf) — **not retrieved (timeout)**
- [STM32F401xD/xE datasheet (ST)](https://www.st.com/resource/en/datasheet/stm32f401re.pdf) — **not retrieved (timeout)**

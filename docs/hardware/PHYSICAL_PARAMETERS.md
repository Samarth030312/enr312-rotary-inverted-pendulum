> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`shared/parameters/edukit01_rig.yaml`](../../shared/parameters/edukit01_rig.yaml).

# Physical Parameters — ENR312 Rotary Inverted Pendulum

**Date:** 2026-08-20 · **Parameter set:** `PS-EDUKIT01-v1` · **Revision:** `73c7d31`

> # ⛔ NO VALUE IN THIS DOCUMENT HAS BEEN MEASURED ON THIS RIG
> The `MEASURED` and `IDENTIFIED` columns are **empty by construction** and must stay
> empty until real measurements exist.

---

## Column definitions — never mix these

| Column | Meaning |
|---|---|
| **SOURCE** | Printed in a repository document (course manual, tutorial, reference code). A value someone else measured, on some rig. |
| **MEASURED** | Directly measured on **this** rig with an instrument. Requires date, method, instrument. |
| **IDENTIFIED** | Obtained by fitting a model to **this** rig's measured response (system identification). |
| **ASSUMED** | Neither measured nor identified; adopted to make progress. **Every prediction resting on one inherits its uncertainty.** |

---

## 1. Geometry

| Parameter | Symbol | SOURCE | MEASURED | IDENTIFIED | ASSUMED | Unit | Evidence |
|---|---|---|---|---|---|---|---|
| Rotor arm length | `r` | **0.14** | — | — | — | m | Edukit Manual Table 2 |
| Pendulum length | `l` | **0.235** | — | — | — | m | Edukit Manual Table 2 ("vertical separation, rotor arm → pendulum mass") |
| Effective pendulum length | `L` | — | — | — | **0.253–0.258** | m | back-computed from the tutorials' `ω_g²` |
| Pendulum mass | `m` | — | — | — | — | kg | **UNKNOWN** |
| CoM distance | — | — | — | — | — | m | **UNKNOWN** |
| Rotor inertia | `I_rotor` | — | — | — | — | kg·m² | **UNKNOWN** (appears only inside a lumped term) |
| Pendulum inertia | `I_pend` | — | — | — | — | kg·m² | **UNKNOWN** |
| Gear ratio | — | — | — | — | — | — | **UNKNOWN** — no gearbox mentioned; direct drive assumed |

> **⚠ CONFLICT.** The manual gives `l = 0.235 m`. Tutorials 5/12 define
> `ω_g² = g/(L·0.6805)`; inverting their published `ω_g²` gives **L ≈ 0.2528 m**
> (suspended, `ω_g² = 57.01`) and **L ≈ 0.2581 m** (inverted, `ω_g² = 55.85`).
>
> `l` and `L` may be different quantities — a physical separation versus an effective
> model length including the `2I_rotor/mL²` term — or the sources may simply disagree.
> **Not resolved.** Measuring `l` directly and comparing against an identified `ω_g` is
> the way to settle it.

---

## 2. Lumped model coefficients

Tutorials 12 and 5 define
`ω_r² = r/(L·0.6805)` and `ω_g² = g/(L·0.6805)`, where `0.6805 = 2/3 + 2I_rotor/(mL²)`.

| Parameter | Mode | SOURCE | MEASURED | IDENTIFIED | Unit | Evidence |
|---|---|---|---|---|---|---|
| `ω_r²` | suspended | **0.803** | — | — | (rad/s)² | Tutorial 12 §2 |
| `ω_g²` | suspended | **57.01** | — | — | (rad/s)² | Tutorial 12 §2 |
| `Q` | suspended | **27** | — | — | — | Tutorial 12 §2 (from system ID on *that* rig) |
| `ω_r²` | inverted | **0.803** | — | — | (rad/s)² | Tutorial 5 §8 |
| `ω_g²` | inverted | **55.85** | — | — | (rad/s)² | Tutorial 5 §8 |
| `Q` | inverted | **20** | — | — | — | Tutorial 5 §8 |
| `0.6805` | both | **0.6805** | — | — | — | Tutorials 5, 12 |

> ## ⚠ OPEN ITEM OI-9 — THE DOMINANT UNCERTAINTY IN EXP003–EXP005
> These are **another rig's** values, obtained by system identification on the UCLA/ST
> Edukit. Every EXP003, EXP004 and EXP005 prediction rests on them.
>
> The suspended and inverted sets **differ from each other** (`ω_g²` 57.01 vs 55.85,
> `Q` 27 vs 20), which is physically reasonable — but it means **two** sets must be
> identified on this rig, not one.
>
> Identifying them requires a ring-down or frequency-response measurement — a system-ID
> task that **Tutorials 1–5 do not include**.

### Derived quantities (exact given the above)

| Quantity | Suspended | Inverted |
|---|---|---|
| `ω_g` | 7.5505 rad/s (1.202 Hz) | 7.4733 rad/s |
| `ω_g/Q` | 0.27965 rad/s | 0.37366 rad/s |
| Decay time constant `2Q/ω_g` | 7.15 s | — |
| Open-loop pole | −0.140 ± 7.549j (stable) | **−7.6625, +7.2888 (UNSTABLE)** |
| Fall time constant | — | **137 ms** |

---

## 3. Sensor

| Parameter | SOURCE | MEASURED | Unit | Evidence |
|---|---|---|---|---|
| Encoder PPR | **600** | — | pulses/rev | manual, UCLA |
| Decode multiplier | **X4** | — | — | UCLA TIM3 `TIM_ENCODERMODE_TI12` — a **firmware choice** |
| Counts per revolution | **2400** | — | counts/rev | derived; manual confirms |
| Angular resolution | **0.15** | — | °/count | derived |
| Pendulum measurement gain | **6.667** | — | counts/° | manual Table 2 |
| Encoder polarity | — | — | ±1 | **UNDETERMINED — EXP001 P2b** (reference used −1; not inherited) |
| Counter width | **16** | — | bits | TIM3 on STM32F401 |

**EXP001 P2 measures counts/rev directly.** A result of 600 or 1200 would identify the
decode mode as X1 or X2 and invalidate the constant.

---

## 4. Actuator — ⚠ THE CONTROL GAIN IS DISPUTED

| Parameter | SOURCE (manual) | SOURCE (UCLA code) | MEASURED | Unit |
|---|---|---|---|---|
| Full steps/rev | 200 | 200 | — | steps/rev |
| Microstep divisor | 1/16 | 1/16 (`STEP_SEL_1_16`) | — | — |
| **Rotor control gain** | **17.778** | **8.888889** | — | steps/° |
| **Rotor measurement gain** | **8.889** | **8.888889** | — | steps/° |
| Implied command resolution | 0.0563 °/step (6400/rev) | 0.1125 °/step (3200/rev) | — | — |

> ## ⚠ FACTOR-OF-TWO CONFLICT — AFFECTS EVERY COMMANDED ANGLE
> The Edukit Manual asserts a factor of two between commanding and reading the rotor.
> The UCLA reference code uses the **same** constant for both, and **EXP001 followed the
> code** (`ENR312_ROTOR_MICROSTEPS_PER_REV = 3200`).
>
> **If the manual is right, every commanded rotor angle in EXP001–EXP005 is out by 2×.**
>
> The manual's own wording is internally inconsistent — it describes the read gain as *"a
> factor of two greater"* while tabulating it as **half** the control gain.
>
> **Do not resolve this from documents.** EXP001 prediction **P1** measures it: command
> +45° and read the physical arm angle with a protractor. **22.5° confirms the manual.**

| Parameter | SOURCE | MEASURED | Unit | Evidence |
|---|---|---|---|---|
| Rated phase current | 2.0 | — | A | `17HS19-2004S` part number |
| Configured current (TVAL) | 0.8 | — | A | `l6474_target_config.h:105` |
| Overcurrent threshold | 2.25 | — | A | `l6474_target_config.h:146` |
| Holding torque | — | — | N·m | **UNKNOWN** |
| Winding R / L | — | — | Ω / H | **UNKNOWN** |
| Rotor polarity | — | — | ±1 | **UNDETERMINED — EXP001 P1** |
| Max step rate (EXP001 cap) | 1000 | — | steps/s | self-imposed; 0.038 % rate error |

---

## 5. Timing

| Parameter | SOURCE | MEASURED | Unit | Evidence |
|---|---|---|---|---|
| Control period `T_s` | **0.002** | — | s | handout ("500 times per second") |
| Control rate | **500** | — | Hz | handout |
| Timing jitter | — | — | s | **UNKNOWN — never measured (OI-10)** |
| Step-clock tick rate | 82031.25 | — | Hz | 84 MHz / 1024, from the reference prescaler |
| MCU clock | 84 | — | MHz | **LOCAL** — this repo's `SystemClock_Config` |

> ## ⚠ OPEN ITEM OI-10 — BLOCKING FOR EXP005
> **Loop timing has never been measured.** A 500 Hz loop gives ~68 samples per 137 ms fall
> time constant, which is ample *if* the timing is as assumed. EXP005 is the first
> experiment where slow or jittery timing causes a **fall**, not a poor response.

---

## 6. Derived sensing limits (exact given §3)

| Quantity | Value | Note |
|---|---|---|
| Angle quantisation `σ_θ` | 7.557×10⁻⁴ rad (0.0433°) | uniform residual, `q/√12` |
| Velocity granularity `q/T_s` | 1.309 rad/s (75 °/s) | one count per sample |
| Velocity noise `σ_ω`, unfiltered | **0.534 rad/s** | `σ_θ·√2/T_s` |
| `σ_ω` after a 10 Hz derivative filter | 0.136 rad/s | noise gain 0.251 |
| Counter-wrap aliasing threshold | 6827 rev/s | unreachable |

These are **exact consequences** of the encoder resolution and sample period. They become
wrong only if §3 or §5 is wrong.

---

## 7. Capture template — fill during bring-up

```yaml
parameter_set_id: PS-EDUKIT01-v1-MEASURED   # new ID once anything is measured
measured_on: YYYY-MM-DD
operator: ""
instruments: []          # protractor, calipers, scale, scope -- with resolutions

geometry:
  r_m:            { measured: null, method: "", uncertainty: null }
  l_m:            { measured: null, method: "", uncertainty: null }
  pendulum_mass_kg: { measured: null, method: "" }

sensor:
  counts_per_rev: { measured: null, method: "EXP001 P2, one full revolution" }
  encoder_polarity: { measured: null, method: "EXP001 P2b", direction_described: "" }

actuator:
  # THE FACTOR-OF-TWO RESOLUTION -- record BOTH commanded and measured
  commanded_deg:  45.0
  measured_deg:   null     # 45 -> UCLA code correct;  22.5 -> manual correct
  control_gain_steps_per_deg: null
  rotor_polarity: { measured: null, method: "EXP001 P1" }
  step_fidelity_residual_deg: null   # EXP001 P3, after 10 zero-net cycles

identified:
  suspended: { wg2: null, wr2: null, Q: null, method: "ring-down or freq response" }
  inverted:  { wg2: null, wr2: null, Q: null, method: "" }

timing:
  measured_period_s: null      # OI-10 -- BLOCKING for EXP005
  jitter_std_s: null
  method: ""                   # requires an INDEPENDENT time source
```

---

## 8. Summary

| Category | SOURCE | MEASURED | IDENTIFIED | UNKNOWN |
|---|---|---|---|---|
| Geometry | 2 | **0** | 0 | 5 |
| Lumped model | 6 | **0** | 0 | 0 (but all are another rig's) |
| Sensor | 5 | **0** | 0 | 1 (polarity) |
| Actuator | 5 | **0** | 0 | 3 |
| Timing | 3 | **0** | 0 | 1 (jitter) |
| **Total** | **21** | **0** | **0** | **10** |

**Nothing has been measured. Twenty-one values are another rig's or a document's.**

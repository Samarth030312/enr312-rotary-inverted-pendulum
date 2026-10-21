> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP005/`.

# EXP005 — First-Principles Derivation

**Source:** Tutorial 5 — *MIMO Unstable System Control* · **Depends on:** EXP001–EXP004

> ## ⚠ THIS IS THE FIRST EXPERIMENT WITH NO BENIGN FAILURE MODE
> The open-loop inverted pendulum has a right-half-plane pole at **+7.2888 rad/s** — a
> **137 ms** fall time constant. If the loop opens, the pendulum falls and the arm slams.
> Every safety bound in EXP005 is tighter than EXP003's, deliberately.

---

## 1. What changes: one sign

```
    SUSPENDED (EXP003/004):  G_pend = ω_r²s² / (s² + (ω_g/Q)s + ω_g²)
    INVERTED  (EXP005):      G_pend = ω_r²s² / (s² + (ω_g/Q)s − ω_g²)
                                                                 ↑ MINUS
```

The parameters also differ (Tutorial 5 §8):

| | Suspended | Inverted |
|---|---|---|
| `ω_r²` | 0.803 | 0.803 |
| `ω_g²` | 57.01 | **55.85** |
| `Q` | 27 | **20** |
| `ω_g/Q` | 0.2796 | **0.3737** |

Physically: gravity **restores** a hanging pendulum and **destabilises** a standing one.
Mathematically that is the sign of the `ω_g²` term, and it moves a pole from the left half
plane to the right:

```
    poles of s² + 0.37366s − 55.85  =  −7.6625  and  +7.2888
```

**+7.2888 rad/s → 137 ms e-folding time.** This is the "falls in a fraction of a second"
of the student handout, quantified.

---

## 2. The inner controller must now stabilise, not damp

```
    K_pend(s) = 300 + 30·s        SUPPLIED and FIXED by Tutorial 5
```

Thirty times the suspended-mode gain (`10 + 5s`). It is doing a categorically different
job: EXP003's inner loop *damped* a stable resonance; this one *stabilises* an unstable
plant.

It succeeds:

```
    den_pend + ω_r²·K_pend  =  s² + 24.4637s + 185.05
    poles: −12.232 ± 5.953j       ζ = 0.899,  ω_n = 13.60 rad/s
```

Both coefficients positive, both poles in the left half plane. **The inner loop is
stable.**

### Documented conflict in the source

Tutorial 5 §8 states `K_P = 300.0, T_d = 0.5 s, K_d = K_P·T_d = 30.0`. But
**300 × 0.5 = 150, not 30.** The stated `T_d` and `K_d` cannot both be right.

`K_d = 30` is operative, on two independent pieces of evidence:
1. Tutorial 5's own serial-interface transcript enters `Differential Gain: 30.00` in every
   example.
2. The UCLA reference firmware pairs `PRIMARY_PROPORTIONAL_MODE_1 = 300` with
   `PRIMARY_DERIVATIVE_MODE_1 = 30`.

The implied `T_d` is therefore **0.1 s**, not 0.5 s. Recorded, not silently corrected.

---

## 3. The outer loop must be inverted

```
    T_rotor(s) = den_pend / ( s²·(den_pend + ω_r²K_pend) )
```

`den_pend(0) = −ω_g² = −55.85`, so near DC

```
    T_rotor ≈ −55.85 / (185.05 s²) = −0.3018/s²        NEGATIVE DC gain
```

Closing the outer loop with a **positive** `K_rotor` is therefore **positive feedback**.

**Established by evidence, not assumption.** With the non-inverted sign, both of Tutorial
5's own published designs are unstable; with the inversion, both are stable *and* their
relative stability reproduces the names Tutorial 5 gives them:

| Design | non-inverted `max Re(pole)` | inverted `max Re(pole)` |
|---|---|---|
| "Stable System 1" | **+2.4613** (unstable) | **−1.7915** (stable) |
| "Quasi-Stable System 2" | **+1.8915** (unstable) | **−0.3497** (stable, barely) |

Independent corroboration: the UCLA reference firmware uses **negative** gains for its
suspended demonstration mode (`−10.0`, `−2.0`) and **positive** ones for inverted — the
same inversion applied at gain entry rather than in the loop algebra. Tutorial 5 quotes
positive gains and leaves the inversion implicit in the mode.

---

## 4. The fundamental limitation

`T_rotor`'s **numerator is `den_pend`**. So the plant's unstable **pole** at +7.2888 rad/s
becomes a **non-minimum-phase zero of `T_rotor`** at the same frequency.

> **Stabilising an unstable pole does not remove it from the problem. It converts it into
> a right-half-plane zero of the loop the outer controller must then work with.**

A RHP zero imposes a hard bandwidth ceiling — roughly `z/2 ≈ 3.64 rad/s` (0.58 Hz) — that
**no choice of `K_rotor` can exceed**. This is why Tutorial 5's targets (settling < 4 s,
overshoot < 25 %) are so much looser than Tutorial 3's, and why gain and phase margins,
not speed, become the binding constraints.

**Observable signature:** the step response **dips the wrong way first**. Physically, the
arm must move *away* from the target initially to get under the pendulum before it can
carry it. Computed undershoot ranges from −11 % to −40 % across the designs.

---

## 5. Stability metrics (Tutorial 5 §§5–7)

| Symbol | Definition |
|---|---|
| `ω_GC` | gain crossover, `\|L(jω)\| = 1` |
| `φ_M` | phase margin `= 180° + ∠L(jω_GC)` |
| `ω_PC` | phase crossover, `∠L(jω) = −180°` |
| `GM` | gain margin `= 1/\|L(jω_PC)\|`, in dB `= −20log₁₀\|L(jω_PC)\|` |
| `M_S` | `max\|S(jω)\|`, at `ω_MS` |
| `ω_SC` | sensitivity crossover, `\|S\| = 1` |

All three margin families measure the same thing — distance from `−1` on the Nyquist
diagram — along different directions: `GM` radially, `φ_M` angularly, `M_S` as the closest
approach in any direction. That is why `M_S` is the most complete single number.

---

## 6. Results

### Tutorial 5 §13 introduction-step designs

| | `K_P` | `T_d` | `K_d` | Settling | OS | **Undershoot** | `φ_M` | `GM` | `M_S` |
|---|---|---|---|---|---|---|---|---|---|
| Stable System 1 | 9 | 1.0 | 9 | 2.75 s | 23.6 % | −33.2 % | 47.3° | 6.01 dB | 6.37 dB |
| Quasi-Stable System 2 | 10 | 0.333 | 3.33 | 11.74 s | 70.8 % | −11.6 % | **17.5°** | 13.68 dB | **10.32 dB** |

System 2's phase margin (17.5°) and `M_S` (10.3 dB) are clearly poor — matching Tutorial
5's description of it as *"not meeting stability margins"*.

> **Discrepancy recorded.** Tutorial 5 §13 describes System 2 as having *"improved
> performance"* relative to System 1. The model shows the opposite: System 2 settles in
> 11.7 s with 70.8 % overshoot against System 1's 2.75 s and 23.6 %. Either "performance"
> there refers to something not tabulated (e.g. disturbance response), or it describes
> observed hardware rather than the model. **Not resolved — flagged for the hardware run.**

> **Second source conflict:** §13's table gives System 2 as `K_d = 3.33` (`= 10 × 0.333`)
> while its serial transcript enters `3.00`. `3.33` is self-consistent with `K_d = K_P·T_d`
> and is used; both are evaluated in the tool so the difference is visible (3.00 gives
> `φ_M` 14.7° and `M_S` 11.8 dB — slightly worse).

### Designs meeting Tutorial 5 §14 objectives

Constraints: `K_d < 15`, `K_P < 18`.

| | `K_P` | `T_d` | `K_d` | Settling | OS | `φ_M` | `GM` | `M_S` | Meets? |
|---|---|---|---|---|---|---|---|---|---|
| **System 1** (`t_s`<4, OS<25 %, GM>8 dB, `φ_M`>50°, `M_S`<5 dB) | 6.25 | 1.12 | 7.00 | 3.25 s | 24.8 % | 50.6° | 8.23 dB | 4.52 dB | **YES** |
| **System 2** (`t_s`<2, OS<35 %, GM>4 dB, `φ_M`>30°, `M_S`<10 dB) | 0.50 | 21.5 | 10.75 | 0.83 s | 6.4 % | 58.6° | 4.76 dB | 7.86 dB | **YES** |

> **Caveat on the System 2 design.** `T_d = 21.5 s` makes it almost purely derivative —
> the same pattern seen in EXP004's Design B. The search minimises settling time, and
> derivative-dominant designs win that objective while amplifying measurement noise and
> demanding large control effort. It satisfies every stated constraint, but Tutorial 5
> imposes no control-effort or noise constraint. **A practical implementation should check
> both before adopting it.**

---

## 7. Units and conventions

As EXP003, plus:

| Symbol | Unit |
|---|---|
| `φ_M` | degrees |
| `GM` | dB (`−20log₁₀\|L\|`, an amplitude ratio) |
| `ω_GC`, `ω_PC`, `ω_MS`, `ω_SC` | rad/s |

`θ = 0` is now **upright**, not hanging. This is a different physical datum from
EXP003/EXP004 and must be re-established at the start of every inverted run.

---

## 8. What can and cannot be measured

**Can:** pendulum angle; commanded rotor angle; the step response and its undershoot (the
RHP-zero signature); `φ_M`, `GM`, `M_S`, `ω_SC` computed offline from step data.

**Cannot:** the RHP pole directly (measuring it means letting the pendulum fall,
repeatedly and by design — possible but destructive); `ω_r², ω_g², Q` for **this** rig
(**OI-9**, now doubly important because the inverted parameters differ from the suspended
ones and *both* sets are another rig's).

---

## 9. Assumptions

| ID | Assumption | If false | Tested where |
|---|---|---|---|
| E1 | Inverted `G_pend` with `ω_g²=55.85, Q=20` | every margin wrong | **OI-9** |
| E2 | Outer loop inverted in inverted mode | positive feedback; immediate fall | verified against Tutorial 5's own designs |
| E3 | `K_d_pend = 30` (not 150) | inner loop mis-tuned | two independent sources |
| E4 | Small-angle linearisation valid to ±15° | model ≠ system near the bound | `sin` error 1.2 % at 15° |
| E5 | Operator can present the pendulum upright | capture gate never completes | capture gate |
| E6 | Loop closes fast enough vs a 137 ms fall | unrecoverable | **EXP003 timing never verified** |

> **E6 is the most dangerous untested assumption in the whole laboratory.** Sample-rate
> and jitter have never been measured on this rig. A 500 Hz loop has ~68 samples per fall
> time constant, which is ample *if* the timing is what it is assumed to be — and that has
> never been checked.

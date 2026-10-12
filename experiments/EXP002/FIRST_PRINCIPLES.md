> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP002/`.

# EXP002 — First-Principles Derivation

**Source:** Tutorial 2 — *Introduction to Control System Design and Performance Analysis
by Sensitivity Function Measurement*
**Depends on:** EXP001 (Tutorial 1) — measurement foundation, and its rotor PD design
**Parameter set:** `PS-EDUKIT01-v1`

---

## 1. What are we measuring, and why?

EXP001 established that a command produces motion and that a sensor reading means an
angle. EXP002 asks the next question: **when the loop is closed, how well does it
actually behave — and behave against what?**

"Well" is not one property. Tutorial 2's central point is that a control system has
*several* input paths, and a design that is good on one can be poor on another:

- a **reference** the output should follow (`R`);
- a **load disturbance** entering at the plant input, which the controller cannot see
  (`D`);
- **measurement noise** entering at the sensor (`N`).

A controller tuned only for reference tracking may reject disturbances badly. Measuring
both is the whole content of this experiment.

---

## 2. Signal topology (Tutorial 2, Figure 1)

```
        R ---->(+)---- e ---->[ C(s) ]---- u ---->(+)---- U ---->[ P(s) ]----+----> Y
                ^-                                  ^                        |
                |                                   |                        |
                |                                   D                        |
                +---------------- (Y + N) <---------------------------------(+)
                                                                             ^
                                                                             N
```

Where each signal enters is not a detail — it *defines* the transfer functions:

- **`D` enters at the plant input**, after the controller. It represents a load the
  controller has no knowledge of, so it is not attenuated by `C` before reaching `P`.
- **`N` enters at the sensor**, so the controller acts on `Y + N`, never on `Y`.

Getting either injection point wrong yields a plausible-looking measurement of the wrong
quantity. The firmware enforces both (`enr312_pd.c`), and the placement is unit-tested.

---

## 3. Plant and controller

From Tutorial 1 §2:

```
    Rotor plant       P(s) = 1/s²           double integrator
    Rotor controller  C(s) = K_P + K_d·s    K_d = K_P·T_d
```

**Why `1/s²`?** The rotor is commanded through a stepper whose control input behaves as
an angular *acceleration* demand; angle is its double integral. This is the model
Tutorial 1 states. It is **not verified on this rig** — recorded as open item **OI-7**.
A double integrator has two poles at the origin: it is marginally stable, has no natural
damping whatsoever, and *cannot* be stabilised by proportional action alone. The
derivative term is not a refinement here; it is the only source of damping in the loop.

---

## 4. The four transfer functions

With `L(s) = P(s)C(s) = (K_d s + K_P)/s²`:

| Name | Definition | Closed form | Measures |
|---|---|---|---|
| Sensitivity | `S = 1/(1+L)` | `s²/(s² + K_d s + K_P)` | error rejection |
| Complementary sensitivity | `T = L/(1+L)` | `(K_d s + K_P)/(s² + K_d s + K_P)` | **reference tracking** |
| Load-disturbance sensitivity | `S_D = P/(1+L)` | `1/(s² + K_d s + K_P)` | **disturbance rejection** |
| Noise sensitivity | `C/(1+L)` | `s²(K_d s + K_P)/(K_P(s² + K_d s + K_P))` | noise amplification |

All share the closed-loop denominator, so

```
    ω_n = √K_P   [rad/s]           ζ = K_d / (2√K_P)   [dimensionless]
```

`S + T = 1` identically — the fundamental constraint. You cannot make both small at the
same frequency; the design is a trade, not an optimisation.

### The zero in `T(s)` matters

`T` has a zero at `s = −K_P/K_d`. For the Tutorial 1 design that is `−2 rad/s`, close to
`ω_n = 2.236 rad/s`, so it materially increases overshoot: **26.8 %** measured, against
**12.0 %** for the same poles without the zero. The zero exists because the derivative
acts on the *error*, so a reference step passes directly through `K_d·s`.

This is not an artefact to be removed. Tutorial 2 measures the sensitivity functions *of
this controller*, so the firmware keeps derivative-on-error. Derivative-on-measurement
would remove the zero and change `T(s)` — a different experiment.

---

## 5. Units and conventions — stated, never implied

| Symbol | Meaning | Unit |
|---|---|---|
| `R`, `Y`, `e`, `N` | reference, output, error, noise — all rotor **angle** | deg (rad in models) |
| `D`, `U`, `u` | plant input — rotor angular **acceleration** demand | plant-input units (OI-7) |
| `K_P` | proportional gain | 1/s² |
| `T_d` | derivative time | s |
| `K_d` | `K_P·T_d` | 1/s |
| `ω_n` | `√K_P` | rad/s |
| `ζ` | `K_d/(2√K_P)` | — |
| `T_s` | sample period | 0.002 s |

**Sign convention:** `e = R − (Y + N)`. Positive error means the output is *below* the
reference. Rotor angle sign follows EXP001, and remains **UNDETERMINED** until measured
(open item OI-2). A sign error here converts negative feedback into positive feedback.

### The one convention that silently changes the answer

`T(0) = 1`, so `T`'s step response settles to **1**.
`S_D(0) = 1/K_P`, so the disturbance step response settles to **1/K_P ≠ 0**.

Overshoot and settling for `S_D` are therefore measured **relative to `1/K_P`**, not to
zero. Compared against zero, `S_D` *never settles at all* — see §7.

---

## 6. Discrete implementation

The controller runs at `T_s = 2 ms`. Two departures from the ideal `C(s)`, both
deliberate:

**Backward-difference derivative:** `de/dt ≈ (e[k] − e[k−1])/T_s`.

**First-order low-pass on the derivative**, `a = 1 − exp(−2π f_c T_s)`, default
`f_c = 10 Hz` giving `a = 0.11809`.

This filter is **forced by EXP001's measurements**, not chosen by taste. EXP001 equations
(13)–(14) give a raw backward-difference velocity granularity of 1.309 rad/s and
`σ = 0.534 rad/s` at this sample rate. Unfiltered, a gain `K_d` injects `0.534·K_d` of
noise straight into the actuator. The filter's steady-state noise gain is
`√(a/(2−a)) = 0.251`, reducing `σ` to **0.134 rad/s**.

At `f_c = 10 Hz` the filter pole (62.8 rad/s) is 28× faster than `ω_n` (2.24 rad/s), so
the effect on `T(s)` is small but not zero — the host tests bound it explicitly.

**Consequence of the first-sample rule:** `ENR312_PD_Update` reports zero derivative on
its first call, since no predecessor exists. If an excitation step landed on that tick,
`T`'s zero would be suppressed and overshoot would collapse from 27 % to 11 %. The
sequencer's IDLE phase exists partly to prevent this, and the tests reproduce the
ordering deliberately.

---

## 7. What a correct result looks like

For the Tutorial 1 design `K_P = 5, T_d = 0.5, K_d = 2.5`
(`ω_n = 2.236 rad/s`, `ζ = 0.559`), computed in
`scripts/exp002_sensitivity_design.py`:

| Quantity | `T(s)` reference tracking | `S_D(s)` disturbance |
|---|---|---|
| final value | 1.0000 | 0.2000 = 1/K_P |
| peak value | 1.2676 | 0.2241 |
| peak time | 1.055 s | 1.694 s |
| overshoot | 26.76 % | 12.03 % |
| settling (2 %) | 3.239 s | 2.617 s |

### A finding worth stating plainly

Tutorial 2 §2 warns: *"You may find that for your design, the Load Disturbance Rejection
Sensitivity Function Step Response shows an extended settling time."*

Against `S_D`'s own final value it settles in 2.6 s — comfortably. **The warning is about
a different measurement.** Disturbance *rejection* means returning to zero, and against
zero this system never settles: it holds a permanent offset of `1/K_P = 0.2`.

That is not a tuning failure. It is structural. A PD controller has no integral action, so
the loop gain at DC is finite and a constant load produces a constant error. No choice of
`K_P` and `K_d` removes it; larger `K_P` only shrinks it. **This is precisely the
motivation for integral action in Tutorial 6.**

Both conventions are computed and reported so the distinction cannot be lost.

---

## 8. Design objectives (Tutorial 2 §3)

| Response | Peak time | Overshoot | Settling (2 %) |
|---|---|---|---|
| Rotor angle (`T`) | < 2 s | < 30 % | < 4 s |
| Load disturbance (`S_D`) | < 3 s | < 15 % | < 4 s |

Admissible region: `0 < K_d ≤ 4.0`, `0.5 < K_P < 10`.

**Result:** the Tutorial 1 design *already satisfies all six*. A grid search finds 3595
feasible designs. The one minimising disturbance settling is
`K_P = 6.55, T_d = 0.611, K_d = 4.00` (`ζ = 0.782`), giving `T` overshoot 18.5 %,
settling 1.96 s; `S_D` overshoot 1.96 %, settling 1.41 s.

`K_d = 4.0` sits **on the constraint boundary** — the unconstrained optimum lies outside
the admissible region, so the constraint is active and the design is limited by the
tutorial's bound rather than by the physics.

---

## 9. Dominant error sources

| Source | Effect | Mitigation |
|---|---|---|
| Encoder quantisation | `σ_ω = 0.534 rad/s` into the derivative | 10 Hz derivative filter (§6) |
| Plant-model error (OI-7) | `1/s²` unverified; friction and actuator dynamics unmodelled | Compare measured vs model; record discrepancy |
| Actuator saturation | Makes the "measured sensitivity function" nonlinear | Small excitation amplitudes; saturation abort |
| Timing jitter | `T_s` non-uniform corrupts the derivative | **Not characterised** — EXP003 |
| Sign error | Positive feedback; violent divergence | OI-2, resolved by EXP001 hardware run |
| Lost steps | Rotor position model diverges silently | EXP001 P3 |

---

## 10. What would indicate a wiring/configuration/software problem

| Observation | Likely cause |
|---|---|
| Output diverges on any gain | Feedback sign inverted (OI-2) |
| Overshoot ≈ 12 % instead of ≈ 27 % | Derivative kick suppressed — step applied on the first tick, or derivative on measurement |
| `S_D` settles to 0 | Integral action present somewhere it should not be |
| `S_D` offset ≠ `1/K_P` | Disturbance injected at the wrong point, or plant is not `1/s²` |
| `N` produces no error | Noise injected after the comparator instead of at the sensor |
| Measured `ω_n ≠ √K_P` | Plant is not `1/s²` — OI-7 confirmed wrong |
| Response depends on step amplitude | Saturation — reduce excitation |

---

## 11. Assumptions

| ID | Assumption | If false | Tested where |
|---|---|---|---|
| B1 | `P(s) = 1/s²` | Every predicted metric is wrong | Compare measured vs model (hardware) |
| B2 | Loop is linear over the excitation range | Sensitivity functions meaningless | Saturation abort; amplitude sweep |
| B3 | `T_s` uniform at 2 ms | Derivative biased | **EXP003** |
| B4 | Rotor position model tracks the physical arm | Feedback is of a fiction | EXP001 P3 |
| B5 | Derivative filter at 10 Hz negligibly perturbs `T` | Model/measurement mismatch | Host tests bound it |
| B6 | Sign conventions correct | Positive feedback | EXP001 P1/P2b |

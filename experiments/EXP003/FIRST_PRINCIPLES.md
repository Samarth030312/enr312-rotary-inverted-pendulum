> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP003/`.

# EXP003 — First-Principles Derivation

**Source:** Tutorial 3 — *Control of Multiple Input Multiple Output (MIMO) Systems:
Control Effort* (suspended mode)
**Depends on:** EXP001 (measurement chain), EXP002 (sensitivity functions, rotor PD)
**Parameter set:** `PS-EDUKIT01-v1`

---

## 1. What EXP003 adds

EXP001 and EXP002 controlled **one** variable with **one** loop. EXP003 introduces the
problem that makes the rotary pendulum interesting: **two outputs must be controlled with
one actuator.**

Tutorial 3 §3 states the limitation precisely. A single pendulum-angle loop *can* be
designed to meet stability and performance objectives — but it does not control rotor
angle, so "while `θ(s)` may temporarily stabilize near `θ_command(s)`, `φ_Rotor(s)` will
not be controlled and will drift with an uncertain trajectory."

That drift is not a tuning defect. It is a structural consequence of leaving a degree of
freedom unconstrained, and no amount of pendulum-loop tuning removes it.

**The second thing EXP003 adds is a cost.** Until now, "better" meant faster settling and
less overshoot. Tutorial 3 §5 introduces **control effort** — the price in actuator
amplitude, power and energy paid for that performance — and asks for a design that meets
performance limits while *minimising* the price.

---

## 2. Physical system

| | |
|---|---|
| **Controlled** | rotary inverted pendulum, **suspended** (hanging) configuration |
| **Actuator** | one — the rotor stepper. **One input, two outputs** |
| **Output 1** | pendulum angle `θ` — measured by the encoder (EXP001) |
| **Output 2** | rotor angle `φ` — **commanded, not measured** (EXP001 §2.1) |
| **Disturbances** | load at the plant input; platform tilt (Tutorial 12); friction |
| **Mode** | suspended: gravity restores the pendulum, so the plant is **stable** |

Suspended mode is the safe place to learn MIMO: if control is lost, the pendulum simply
hangs. Inverted mode is EXP005.

---

## 3. Plants

### Rotor (from Tutorial 1 §2)

```
    G_rotor(s) = 1/s²
```

Double integrator. Two poles at the origin, no natural damping. Unverified on this rig —
open item **OI-7**.

### Pendulum, suspended mode (from Tutorial 12 §2)

```
                     ω_r² s²
    G_pend(s) = ─────────────────────       θ(s)/φ(s)
                s² + (ω_g/Q)s + ω_g²
```

with, for the reference rig,

| Symbol | Value | Unit | Provenance |
|---|---|---|---|
| `ω_r²` | 0.803 | (rad/s)² | Tutorial 12 §2 — **REFERENCE, not measured** |
| `ω_g²` | 57.01 | (rad/s)² | Tutorial 12 §2 — **REFERENCE, not measured** |
| `Q` | 27 | — | Tutorial 12 §2, from system identification |
| `ω_g/Q` | 0.279648 | rad/s | derived |

`ω_g = 7.5505 rad/s` → 1.202 Hz natural frequency, decay time constant `2Q/ω_g = 7.15 s`.
The suspended pendulum rings for a long time; this matters for how long a run must be.

**The `s²` numerator is the physics, not an artefact.** The pendulum responds to rotor
*acceleration*, not rotor position — swing the pivot at constant velocity and nothing
happens. Two consequences follow immediately:

- `G_pend(0) = 0`: a constant rotor angle produces no steady pendulum deflection.
- Cascading with `G_rotor = 1/s²` gives `G_pend·G_rotor = ω_r²/(s² + (ω_g/Q)s + ω_g²)` —
  the `s²` cancels the double integrator exactly. The pendulum sees the plant input
  directly.

That cancellation gives the clean simulation identity used by the host tests: since
`s²φ = u`,

```
    θ̈ + (ω_g/Q) θ̇ + ω_g² θ = ω_r² u
```

The pendulum is driven by the plant input with no algebraic loop.

---

## 4. Controllers

### Inner — pendulum, SUPPLIED AND FIXED (Tutorial 3 §3)

```
    K_pend(s) = K_P-Pend + K_d-Pend·s
    K_P-Pend = 10.0,  K_I-Pend = 0.0,  T_d-Pend = 0.5 s,  K_d-Pend = 5.0
```

Tutorial 3 supplies this and explicitly defers its design ("`K_Pend` will be the subject of
additional design effort in the future"). It is **not** a free parameter in EXP003, and the
firmware treats it as a constant rather than an argument, so it cannot drift between runs.

### Outer — rotor, TO BE DESIGNED (Tutorial 3 §6)

```
    K_rotor(s) = K_P-Rotor + K_d-Rotor·s
    Design 1 defaults: K_P = 6, K_I = 0, T_d = 0.8 s, K_d = 4.8
```

---

## 5. Loop structure

Tutorial 3 §4 gives the inner-loop relation with the pendulum reference held at zero:

```
    φ_Rotor(s) = ( φ_Rotor-Control(s) − φ_Rotor(s)·G_pend(s)·K_pend(s) ) · G_rotor(s)
```

from which

```
                              G_rotor(s)
    T_rotor(s) = ────────────────────────────────────         (inner closed loop)
                 1 + G_pend(s)·K_pend(s)·G_rotor(s)
```

and with the outer controller,

```
                            T_rotor(s)·K_rotor(s)
    T_rotor-tracking(s) = ──────────────────────────           (outer closed loop)
                          1 + T_rotor(s)·K_rotor(s)
```

**Firmware form.** Rearranging, the plant input is the *sum* of the two controller
outputs:

```
    u = K_rotor(φ_cmd − φ)  +  K_pend(θ_cmd − θ)
```

This reading is independently corroborated by the UCLA reference project, which describes
its own Dual PID mode as "implemented as summation of Primary and Secondary PID controller
structures… summed and supplied to Rotor Control".

Substituting the plants:

```
    T_rotor(s) = ─────────── s² + (ω_g/Q)s + ω_g² ─────────────
                 s²·[ s² + ((ω_g/Q) + ω_r²K_d-Pend)s + (ω_g² + ω_r²K_P-Pend) ]
```

With the supplied inner gains the bracket is `s² + 4.29465 s + 65.04` — the inner loop has
turned a `Q = 27` resonance (`ζ = 0.0185`) into `ζ = 0.266`. **The inner loop's job is to
damp the pendulum**, and the numbers show it doing exactly that, by a factor of 14.

Note `T_rotor` retains `s²` in its denominator: the rotor is still a double integrator at
DC. The outer loop must supply its own damping, which is why `K_rotor` needs its
derivative term.

---

## 6. Control effort (Tutorial 3 §5)

```
                     u(s)          K_rotor(s)
    CE(s) = ──────────────── = ──────────────────────
            φ_Command(s)       1 + T_rotor(s)·K_rotor(s)
```

Tutorial 3 notes this "also appears as the Noise Sensitivity Function" — the same transfer
function measures both, so a design that is quiet against noise is also cheap to run.

Metrics:

```
    CE_Max-Amplitude = max |u(t)|
    CE_Max-Power     = max u(t)²
    CE_Total         = ∫ |u| dt
```

### Documented conflict in the source, resolved by evidence

Tutorial 3 §5 writes the third metric as the **signed** integral `∫u(τ)dτ`, but the results
table labels it "Control Effort Total Energy" with the value **11.0** for Design 1.

The written formula cannot be what the tool computes. `CE(s)` has **zero DC gain** — as
`s→0`, `T_rotor→∞` so `CE ≈ K_P-Rotor·s²/(T_rotor·K_P-Rotor) → 0` — therefore the signed
integral of `u` is exactly **zero**. Numerically confirmed: `0.0000`.

Testing all three candidate readings against Tutorial 3's own Design 1 value:

| Candidate | Computed | Tutorial 3 |
|---|---|---|
| `∫u dt` (as written) | **0.0000** | 11.0 ✗ |
| `∫u² dt` (literal "energy") | **1.17×10³** | 11.0 ✗ |
| **`∫\|u\| dt`** | **10.88** | **11.0 ✓** |

**Decision:** `CE_Total = ∫|u|dt`. The source's formula omits the absolute value. Recorded
here rather than silently corrected, per docs/ENGINEERING_STANDARDS.md §7.

### `CE_Max` is not a property of the plant alone

`CE(s)` is **improper**: `K_rotor` adds a relative degree that `1/(1+T_rotor K_rotor)` does
not remove. Its step response therefore contains a Dirac delta, and **any finite
`CE_Max` depends on how the derivative is realised.**

Adding the derivative filter every real implementation needs,
`K_rotor(s) → (K_P + K_d s)·N/(s+N)`, makes `CE` proper. Sweeping `N`:

| `N` [rad/s] | `CE_Max` | `CE_Total` | settling [s] | overshoot [%] |
|---|---|---|---|---|
| 50 | 240 | 10.75 | 2.112 | 34.2 |
| **100** | **480** | **10.88** | **2.096** | **32.4** |
| 200 | 960 | 11.03 | 2.091 | 31.6 |
| 1000 | 4800 | 11.28 | 2.087 | 30.9 |

`CE_Max` scales **linearly with `N`**; `CE_Total`, settling and overshoot vary by under 5 %
across a 20× range. Tutorial 3's `CE_Max = 477` is reproduced at `N = 99.4 rad/s`,
equivalent to a simulation sample of `dt ≈ 0.0101 s` — the tool evidently runs at ~100 Hz.

**Consequences, both binding:**
1. `N = 100 rad/s` is adopted as the reference realisation, and **every `CE_Max` and
   `CE_Max_Power` figure in EXP003 is quoted with its `N`.**
2. Design conclusions rest on `CE_Total`, settling and overshoot — the three metrics that
   are *insensitive* to the realisation.

---

## 7. Validation against the source

Tutorial 3 §6 publishes Design 1 (`K_P = 6, T_d = 0.8, K_d = 4.8`). Reproducing it is the
strongest available check on the entire formulation:

| Metric | Tutorial 3 | Computed (`N=100`) | Error |
|---|---|---|---|
| Settling (2 %) | 2.1 s | 2.096 s | −0.2 % |
| Overshoot | 31.4 % | 32.43 % | +3.3 % |
| `CE_Max-Amplitude` | 477 | 480 | +0.6 % |
| `CE_Max-Power` | 2.27×10⁵ | 2.304×10⁵ | +1.5 % |
| `CE_Total` | 11.0 | 10.88 | −1.1 % |

All five within ~3 %. This validates `G_pend`, `G_rotor`, `K_pend`, the inner/outer loop
algebra, the `CE` definition, and the `∫|u|` reading of `CE_Total` **simultaneously**.
Independent confirmation: `477² = 2.276×10⁵`, matching the published `CE_Max-Power` — so
the tutorial's own two numbers are self-consistent with `max u²`.

---

## 8. Design objectives (Tutorial 3 §6)

| Step | Objective | Settling | Overshoot | `CE_Total` target |
|---|---|---|---|---|
| Design 1 | given | 2.1 s | 31.4 % | 11.0 |
| **Step 2** | minimise `CE_Total` | ≤ 4 s | ≤ 30 % | < 5 |
| **Step 4** | minimise `CE_Total` further | < 10 s | < 30 % | < 2.5 |

Note Design 1's overshoot (31.4 %) already **exceeds** the 30 % limit imposed from Step 2
onward — so Design 1 is a starting point, not a compliant design. Steps 3 and 5 require
the *measured* reduction factor to be at least two, and Tutorial 3 explicitly permits
measured values to disagree with simulation while insisting the **factor** be observed.

---

## 9. Units and conventions

| Symbol | Meaning | Unit |
|---|---|---|
| `φ`, `φ_cmd` | rotor angle — **commanded, no sensor** | deg (rad in models) |
| `θ`, `θ_cmd` | pendulum angle — **measured** | deg (rad in models) |
| `u` | plant input, rotor angular acceleration demand | plant-input units (OI-7) |
| `K_P-Pend`, `K_P-Rotor` | proportional gains | 1/s² |
| `K_d` | `K_P·T_d` | 1/s |
| `ω_r`, `ω_g` | pendulum coefficients | rad/s |
| `Q` | quality factor | — |
| `T_s` | sample period | 0.002 s |

Errors are `reference − measurement` in both loops. Sign conventions remain **UNDETERMINED**
(OI-2). In a two-loop system a sign error is worse than in one: an inverted inner loop
*anti-damps* the pendulum, driving the `Q = 27` resonance rather than damping it.

---

## 10. What can and cannot be measured on the Edukit

**Can:** pendulum angle (encoder); commanded rotor angle; plant input `u`; and from these,
step response, settling, overshoot, and all three control-effort metrics.

**Cannot:** actual rotor angle (no sensor — EXP001); actuator current/power; `ω_r`, `ω_g`,
`Q` directly (these need system identification, and the values used here are
**REFERENCE/ASSUMED**, not measured on this rig — open item **OI-9**).

---

## 11. Assumptions

| ID | Assumption | If false | Tested where |
|---|---|---|---|
| C1 | `G_rotor = 1/s²` | all predictions wrong | OI-7, hardware |
| C2 | `G_pend` with `ω_r²=0.803, ω_g²=57.01, Q=27` | wrong inner damping | **OI-9** — reference values, not this rig |
| C3 | Suspended mode; pendulum stable | inverted mode is EXP005 | procedure |
| C4 | Plant input is the *sum* of both controllers | wrong loop structure | corroborated by UCLA reference |
| C5 | Loop linear over the excitation | CE metrics meaningless | saturation abort |
| C6 | `T_s` uniform at 2 ms | derivative biased | not characterised |
| C7 | Rotor position model tracks the arm | feedback of a fiction | EXP001 P3 |

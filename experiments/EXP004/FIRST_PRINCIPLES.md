> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP004/`.

# EXP004 — First-Principles Derivation

**Source:** Tutorial 4 — *Design of MIMO Systems: Performance Analysis with Sensitivity
Functions* · **Depends on:** EXP003 · **Parameter set:** `PS-EDUKIT01-v1`

---

## 1. What EXP004 adds to EXP003

Two things, and Tutorial 4 §1 states both.

**A second output to satisfy.** EXP003 designed for rotor-angle performance and control
effort. But "application of a Reference Tracking input signal to the MIMO system results
in **Pendulum Angle displacement** in addition to Rotor Angle." A rotor command
*necessarily* disturbs the pendulum — the two outputs share one actuator. EXP004 requires
settling objectives on **both**.

**A robustness constraint.** Plant and controller characteristics vary — supply voltage,
temperature, manufacturing tolerance. Tutorial 4 §5: feedback's central achievement is
"stable and reproducible performance in the presence of these variations". EXP004
quantifies that with the sensitivity function and constrains it.

---

## 2. The sensitivity function, derived (Tutorial 4 §5)

Tutorial 4 derives `S` from its *meaning*, not by asserting a formula. Define fractional
changes:

```
    fractional change in T = δT/T          fractional change in P = δP/P
```

The sensitivity is the limit of their ratio:

```
                 δT/T          P   dT
    S(s) ≡ lim  ───────   =   ─── ────
           δ→0   δP/P          T   dP
```

With `T = PC/(1+PC)`:

```
    dT/dP = C/(1+PC)²
```

so

```
             P        C          P (1+PC)      C              1
    S(s) = ────── ─────────  =  ───────── ──────────  =  ──────────
            T     (1+PC)²         PC       (1+PC)²        1 + PC
```

```
    ┌──────────────────────┐
    │  S(s) = 1/(1 + P C)  │
    └──────────────────────┘
```

**This is why `S` matters.** It is not merely "the transfer function from disturbance to
error" — it is *literally* the factor by which a fractional plant error is transmitted to
closed-loop behaviour. `|S| = 0.5` means a 10 % plant error produces a 5 % behaviour
change. `|S| = 2` means it produces 20 %.

For EXP004, `P = T_rotor` (the inner closed loop from EXP003) and `C = K_rotor`.

---

## 3. Metrics (Tutorial 4 §6)

```
    M_S  = max over ω of |S(jω)|        reported in dB
    ω_SC = the frequency where |S(jω_SC)| = 1
```

Below `ω_SC`, `|S| < 1` — plant variation is *attenuated*. Above it, `|S| > 1` — plant
variation is *amplified*. `M_S` is the worst case anywhere.

**Design objectives: reduce `M_S`, increase `ω_SC`**, while meeting settling and overshoot.

### Nyquist interpretation, and why it is the same statement

```
    1/S = 1 + P C
```

which is exactly the vector from the point `(−1, 0)` to `L(jω) = P(jω)C(jω)`. Therefore

```
    |V_S| = 1/|S|      and      M_S = 1 / min |1 + L(jω)|
                                       ω
```

**`M_S` is the reciprocal of the Nyquist curve's closest approach to `−1`.** Drawing the
unit circle about `(−1,0)`: `|S| < 1` outside it, `|S| > 1` inside. A large `M_S` and a
small stability margin are the same fact seen two ways.

This identity is *verified numerically* rather than asserted: computed
`min|1+L| = 0.724935` against `1/M_S = 0.724935`, agreeing to **1.1×10⁻¹⁶**.

---

## 4. Why no derivative filter here — and why EXP003 needed one

EXP003 quoted every `CE_Max` with a derivative-filter corner `N`, because `CE(s)` is
improper and its time-domain peak is meaningless without a realisation.

`M_S` and `ω_SC` are **frequency-domain metrics of a proper transfer function**. No
discretisation, no realisation, no filter. The evidence confirms the tutorial does the
same:

| Controller | `M_S` |
|---|---|
| **ideal (no filter)** | **2.794 dB** |
| with `N = 100 rad/s` | 3.121 dB |
| with `N = 50 rad/s` | 3.457 dB |

Tutorial 4 publishes **2.7 dB**. The ideal controller agrees to **0.094 dB**; adding a
filter moves *away* from the source. EXP004 therefore uses the ideal controller
throughout, and this is a deliberate, evidenced difference from EXP003, not an
inconsistency.

---

## 5. Validation against the source

| Quantity | Tutorial 4 | Computed | Agreement |
|---|---|---|---|
| `M_S` for `K_P=6, K_d=4.8` (simulation, Fig. 7) | 2.7 dB | **2.794 dB** | 0.094 dB |
| `M_S` measured on hardware (Fig. 11) | 2.4 dB | — | **not reproduced; no rig** |
| Nyquist identity `M_S = 1/min|1+L|` | asserted | verified | **1.1×10⁻¹⁶** |

Tutorial 4 itself notes its measured 2.4 dB is "in close agreement with the simulation
result" of 2.7 dB — a 0.3 dB simulation-vs-hardware gap, which sets a realistic
expectation for what this rig should show.

---

## 6. The second output

The pendulum response to a rotor reference step is

```
    θ(s)/φ_command(s) = G_pend(s) · T_rotor-tracking(s)
```

Because `G_pend(0) = 0` (the `s²` numerator), the pendulum **returns to zero** — it is
displaced in transit, not permanently deflected. Its settling therefore has no non-zero
final value, so it is measured as the last time it lay outside a band around **zero**,
scaled to its own peak excursion. Using the rotor's convention on the pendulum would
divide by a final value of ~0.

Both conventions are implemented in `enr312_metrics.c` and separately tested.

---

## 7. Design objectives (Tutorial 4 §8)

Search range: `0.25 ≤ K_P ≤ 5`, `0.25 ≤ K_d ≤ 5`.

| Step | `M_S` limit | Objective | Overshoot |
|---|---|---|---|
| **Step 1** | < 1 dB | minimum settling time | < 30 % |
| **Step 2** | < 3 dB | minimum settling time | < 30 % |

### Results

| Design | `K_P` | `K_d` | `M_S` | `ω_SC` | Rotor settling | Overshoot | Pend. peak | Pend. settling |
|---|---|---|---|---|---|---|---|---|
| Reference | 6.00 | 4.80 | 2.794 dB | 3.63 rad/s | 2.085 s | 30.72 % | 0.258 | 2.60 s |
| **A** (Step 1) | 1.20 | 1.50 | **0.995 dB** | 1.29 rad/s | 4.492 s | 25.65 % | **0.100** | 2.56 s |
| **B** (Step 2) | 0.25 | 4.80 | **1.857 dB** | **4.60 rad/s** | **1.887 s** | **9.00 %** | 0.237 | 2.60 s |

---

## 8. A finding the tutorial does not state

Tutorial 4's objectives contain **no control-effort constraint**. Evaluating the EXP004
designs with EXP003's metrics (`N = 100 rad/s`):

| Design | `M_S` | Rotor settling | `CE_Max` | `CE_Total` |
|---|---|---|---|---|
| Reference (`6, 4.8`) | 2.794 dB | 2.10 s | 480 | 10.90 |
| EXP003 Design 2 (`1.5, 1.725`) | — | 3.99 s | 172 | 3.76 |
| **A** (`1.2, 1.5`) | 0.995 dB | 6.03 s | **150** | **3.30** |
| **B** (`0.25, 4.8`) | 1.857 dB | 1.91 s | **480** | **10.27** |

**Design A is simultaneously the most robust and the cheapest** — low `M_S` and low
control effort are aligned there, which is not obvious in advance.

**Design B is not.** It reaches the best settling and overshoot of any design while
satisfying `M_S < 3 dB`, but costs as much as the unconstrained reference. Its `T_d` is
19.2 s — a nearly pure-derivative controller. Since the control-effort transfer function
*is* the noise sensitivity function (Tutorial 3 §5), such a design also amplifies
measurement noise heavily.

**EXP003's objective and EXP004's objective are not automatically compatible.** A design
can satisfy one while failing the other, and neither tutorial alone reveals it.

> Note also that Design A's rotor settling differs between the two experiments — 4.49 s
> (EXP004, ideal controller) versus 6.03 s (EXP003, `N = 100` filter). The derivative
> filter genuinely slows the loop. Metrics must be quoted with their realisation.

---

## 9. Units and conventions

Unchanged from EXP003. Additionally:

| Symbol | Meaning | Unit |
|---|---|---|
| `S(jω)` | sensitivity | dimensionless (dB for display) |
| `M_S` | `max|S|` | dimensionless; **dB when stated in dB** |
| `ω_SC` | sensitivity crossover | rad/s |
| `L(jω)` | open loop `T_rotor·K_rotor` | dimensionless |

`M_S` in dB is `20·log₁₀(M_S)` — an amplitude ratio, not a power ratio.

---

## 10. What can and cannot be measured

**Can:** `S(jω)` and hence `M_S`, `ω_SC` and the Nyquist curve, computed offline from
step-response data — which is exactly what Tutorial 4's analysis tools do. Both outputs'
settling. Tutorial 4 Figure 11 shows this measurement succeeding on the real Edukit.

**Cannot:** `S(jω)` on the target in real time (and it is not worth the flash — the host
does it better); plant parameter variation directly (only its *effect*); `ω_r², ω_g², Q`
(**OI-9** — still another rig's values).

---

## 11. Assumptions

Inherits C1–C7 from EXP003, plus:

| ID | Assumption | If false | Tested where |
|---|---|---|---|
| D1 | Ideal (unfiltered) `K_rotor` for frequency-domain metrics | `M_S` shifts ~0.3 dB per realisation | validated against Tutorial 4's 2.7 dB |
| D2 | `S = 1/(1+PC)` with `P = T_rotor` | wrong loop broken for the analysis | Nyquist identity verified to 1e-16 |
| D3 | Linear operation over the excitation | frequency-domain metrics meaningless | saturation abort |

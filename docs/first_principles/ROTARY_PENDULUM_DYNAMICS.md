# Rotary pendulum dynamics: first principles and an audit of the MATLAB model

**Date:** 2026-10-11 · **Status:** derivation complete; numerically validated in
MATLAB R2026a (14/14, `matlab/validation/rotary_pendulum_validate_physics.m`);
compared with the rig on 2026-10-21 (update below).

> **Status update, 2026-10-22: compared with the rig.**
>
> - **ωg².** Six free swings give ωg² = 48.0 ± 0.5 rad²/s², not the Tutorial's 57.01 or
>   55.85 (`results/reports/2026-10-21d_rig_session.md`). The rod is 0.26 m, the
>   Tutorial's length. So the rig's pendulum is not the uniform rod of §6: its mass sits
>   further from the pivot (a tip mass of about 28 % of the rod's would do it).
> - **ωr².** It follows from ωr² = ωg²·r/g (§6) with r = 0.14 m: 0.685, not 0.803.
> - **Damping.** Assumption A3 (viscous damping) is wrong for this pivot. Small swings
>   decay by dry (Coulomb) friction, about 0.35–0.40 rad/s², and large swings lose more
>   than that, about a viscous Q of 60 on top. The host plant and the MATLAB
>   simulation now include dry friction with sticking.
> - **Linearisation.** The linearisation and the sign flip (§5) are confirmed by every
>   balancing run.
>
> The derivation below is unchanged.

This document answers one question: *are the dynamics in the MATLAB simulations
right?* Short answer:

* **For balancing (|α| < 1°), the Tutorial's linear model is accurate.** It is
  exactly the small-angle limit of rigid-body physics; the nonlinear and linear
  simulations agree to 4 significant figures.
* **Its parameters are not this rig's.** They come from the Tutorials (OI-9),
  and two of them contradict each other at the 2 % level (§6).
* **Two sign issues matter on hardware.** The pendulum-to-arm coupling changes
  sign between hanging and upright in the encoder's coordinate (§5). The old
  3-D animation also drew the tilt the wrong way round; that is now fixed.
* What the model still leaves out: stepper torque limits, missed steps,
  Coulomb friction, sensor noise and I/O delay (§8).

---

## 1. Physical system

STEVAL-EDUKIT01: a NEMA17 stepper with its shaft **vertical** turns a horizontal
arm. At the arm tip, a distance **r** from the motor axis, an LPD3806 encoder is
mounted with its shaft **radial** (along the arm). The pendulum, approximately a
uniform rod, is clamped to the encoder shaft, so it swings in the vertical plane
**perpendicular to the arm**.

## 2. Coordinates and sign conventions

| Symbol | Meaning | Unit | Zero | Positive sense |
|---|---|---|---|---|
| θ | arm angle about the vertical motor axis | rad | `z` datum | counter-clockwise seen from above (to be confirmed: EXP001 P1) |
| ψ | pendulum angle about the radial encoder axis, **one absolute coordinate** | rad | hanging straight down | the sense in which the *hanging* pendulum swings when the arm accelerates in +θ |
| α | Tutorial-5 deviation from upright, α = π − ψ | rad | upright | rod tilts toward −θ (the way it lags when the arm accelerates in +θ) |
| r̂, t̂, ẑ | radial, tangential (+θ direction), vertical up | — | — | right-handed |

## 3. Assumptions

| # | Assumption | Consequence if false |
|---|---|---|
| A1 | The arm motion θ(t) is **imposed**: a microstepping stepper follows its step train | missed steps break it; the model cannot see them (§8) |
| A2 | Pendulum is a rigid body; J is its inertia about the pivot axis | flexible rod adds modes; not expected at these frequencies |
| A3 | Pivot friction is viscous: torque −c ψ̇ | Coulomb/stiction gives amplitude-dependent decay (§8) |
| A4 | Arm is rigid and horizontal; pivot axis exactly radial | small tilt adds a gravity component along the arm |
| A5 | The rod is thin: its inertia about the axis through its own length is negligible | changes the centrifugal term by < 1 % |

## 4. Derivation

Work in the frame rotating with the arm, angular velocity Ω = θ̇ ẑ, origin at the
pivot. A rod element dm at distance s from the pivot, along the rod, sits at

    p(s) = −s sinψ t̂ − s cosψ ẑ        (relative to the pivot)

The only generalised coordinate is ψ; ∂p/∂ψ = −s cosψ t̂ + s sinψ ẑ.
The forces per element, in the rotating frame:

1. **Gravity** −g dm ẑ  →  generalised force  −g s sinψ dm
2. **Pivot acceleration** (the pivot is at radius r): the tangential component
   r θ̈ t̂ appears as the pseudo-force −r θ̈ dm t̂  →  +r θ̈ s cosψ dm.
   The centripetal component −r θ̇² r̂ is along the pivot axis, so it does no work.
3. **Centrifugal** θ̇² × (horizontal distance from the motor axis): only the t̂
   part −s sinψ does work  →  θ̇² s² sinψ cosψ dm
4. **Coriolis** −2Ω × v: v lies in the (t̂, ẑ) plane, so Ω × v is along r̂,
   the pivot axis. No work.
5. **Euler** −Ω̇ × p: its t̂ part is the pivot term already counted; the r̂ part
   is along the axis. No work.

Integrate over the rod, with m lc = ∫ s dm and J = ∫ s² dm, and add damping:

    J ψ̈ = −m g lc sinψ + m r lc cosψ θ̈ + J θ̇² sinψ cosψ − c ψ̇            (5)

Divide by J:

    ψ̈ = −ωg² sinψ + ωr² cosψ θ̈ + θ̇² sinψ cosψ − γ ψ̇                       (6)

    ωg² = m g lc / J,   ωr² = m r lc / J,   γ = c / J = ωg / Q

Equation (6) is `matlab/models/rotary_pendulum_psiddot.m`. The arm obeys
θ̈ = u, the acceleration the firmware commands.

## 5. Linearisation, and the sign flip

**Hanging** (ψ small): ψ̈ + γψ̇ + ωg²ψ = **+ωr²** θ̈, so

    G_pend,susp(s) = ωr² s² / (s² + γ s + ωg²)        = Tutorial 3/12 exactly

**Upright** (ψ = π + δ): sinψ ≈ −δ, cosψ ≈ −1, so δ̈ + γδ̇ − ωg²δ = **−ωr²** θ̈.

In the encoder's own coordinate, the coupling **changes sign** between the two
modes. The Tutorial 5 model G_pend = +ωr² s²/(s² + γs − ωg²) holds for
α = π − ψ = −δ, i.e. an angle measured in the *opposite* sense to the hanging one.

**Hardware consequence (new; critical for EXP005).** If EXP005 feeds the encoder
angle to the Tutorial-5 inner controller with the hanging-mode sign, the inner
loop has positive feedback. The lab reproduces this with the preset *Pendulum
encoder sign wrong*: the pendulum is lost **0.17 s** after the first disturbance.
The required firmware convention is therefore:

> **α (EXP005) = −(ψ − π), with ψ in the same sense as EXP003.**
> Operational check before closing the loop: with the pendulum held upright and
> the motor ARMED but not running, tilt the pendulum toward −θ by hand. α must
> read **positive**.

This is separate from the Tutorial-5 *outer-loop* sign inversion already in
`exp005_inverted_model.m`. That one follows from T_rotor's negative DC gain, and
both are needed.

The old 3-D animation drew +α toward +θ, which is the wrong way. Corrected in
`exp005_lab.m` (2026-10-11).

## 6. Do the Tutorial parameters agree with physics?

| Check | Physics says | Tutorial values give | Verdict |
|---|---|---|---|
| ωr² / ωg² = r / g | r ≈ 0.14 m (Edukit manual) | 0.1410 m (T5), 0.1382 m (T3/12) | **consistent** to 1.3 % |
| ωg² = g / (L · k), with k = J/(m lc L) | k = 2/3 for a uniform rod | 0.6805 | consistent with a rod plus a small clamp or encoder hub at its end |
| ωg² the same hanging and upright (one rigid body) | **equal** | 57.01 vs 55.85 | **conflict, 2.1 %** |
| Q the same hanging and upright (same bearing) | roughly equal | 27 vs 20 | plausible (load-dependent friction), unproven |

The 2.1 % disagreement in ωg² cannot come from the physics in §4. Either the two
Tutorials identified their rigs separately, or a model term is missing. **Resolve
it on this rig with the free-swing test (§9). Do not average the two values.**

## 7. Size of each nonlinear term, at the EXP005 limits

| Term | Ratio to the linear term | Value |
|---|---|---|
| sin α vs α at the 15° abort | sin(15°)/(15° in rad) | 0.989 (1.1 % weaker gravity) |
| cos α θ̈ vs θ̈ at 15° | cos 15° | 0.966 |
| centrifugal θ̇² vs ωg² at θ̇ = 50 °/s | 0.762 / 55.85 | 1.4 % |

Inside the ±2° capture band, every nonlinear correction is below 0.1 %. That is
why linear design (Tutorials 3–5) is sound for balancing. Nonlinearity matters
for falls, swing-up and large free swings.

## 8. What the model still does NOT contain

* **Stepper torque.** A1 holds only while the motor can supply
  τ = J_arm θ̈ + (pendulum reaction). With ASSUMED inertias (aluminium arm 71 g,
  encoder 100 g at 0.122 m, rod 30 g at 0.141 m; J ≈ 2.6×10⁻³ kg·m²), the
  firmware's ±1500 °/s² limit needs about **0.07 N·m**. A typical NEMA17 holds
  0.3–0.5 N·m, but **pull-out torque falls with speed, and neither has been
  measured.** If the motor slips, θ in the firmware (a step count) diverges from
  the real arm angle, and nothing detects it.
* Coulomb friction and stiction at the pivot (A3), encoder noise, USB/UART delay,
  the stepper's own resonance, and arm flex.
* Rotor scale conflict C-1 (8.889 vs 17.778 microsteps/°). The model uses 8.889.

## 9. How the rig settles the parameters: the free-swing test

Motor unpowered, pendulum hanging. Displace it 20–40°, release, and record the
encoder (MATLAB rig app → *Free-swing ID*). `matlab/identification/pendulum_free_swing_fit.m`
fits the **nonlinear** model (6) with θ̈ = 0, so large amplitudes are handled
exactly. A linear fit would bias ωg² low by about 3.4 % at 30° (the period is 1.7 % longer), larger
than the Tutorial conflict itself. Validated on synthetic data with encoder quantisation:
ωg² recovered within 0.03 %, Q within 0.2 %, the datum offset within 0.01°.

The result replaces the Tutorial ωg² and Q in `rotary_pendulum_params.m`, with
its provenance recorded. ωr² then follows from r (measured with a ruler) via
ωr² = ωg² r / g.

## 10. Validation evidence (MATLAB R2026a, executed 2026-10-11)

`rotary_pendulum_validate_physics`: **14/14 PASS**:
r implied (both Tutorials), linearisation coefficients (four, including the sign
flip), period at 1° and 40° against the exact elliptic-integral law (to 2×10⁻⁴),
energy drift 2×10⁻¹¹ over 10 s undamped at 60°, upright fall 1°→15° against the
closed-form linear solution (0.4634 vs 0.4631 s; nonlinear correctly slower),
and three free-swing identification checks.

> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP001/`.

# EXP001 — First-Principles Derivation

Parameter set: `PS-EDUKIT01-v1` (`shared/parameters/edukit01_rig.yaml`)
Source revision: 44bda39

EXP001 is deliberately **not** about pendulum dynamics. No equation of motion appears
here. EXP001 establishes the two chains that every later experiment silently assumes are
correct:

```
        control software                                     control software
              |                                                     ^
              v                                                     |
   [ACTUATION CHAIN]  command -> motion              [SENSING CHAIN]  motion -> number
```

If either chain is wrong — wrong scale, wrong sign, wrong origin, lost counts, lost steps
— then every model, every gain, and every stability claim downstream is wrong, and it
will be wrong in a way that looks like a physics problem rather than a wiring problem.
That is the reason this experiment comes first.

---

## 1. Physical system and coordinates

Two rotational degrees of freedom about two distinct axes.

**Rotor (arm).** A horizontal arm driven by the stepper about a vertical axis.

- Coordinate: `theta_r`, the arm angle.
- Origin: `theta_r = 0` at the arm position latched at firmware start. It is an
  arbitrary datum, not a physical feature. EXP002 is what gives it meaning.
- Positive sense: **defined by the actuator**, as the direction the arm moves when the
  L6474 DIR pin is asserted to its `FORWARD` state. It is *chosen*, then *measured*.
- Unit: rad (rad is used for all model work; deg is used only for human-facing display).

**Pendulum.** A rod free to rotate about a horizontal axis carried at the arm tip.

- Coordinate: `theta_p`, the pendulum angle.
- Origin: `theta_p = 0` at the encoder counter value latched at firmware start. Again
  arbitrary — the encoder is *incremental*, so it has no absolute reference and cannot
  have one. The physically meaningful origin (hanging, or upright) is EXP002's job.
- Positive sense: defined by the encoder A/B channel order and the timer's decode
  direction. Also chosen, then measured.
- Unit: rad.

Both origins are latched-at-start, both positive senses are conventions. **The purpose of
EXP001 is not to assume these; it is to determine them and write them down.**

---

## 2. The actuation chain, derived

### 2.1 Why a stepper changes the nature of "command"

A DC motor takes a voltage and produces a torque; position is the double integral of
what you commanded, and you need a sensor to know where you are. A stepper driven in
position mode is different in kind: each step pulse advances the rotor by one fixed
mechanical increment. Position is the *count of pulses issued*, which the software knows
exactly, with no sensor.

This is the answer to the handout's reflection question — *why does the system need an
encoder only on the pendulum and not on the arm?* Because the arm's position is not
measured, it is **commanded and remembered**. The arm has an open-loop position sensor
made of arithmetic.

This is also the chain's single point of failure. It holds only while **no step is
lost**. If the commanded acceleration exceeds what the motor can deliver against the
load's inertia and friction, the rotor slips a pole, the physical arm falls behind, and
the software's position variable is now permanently wrong with no way to detect it. There
is no error signal — the firmware remains perfectly confident. EXP001 must therefore test
step fidelity, not assume it.

### 2.2 Command to angle

Let

- `S_full` = full steps per revolution = 200 (1.8°/step)
- `m` = microstep divisor = 16
- `S = S_full * m` = 3200 microsteps/rev

One microstep is

```
    delta_theta_r = 2*pi / S = 2*pi / 3200 = 1.963495e-3 rad = 0.1125 deg
```

After `n` net microsteps (signed, forward positive), the arm angle is

```
    theta_r(n) = n * 2*pi/S                                             ... (1)
```

Equivalently `8.888889 microsteps per degree`, which reproduces the reference project's
`STEPPER_READ_POSITION_STEPS_PER_DEGREE = 8.888889` exactly — an independent confirmation
that the 200 x 16 assumption is the one that reference rig used.

**Microstepping is an amplitude trick, not a precision guarantee.** The L6474 divides a
full step by modulating the two phase currents sinusoidally. The *nominal* increment is
uniform, but the *achieved* increment is not: detent torque, phase-current error, and any
load torque cause the true rotor angle to deviate within the full-step envelope. A useful
rule is that microstep positioning error can approach one full step under load, i.e. up to
16x the nominal increment. Therefore:

> Equation (1) is a **command model**, not a measurement. Its accuracy at full-step
> granularity is credible; its accuracy at microstep granularity is not, and EXP001 does
> not have the instrumentation to prove otherwise.

This is recorded as assumption A3 and limitation L2.

### 2.3 Step rate and its quantisation

The step clock is generated by a timer interrupt (see parameter set; the STCK pin is a
plain GPIO toggled in the ISR, not a hardware PWM output). With prescaler `P = 1024` and
`f_sys = 84 MHz`, the timer tick rate is

```
    f_tick = f_sys / P = 84e6 / 1024 = 82031.25 Hz
```

and the auto-reload for a requested step rate `f_cmd` is

```
    ARR = round( f_tick / f_cmd ) - 1                                    ... (2)
```

Because `ARR` is an integer, the achieved rate is

```
    f_act = f_tick / (ARR + 1)                                           ... (3)
```

Evaluating (2)-(3):

| `f_cmd` (steps/s) | ARR | `f_act` (steps/s) | error |
|---|---|---|---|
| 200 | 409 | 200.08 | +0.038 % |
| 500 | 163 | 500.19 | +0.038 % |
| 1000 | 81 | 1000.38 | +0.038 % |
| 2000 | 40 | 2000.76 | +0.038 % |
| 10000 | 7 | 10253.91 | **+2.54 %** |

The error is negligible at moderate rates and becomes significant above a few thousand
steps/s, where only a handful of timer ticks remain per step. Note this is a *rate* error,
not a *position* error — the position model (1) counts pulses actually issued, so rate
quantisation costs speed accuracy, not position accuracy, as long as no step is lost.

A second consequence of the software-toggled step clock: the ISR fires on every step
edge. At 10 000 steps/s that is a 10 kHz interrupt competing with a 500 Hz control loop.
Whether that is tolerable is an EXP003 question; EXP001 records it as an observation.

### 2.4 Angular velocity of the arm

```
    omega_r = f_step * 2*pi/S     [rad/s]                                ... (4)
```

so 1000 steps/s corresponds to `1000 * 1.9635e-3 = 1.9635 rad/s = 112.5 deg/s`.

---

## 3. The sensing chain, derived

### 3.1 From shaft to counts

The encoder is a 600-pulse-per-revolution incremental optical quadrature encoder. Two
photodetectors observe the same slotted disc through masks offset by a quarter of a slot
pitch, producing square waves A and B in quadrature — 90° out of phase.

Two facts follow directly from that geometry, and they are the whole reason quadrature is
used:

1. **Direction is recoverable.** Whether A leads B or B leads A distinguishes the two
   senses of rotation. A single channel could not: it produces an identical pulse train
   either way.
2. **Resolution can be multiplied by four.** A and B together have four distinguishable
   states (00, 01, 11, 10) per pulse period, and transitions between them are unique to a
   direction. Counting *every edge of both channels* — X4 decoding — yields four counts
   per encoder pulse.

Hence

```
    N = P_enc * 4 = 600 * 4 = 2400 counts per revolution                 ... (5)
```

X4 is a property of **the timer configuration we choose**, not of the encoder. A timer set
to X2 or X1 would produce 1200 or 600 counts/rev from the identical hardware. This is a
firmware decision and must be verified, not assumed — it is exactly the kind of silent
factor-of-two/four that corrupts an entire model.

The angular resolution is

```
    q = 2*pi/N = 2*pi/2400 = 2.617994e-3 rad = 0.15 deg per count        ... (6)
```

`N/360 = 6.666667 counts/deg`, again reproducing the reference's
`ENCODER_READ_ANGLE_SCALE = 6.666667` exactly.

### 3.2 The measurement equation

Let `c[k]` be the hardware counter value at sample `k` and `c_0` the value latched at
start. The measured pendulum angle is

```
    theta_p_meas[k] = s * ( c[k] - c_0 ) * q                             ... (7)
```

with `s = +1 or -1` the polarity constant. Equation (7) contains every assumption of the
sensing chain, and it is worth being explicit about what each symbol hides:

- `q` encodes the PPR and the decode multiplier. Wrong by 4x if X4 is assumed but X1 is
  configured.
- `s` encodes A/B wiring order and the timer's direction convention. A sign error here
  turns negative feedback into positive feedback — the controller drives the pendulum away
  from the setpoint and the rig fails violently. This is the single most dangerous
  unverified quantity in the whole system.
- `c_0` encodes the origin. Arbitrary until EXP002.

The reference project used `s = -1`. **That is a fact about the reference rig, not about
this one.** It is recorded and deliberately not inherited.

### 3.3 The 16-bit counter and modular arithmetic

TIM3 is a 16-bit counter with `ARR = 65535`. It wraps. Equation (7) as written is wrong
across a wrap: `c` steps from 65535 to 0 and the naive difference is −65535 counts, an
apparent instantaneous jump of −27.3 revolutions.

The correct treatment is to accumulate signed differences in modular arithmetic. Define
the wrapped difference

```
    d[k] = ((c[k] - c[k-1] + 2^15) mod 2^16) - 2^15                      ... (8)
```

which maps the raw difference into `[-32768, +32767]`, then accumulate into a wide
(64-bit) position:

```
    C[k] = C[k-1] + d[k],     theta_p_meas[k] = s * C[k] * q             ... (9)
```

This is correct **if and only if** the true motion between samples is less than half a
counter period. The condition is

```
    |d_true| < 2^15 counts
```

Converting to a speed limit with `Ts = 2 ms` and `N = 2400`:

```
    omega_max = 2^15 / N / Ts = 32768 / 2400 / 0.002 = 6827 rev/s        ... (10)
```

That is roughly 410 000 rpm. The physical pendulum will not approach 0.01 % of it. **The
wrap-safe algorithm is therefore unconditionally valid for this rig at 500 Hz**, and this
is a derived guarantee rather than a hope. It is worth stating explicitly because the same
algorithm at, say, 1 Hz sampling would be marginal.

Note the accumulator must be wider than 16 bits: at ±120° of travel the count stays small,
but a free-spinning pendulum during swing-up accumulates without bound. A 64-bit
accumulator overflows after ~3.8e15 revolutions and can be ignored.

### 3.4 Quantisation: what the number cannot tell us

The counter is exact — it is a count of real edges. The *angle* is not, because the
underlying continuous angle is only known to lie within one count. Model the residual as
uniform on `[-q/2, +q/2]`:

```
    E[e] = 0,     Var[e] = q^2/12,     sigma_theta = q/sqrt(12)          ... (11)
```

```
    sigma_theta = 2.617994e-3 / 3.4641 = 7.5575e-4 rad = 0.0433 deg
```

This is a *bias-free* error of about 0.043° — excellent for position. The problem appears
when velocity is estimated by differencing.

### 3.5 Velocity estimation and noise amplification

The obvious estimator is the backward difference

```
    omega_hat[k] = ( theta[k] - theta[k-1] ) / Ts                        ... (12)
```

Its **granularity** is one count per sample:

```
    q / Ts = 2.617994e-3 / 0.002 = 1.309 rad/s = 75 deg/s                ... (13)
```

The velocity estimate can only take values that are integer multiples of 1.309 rad/s. Its
**noise standard deviation**, treating consecutive quantisation errors as independent, is

```
    sigma_omega = sigma_theta * sqrt(2) / Ts = 0.534 rad/s = 30.6 deg/s  ... (14)
```

This is a large number, and it is the central quantitative result of EXP001's sensing
analysis. A pendulum moving slowly — precisely the regime near an equilibrium where a
balancing controller does its most delicate work — has a true velocity comparable to or
smaller than this noise. Feeding (12) raw into a derivative gain would inject roughly
`Kd * 0.53 rad/s` of noise straight into the actuator command.

Three consequences, all of which explain design choices found in the reference project
rather than merely asserting them:

1. **Low-pass filtering of the derivative is not optional.** The reference's
   `DERIVATIVE_LOW_PASS_CORNER_FREQUENCY = 10 Hz` exists because of (14). For a
   first-order filter `y[k] = y[k-1] + a*(u[k] - y[k-1])` with
   `a = 1 - exp(-2*pi*f_c*Ts)`, the steady-state noise gain is `sqrt(a/(2-a))`. At
   `f_c = 10 Hz` and `Ts = 2 ms` that gain is 0.254, reducing `sigma_omega` from
   0.534 rad/s to **0.136 rad/s** — a factor of 3.9. Computed and plotted in
   `results/figures/EXP001_fig2_velocity_noise_tradeoff.png`.
2. **Faster sampling makes velocity worse, not better.** `sigma_omega` scales as `1/Ts`.
   Halving the sample period doubles differentiation noise. Sampling rate must be chosen
   against loop-delay and bandwidth requirements, not by "faster is better".
3. **Resolution, not sample rate, is the lever.** `sigma_omega` scales linearly with `q`.
   This is the quantitative argument for X4 decoding: it divides the velocity noise by
   four relative to X1.

These relations are computed and plotted by `scripts/exp001_sensing_analysis.py`.

---

## 4. Sampling and timing

`Ts = 2 ms`, `fs = 500 Hz`, Nyquist 250 Hz. Two independent facts are bundled in "500 Hz"
and must not be conflated:

- **Rate** — how often a sample is taken. Sets the Nyquist limit and, with (13)-(14), the
  velocity noise.
- **Regularity** — how nearly constant the interval is. Every discrete-time model, and
  the `1/Ts` in (12), assumes uniform spacing. Jitter makes the effective `Ts` a random
  variable, and (12) then produces a velocity error proportional to the jitter fraction.

EXP001 only *assumes* both. Establishing them by measurement is EXP003's entire purpose,
and EXP001 must not claim them.

---

## 5. Assumptions

| ID | Assumption | If false | Tested where |
|---|---|---|---|
| A1 | Rig is STEVAL-EDUKIT01 as the handout states | All constants wrong | EXP001 P0 |
| A2 | No steps are lost at the rates commanded | Arm position silently drifts from truth | EXP001 P3 |
| A3 | Microstep increments are uniform | Fine-grained position error up to ~1 full step | Not tested; limitation L2 |
| A4 | Encoder is 600 PPR and decoded X4 | Angle scale wrong by an integer factor | EXP001 P2 |
| A5 | No missed encoder edges (adequate pull-up, no EMI) | Origin drifts, permanently | EXP001 P4 |
| A6 | Motion between samples < half a counter period | Wrap logic mis-decodes | Proved by (10); margin 1e5 |
| A7 | Sample interval is uniform at 2 ms | Velocity estimate biased | EXP003 |
| A8 | Rotor and pendulum axes are mechanically rigid | Commanded arm angle != actual arm angle | Not tested; limitation L3 |

---

## 6. What EXP001 establishes, and what it does not

**Establishes:** the scale, sign and origin of both chains; that commanded arm motion
produces the predicted physical motion; that the encoder responds with the correct
resolution and a known direction; that counts are not lost.

**Does not establish:** any dynamic property. No inertia, no friction, no damping, no
natural frequency, no transfer function, no stability claim. Those require EXP004 and a
model this experiment deliberately does not build.

# Design: decisions, model, metrics, parameters

This page explains why the system is built the way it is, what each number means, and
where it comes from. The structure itself is in [ARCHITECTURE.md](ARCHITECTURE.md), the
derivation of the physics in
[first_principles/ROTARY_PENDULUM_DYNAMICS.md](first_principles/ROTARY_PENDULUM_DYNAMICS.md).

## 1. The model in one equation

The pendulum is a rigid body on a rotating arm. With ψ its angle from hanging, θ the arm
angle, and u = θ̈ the arm acceleration the firmware commands:

    ψ̈ = −ωg² sin ψ + ωr² cos ψ · u + θ̇² sin ψ cos ψ − γ ψ̇ − c · sgn ψ̇

| Term | Physics | This rig |
|---|---|---|
| −ωg² sin ψ | gravity; ωg² = m g lc / J | 48.0 ± 0.5 rad²/s², measured (six free swings) |
| ωr² cos ψ · u | the arm's acceleration pushes the pivot sideways; ωr² = m r lc / J | 0.685 = ωg²·r/g with r = 0.14 m |
| θ̇² sin ψ cos ψ | centrifugal | small: about 1.6 % of gravity at 50 deg/s |
| −γ ψ̇ | viscous loss, γ = ωg/Q | Q ≈ 60 at large swings; not measurable at small ones |
| −c sgn ψ̇ | dry (Coulomb) pivot friction, with sticking below c | 0.35–0.40 rad/s² from small free swings |

Upright, the gravity term changes sign and the pendulum is unstable, with a pole at
+√ωg² = 6.9 rad/s. In the deviation δ = ψ − 180° the arm coupling also changes sign:
δ̈ = ωg² δ − ωr² u. Tutorial 5 measures the other way, α = 180° − ψ, so that
α̈ = ωg² α + ωr² u. The firmware uses α.

One identity carries much of the work: **ωr²/ωg² = r/g for any rigid pendulum**,
whatever its shape. A free swing (giving ωg²) and a ruler (giving r) therefore
determine both constants.

## 2. Decisions, and why

### Hardware and firmware

**D1. Bare metal, one 500 Hz timer interrupt for control.**
- *Why:* a balancing pendulum needs the same delay every tick.
- *How:* the interrupt reads the encoder, runs the controller and sets the step rate;
  the main loop only talks to the PC, so communication cannot delay control. No RTOS
  is needed for one control loop, and none means nothing to schedule wrongly.
- *Evidence:* the worst-case interrupt time is measured on every boot with the cycle
  counter: 11–216 µs of the 2000 µs budget.

**D2. The stepper is treated as an acceleration source.**
- *Why:* a stepper cannot be torque-controlled, but it follows a step train exactly.
- *How:* the controller outputs an arm acceleration u, the runner integrates it to a
  velocity, and the velocity sets the step rate. The plant input of every model is
  therefore u, as in the Tutorials. The arm angle is the count of microsteps issued
  (8.889 per degree).
- *Evidence:* a protractor read 5° for 44 microsteps. The approach fails only if the
  motor loses steps. An estimate puts the torque at the 1500 deg/s² limit at about
  0.07 N·m, against 0.3–0.5 N·m typical holding torque for this motor size (not
  measured).

**D3. Portable control cores, tested on the PC.**
- *Why:* code that only runs on the board can only be tested on the board.
- *How:* all control logic lives in `firmware/enr312/src/`, with no hardware calls. The
  same files build into the firmware, the 479-check host test suite, and an emulator
  that runs them behind the real serial protocol.

**D4. A MATLAB twin of the C control code, checked line by line.**
- *Why:* a simulation that is "the same idea" as the firmware predicts what the idea
  does, not what the firmware does.
- *How:* `odyssix.sim.runTutorial` and `runCtrl` repeat the firmware's arithmetic in
  the same order, and `test_sim_matches_firmware` compares them with the C code
  (33 checks, agreement to 10⁻¹⁴ deg).
- *What it does not cover:* when a rig result differs from the simulation, the cause
  is the plant model, never a porting error.

**D5. Base MATLAB only.**
- *Why:* students and other labs should not need toolboxes. The LQR is solved by the
  project's own Riccati iteration (`odyssix.ctrl.lqr`), the fits use `fminsearch`.

**D6. Safety in layers.**
- **Firmware:** limits on arm travel (±240°), pendulum angle, speed, actuator
  saturation; a fault state that only a human can clear.
- **Host:** a 1 s watchdog, so a crashed PC stops the rig. The app feeds it during
  long simulations too (found when a simulation tripped it).
- **Configuration:** echoed and compared before every run, so a corrupted byte cannot
  change a gain.
- **Flashing:** refuses an image without the pendulum banner, with the wrong hash, or
  for the wrong chip. This followed an incident on 2026-08-20, in which the vehicle
  firmware (a different project on the same board type) drove the motor driver's reset
  line as a UART.

**D7. Reproducible, hash-pinned releases.**
- *Why:* a result must name the exact code that produced it.
- *How:* the committed image rebuilds byte for byte from the tagged source, the
  readiness check proves it, and every run records the firmware version and the
  repository revision.

### Data and analysis

**D8. Every rig run recorded automatically; raw data read-only.**
- *Why:* hand-saved data is selectively saved data.
- *How:* the app writes each run, aborted ones included, with its configuration,
  firmware line, live actions and metrics. Raw files are made read-only, and analysis
  results go to `results/`, never back into `data/`.
- *Corrections:* when an analysis method improves, the stored metadata keeps the old
  numbers and the reports give the new ones, with the reason.

**D9. One metric function for simulation and rig.**
- *Why:* a comparison is only fair if both sides are scored identically.
- *How:* simulations are scored on every 10th sample, like the 50 Hz stream, by the
  same `odyssix.sim.metrics`.

**D10. A crash recorder (2.3.3).**
- *Why:* the 50 Hz stream is too coarse to see how a push or a fall develops.
- *How:* the interrupt keeps the last 2 s of every tick, and an abort or PUSH MARK
  sends it, saved next to the run.

### Control

**D11. Linear control for balancing, energy control for swinging up.**
- *Why:* near upright, every nonlinear term is below 0.1 % (|α| < 2°), so the linear
  design of the Tutorials is exact enough and the LQR is optimal for it. Far from
  upright, the arm's effect on the pendulum's energy is proportional to ψ̇ cos ψ, and
  cos ψ changes sign at the horizontal. A fixed linear law pushes the wrong way for
  half of every swing.
- *How:* the swing-up pumps the normalised energy E = ψ̇²/(2ωg²) + 1 − cos ψ towards 2
  (upright, at rest), then hands over to the LQR.

**D12. The catch rule, built from rig evidence.** Each version answered one
measurement (`experiments/EXP024`):

| Version | Catch rule | Why it changed |
|---|---|---|
| 2.2.0 | at ≤ 100 deg/s | one catch at 75 deg/s fell (moving away from upright) |
| 2.3.0 | at ≤ 60 deg/s | the rig hardly ever passed that slowly (1 of 3 caught) |
| 2.3.1 | also when approaching upright at ≤ 100 deg/s, if the LQR's first command is feasible | the held catches were all approaching |
| 2.3.2 | the learnt energy correction may go negative | the real cause: the firmware had been told ωg² 57, the pendulum has 48 |

**D13. Upright auto-trim.**
- *Why:* the encoder's "upright" is a fraction of a degree off the true balance point,
  and the LQR pays for it with the arm: 0.63° made the arm sit 23° off home.
- *How:* while holding upright, the firmware learns the mean α (time constant 8 s)
  and controls it away.
- *Evidence:* the arm now stays within a few degrees of home.

**D14. Measure the pendulum; never trust a textbook value.**
- *Why:* the Tutorial pendulum constant was 19 % too high for this rig, and this cost
  more than any controller detail. Every model parameter that can be measured on the
  rig is measured, with its provenance recorded in
  `shared/parameters/edukit01_rig.yaml`.

## 3. Metrics

Defined once in `matlab/+odyssix/+sim/metrics.m` (and, for the swing-up, in the app);
used for simulation and rig alike.

| Metric | Definition | Used for |
|---|---|---|
| overshoot (%) | 100·(peak/step − 1) during the step phase | T2–T4, T6, T8–T10, PEND |
| peak time (s) | time of that peak from the step | same |
| settling time (s) | last time outside a band around the target. The band is 2 % of the step, never tighter than 2 microsteps (0.225°); 5 % upright, where the arm keeps a ±1° balancing wobble | same |
| load offset (deg) | mean arm angle in the last 1–2 s of the load phase; prediction D/Kp (T2) or −D/Kp without integral action (T8) | T2, T8 |
| control effort | ∫|u| dt over the step (deg/s); also the peak |u| and its square | T3, T4 |
| α rms (deg) | √(mean α²) over the balancing phases | T5–T8, PEND, swing-up |
| hunting (deg) | half the arm's range in the last 2 s | T5 |
| impulse response | the **median**, sample by sample, over all impulse windows (a mean would be pulled by one disturbed window) | T7 |
| hold error (deg) | mean arm error in the last 3 s after a live set-point; reached when inside 0.5° (hanging) or 1.5° (upright) | LAB |
| catch time (s) | from the start of the swing-up to the first sample of HOLD | swing-up |
| swing height (deg) | median of the peaks in undisturbed stretches | pendulum target |
| push size (deg/s) | peak pendulum rate within 200 ms of the push's onset. It underestimates the equivalent instantaneous tap, because the controller brakes within about 50 ms | push test |
| ωg² (free swing) | nonlinear fit with dry and viscous friction from the detected release, and, independently, the median full period between interpolated crossings | identification |

## 4. Variables and parameters

| Symbol | Meaning | Unit | Value or range | Source |
|---|---|---|---|---|
| θ | arm angle | deg | ±240 limit | microsteps issued ÷ 8.889 |
| ψ | pendulum angle from hanging | deg | | encoder, 2400 counts/rev (0.15°) |
| α | pendulum from upright, 180° − ψ wrapped | deg | ±15 abort | |
| u | arm acceleration, the plant input | deg/s² | ±1500 (±800 in T9/T10) | controller output |
| v | arm velocity | deg/s | ±360 (±720 swing-up) | runner |
| Ts | control period | s | 0.002 (500 Hz) | TIM4 |
| ωg² | gravity constant | rad²/s² | **48.0 ± 0.5** (Tutorial: 57.01 hanging, 55.85 upright) | six free swings |
| ωr² | arm coupling | – (dimensionless) | **0.685** (Tutorial 0.803) | ωg²·r/g |
| r | arm length | m | 0.14 | STEVAL-EDUKIT01 manual, Table 2 |
| L | rod length | m | 0.26 | measured with a ruler |
| — | tip accessory | | a small paper holder clipped at the rod end | the likely reason ωg² is 48, not 56.6 |
| c | dry pivot friction | rad/s² | 0.35–0.40 small swings | free swings |
| Q | viscous quality factor | | ≈ 60 at 92° swings | energy balance, R05 |
| E | normalised pendulum energy | | 0 hanging, 2 upright | ψ̇²/(2ωg²) + 1 − cos ψ |
| δ | learnt energy correction | | −0.3 … 0.6 | swing-up |
| Kp, Kd, Ki | arm (rotor) loop gains | per tutorial | | `experiments/EXP00n` |
| Kpp, Kdp | pendulum loop gains | per tutorial | | same |
| k1…k4 | state feedback on θ, θ̇, α, α̇ | | LQR (EXP023) | `odyssix.ctrl.lqr` |

Signs: positive θ is the direction the arm turns for a positive step. Positive ψ is
the direction the hanging pendulum first swings when the arm accelerates in +θ. Both
were measured on the rig (EXP001); the encoder needed a polarity of −1.

## 5. Firmware versions

| Version | Date | What changed | Rig result |
|---|---|---|---|
| 2.0.0–2.0.8 | 2026-10-11/12 | Tutorials 2–5 closed loop; fixes found on first contact with the hardware | T1–T5 run; T5 balanced 4 of 4 on 2.0.8 |
| 2.1.0 | 2026-10-21 | general controller core: T6–T10, PEND experiments, live set-point and gains | |
| 2.2.0 | 2026-10-21 | energy swing-up, lab mode | swing-up 3 of 3 |
| 2.3.0 | 2026-10-21 | pendulum target, upright trim, gentler catch | swing-up 1 of 3; all ten tutorials |
| 2.3.1 | 2026-10-21 | catch when approaching | not flashed |
| 2.3.2 | 2026-10-22 | energy correction may go negative | swing-up 1 of 1 (measured ωg²) |
| 2.3.3 | 2026-10-22 | 500 Hz crash recorder | swing-up 3 of 3; push test 15 of 17 |

Details in the [changelog](../CHANGELOG.md).

## 6. Known limits

- **The model's swing-up build-up is faster than the rig's.** The large-swing losses
  are not fully modelled; the firmware's learnt correction absorbs the difference.
- **The split of the pivot loss between dry and viscous friction is uncertain.**
- **Lost steps cannot be detected:** the arm has no sensor.
- **ωr² is computed, not measured directly.** It rests on the documented arm length
  and the rigid-body identity above.
- **Simulation and rig agree within a few percent for the hanging tutorials.** The
  upright ones are dominated by the arm drift that the trim, deliberately, does not
  correct in the Tutorial sequences.

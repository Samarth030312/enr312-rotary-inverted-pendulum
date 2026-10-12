> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP001/`.

# EXP001 — Conclusion

**Date:** 2026-08-19 · **Revision:** 44bda39 + working tree · **Parameter set:** PS-EDUKIT01-v1

---

## Verdict

**EXP001 is complete to the limit this environment permits. It is not complete as an
experiment, and it must not be reported as one.**

The two chains have been derived from first principles, implemented, and proved correct
*as software*. Not one physical quantity has been measured, because no hardware is
attached to this machine. The distinction is the whole point of the experiment.

---

## What is now established

### Established as fact

1. **The rig is identified.** `Edukit_Student_Lab_Handout.pdf` is an ENR312 course
   document and names the per-station equipment: STEVAL-EDUKIT01 (NUCLEO-F401RE +
   X-NUCLEO-IHM01A1 + NEMA17 + encoder). Its Experiment 1 is this experiment.

2. **The firmware in `Core/` is not this system.** It is an autonomous-vehicle
   application — BNO085 IMU, ESC and steering PWM, `bfmc_msgs/ControlCommand`. It has no
   encoder, no stepper, no SPI. Its pin map conflicts with the Edukit rig on PB4, PA5,
   PA9, PA10 and TIM2. This was the single most consequential finding of the
   reconnaissance, and it determined the architecture: EXP001 lives in
   `firmware/enr312/` as a separate application, and `Core/` and the `.ioc` were not
   touched.

3. **The measurement and command arithmetic is correct.** 119 host checks pass, including
   an exhaustive proof of the wrap-safe decoder over all 65 536 signed deltas at seven
   starting points. The core cross-compiles for Cortex-M4F with zero warnings under a
   strict warning set, in 2086 bytes of flash and zero bytes of static RAM.

4. **The derived constants are independently corroborated.** Deriving 2400 counts/rev
   from 600 PPR × X4, and 3200 microsteps/rev from 200 × 16, reproduces the UCLA
   reference project's `6.666667` and `8.888889` constants *exactly*. Two independent
   routes to the same numbers is meaningful evidence that the part assumptions are right
   — though not that those parts are the ones installed.

5. **The velocity-estimation noise floor is quantified and confirmed twice.** Analytic
   σ_ω = 0.534 rad/s (30.6 °/s) at 500 Hz, confirmed to 0.03 % by a 4×10⁶-sample
   Monte-Carlo simulation.

### Established as prediction only

Every rig constant in `PS-EDUKIT01-v1`. The encoder resolution, the microstep divisor,
the pin map, the travel limits and **both sign conventions** are `REFERENCE_UNVERIFIED`
or `DATASHEET_NOMINAL`. They are the best available priors. They are not measurements,
and the parameter set says so on every line.

---

## The most useful thing EXP001 produced

Three results are worth carrying forward because they change later decisions rather than
merely recording facts.

**1. The arm has no sensor, and that is a design commitment, not an omission.**
A stepper's position is commanded and remembered, not measured. This answers the
handout's reflection question — the encoder is on the pendulum because the arm does not
need one *provided no step is ever lost*. There is no error signal behind that proviso:
if the motor slips a pole, the firmware remains perfectly confident and permanently
wrong. Prediction P3 is the only check that exists anywhere in the system, which is why
it is not optional and why it must be repeated at any rate later experiments actually use.

**2. Sampling faster makes velocity estimation worse.**
σ_ω = σ_θ·√2/Ts scales as 1/Ts. Halving the sample period doubles the differentiation
noise. The lever that actually helps is resolution: σ_ω scales linearly with q, so X4
decoding buys a factor of four that no amount of sampling speed can. This is
counter-intuitive and it constrains EXP003 — "faster is better" is simply false here, and
the sample rate must be argued from bandwidth and loop delay instead.

**3. The derivative low-pass filter is forced by the sensor, not by taste.**
At 500 Hz the raw backward difference carries σ = 0.534 rad/s, which is comparable to the
true pendulum velocity near equilibrium — exactly the regime where a balancing controller
does its most delicate work. Unfiltered, a derivative gain Kd injects ~0.53·Kd rad/s of
noise straight into the actuator. The reference project's 10 Hz corner reduces this to
0.136 rad/s, a factor of 3.9. EXP005 will need this, and now it will have a reason rather
than an inherited constant.

---

## What EXP001 has *not* shown

- Nothing about physical motion. No commanded angle has produced a measured angle.
- Nothing about step fidelity. A2 is untested.
- Nothing about either sign convention. Both remain undetermined.
- Nothing about timing. `t_s` in the telemetry is computed as `tick × Ts` by the firmware
  itself, so it is a restatement of an assumption, not a measurement of it. Real timing is
  EXP003.
- Nothing about dynamics — deliberately. No inertia, no friction, no natural frequency, no
  transfer function, no stability claim.

---

## Failures encountered and fixed

Three real defects, all found by tests written before any hardware existed.

| # | Defect | Consequence had it reached hardware | Fix |
|---|---|---|---|
| 1 | P3 phase skipped its closing return-to-zero | The arm would park at −90° and the commanded position would end at −800 microsteps. A "zero-net-motion" test that does not end at zero net motion **silently invalidates P3** — the one test that can detect lost steps. | Issue `goto(0)` before advancing to DONE |
| 2 | Step-tick rate truncated 82031.25 → 82031 Hz | −3 ppm bias on every predicted step rate; firmware quietly disagreeing with the derivation, so P5 could never be evaluated cleanly | Keep the tick rate as an exact double; compute ARR in floating point |
| 3 | Analysis probed the last `RETURN_P3` sample for closure | Would report P3 closure failure on a perfectly closed run, i.e. a false negative on the most important test | Probe the run's final sample |

Defect 1 is the one worth noting: it is not a crash, it produces plausible telemetry, and
it would have made the experiment's central test quietly meaningless.

One documentation error was also corrected: the derivative-filter noise reduction was
stated as "~0.11 rad/s" by a rough estimate; the exact first-order noise gain gives
0.136 rad/s.

---

## Open items carried forward

| ID | Item | Blocks | Resolution |
|---|---|---|---|
| OI-1 | Course outline says DC servo; lab handout says NEMA17 stepper | Rig identity | Physical inspection (procedure 0.1) |
| OI-2 | Both sign conventions undetermined | **EXP002** | P1, P2b |
| OI-3 | No board-support layer exists | Hardware execution | See below |
| OI-4 | Pin map `REFERENCE_UNVERIFIED` | Hardware execution | Procedure 0.2 |
| OI-5 | Travel limits inherited | Hardware execution | Procedure 0.3 |
| OI-6 | Mechanical parameters unknown | **EXP004** | Direct measurement |

### On OI-3 — why the board layer was deliberately not written

The EXP001 core is complete and tested, but it is not yet a flashable application. Still
missing: TIM3 quadrature initialisation, the L6474 SPI driver, the step-clock ISR, and a
telemetry UART.

That was a deliberate stopping point, not an oversight. Writing it now would mean
committing several hundred lines to a pin map tagged `REFERENCE_UNVERIFIED`, against a
rig nobody has inspected, with an open question (OI-1) about whether the actuator is even
a stepper. If OI-1 resolves the other way, that code is not wrong in detail — it is the
wrong architecture entirely, because a DC servo is torque-commanded and would need its
own arm encoder.

docs/ENGINEERING_STANDARDS.md §15 is explicit: never copy MCU-specific configuration merely because it exists
in the reference project. The boundary chosen here puts everything that is
hardware-independent — and therefore provable now — on one side, and everything that
depends on unverified hardware facts on the other. The core is written and proved; the
shim waits for the rig.

---

## Gate decision

**EXP002 must not begin.**

EXP002 is *Sensor Calibration and Sign Conventions*. Its inputs are precisely the
measurements EXP001 could not make: encoder resolution (P2), sign convention (P2b), and
count integrity (P4). Beginning it now would mean calibrating against assumed constants
and inherited signs — the exact failure mode EXP001 exists to prevent, and the one that
would present later as a physics problem rather than a plumbing problem.

The dependency is real, not procedural.

---

## Reproducibility

Everything claimed here is reproducible from a clean checkout:

```bash
# Baseline vehicle-firmware build (unmodified)
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"
make clean && make -j"$(nproc)"

# EXP001 core: 119 host checks, then target cross-compile
cd firmware/enr312 && make test && make arm && cd ../..

# Numerical analysis, figures, and tables
python3 scripts/exp001_sensing_analysis.py

# Measured-data pipeline, exercised on synthetic input
python3 scripts/exp001_process_measurements.py --selftest
```

| Environment | Version |
|---|---|
| Cross compiler | arm-none-eabi-gcc 13.2.1 (Arm GNU Toolchain 13.2.rel1) |
| Host compiler | gcc (system) |
| Python | 3.10 with numpy 1.26.4, scipy 1.15.3, matplotlib 3.10.8 |
| MATLAB | **absent** |
| Target hardware | **absent** |

---

## Next step

The smallest justified next action is **procedure step 0.1**: physically inspect the rig
and record the part numbers in `MEASUREMENTS.md`.

It is small, it needs no code, and it resolves OI-1 — which gates OI-3, OI-4, the entire
parameter set, and therefore every subsequent experiment. Until a human confirms that the
actuator is a stepper and the encoder is 600 PPR, further firmware would be built on an
unverified premise.

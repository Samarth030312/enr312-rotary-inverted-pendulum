> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP007/`.

# EXP007: Pendulum-loop design, impulse response (inverted)

| | |
|---|---|
| **Source** | Tutorial 7. Safety class **HIGH** (upright). |
| **Status** | Firmware 2.1.0 implemented and host-tested; simulation EXECUTED; **hardware NOT_EXECUTED** |
| **Depends on** | EXP005, EXP006 |
| **Run it** | `enr312_lab` → **T7**; `$exp=7` |

## 1. Objective and physical question
With the rotor PID fixed, design the **pendulum** (inner) PD and measure its effect
directly, by kicking the pendulum's reference instead of the rotor's. **Physical
question:** how stiff and how damped must the balancing loop be, and how does that
show up in the pendulum's own response?

## 2. Signs, units, law
As EXP006. Rotor PID fixed at Kp 15, Ki 0, Kd 7.5, rotor D filter 50 Hz (Tutorial 7).
Impulse: the pendulum reference α_ref becomes +10° for **2 ticks (4 ms)**, every 5 s,
8 times (Tutorial 7 §15 signal averaging); the responses are aligned on the known
timing and averaged (`odyssix.sim.impulseAverage`, works on 50 Hz rig logs).

## 3. Model
Inner loop: s² + (γ + ωr²Kdp)s + (ωr²Kpp − ωg²). It needs **Kpp > ωg²/ωr² = 69.6** just
to hold the pendulum up against gravity. Damping ζ = (γ + ωr²Kdp)/(2√(ωr²Kpp − ωg²)).
The full closed loop also contains the sign-inverted rotor loop, and an inner loop
that is stable on its own is **not sufficient**:

| Kpp / Kdp | inner poles | full closed loop |
|---|---|---|
| 150 / 15 | −6.21 ± 5.10j (stable) | **unstable** |
| 200 / 20 | −8.22 ± 6.10j | stable |
| 300 / 30 (default) | −12.23 ± 5.95j | stable (−7.21 ± 8.47j, −1.28 ± 2.27j) |
| 600 / 60 | −37.1, −11.5 | stable |

The pendulum loop seen from the pendulum reference has 2 open-loop RHP poles, so a
crossover "phase margin" is meaningless there. The closed-loop poles are the verdict.

## 4. Predictions (firmware simulation, Tutorial 5 plant)
Averaged response to a 10° × 4 ms reference impulse: pendulum peak −1.39°, settles in
1.86 s; arm peak 4.75°, settles in 2.36 s; pendulum rms 0.29° while balancing.
Gain sweep (Kdp 30 fixed): Kpp ≤ 150 falls, 160 marginal, ≥ 170 balances; pendulum rms
falls from 2.2° (160) to 0.34° (1000). Kdp sweep (Kpp 300): Kdp ≤ 10 falls, 15–100
balances, **≥ 150 hits the arm-velocity limit**: the derivative amplifies encoder
quantisation (C11). Tables: `results/tables/PEND_sim_kpp.csv`, `PEND_sim_kdp.csv`.

## 5. Hypotheses
* **H7-1** The default design balances and the 8 impulse responses average to a clean
  transient (peak −1.4 ± 0.5°).
* **H7-2** Kpp/Kdp = 150/15 loses balance though its inner loop alone is stable.
* **H7-3** Higher Kpp/Kdp → smaller pendulum peak, faster pendulum settling.

## 6. Acceptance
AC7-1 8 impulses applied, no abort; AC7-2 averaged rig response overlaid on the
simulation (app analysis panel); AC7-3 H7-2 tested last, with a hand ready.

## 7. Procedure, artifacts, results
Procedure: `../PROCEDURE_UPRIGHT.md`. Artifacts: `enr312_ctrl.c` (exp 7),
`impulseAverage.m`, app T7. **Measured data: none yet.**

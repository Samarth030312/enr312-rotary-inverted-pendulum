> **Pre-registration, not yet run on the rig.** Every number below is a simulation
> prediction ([`results/tables/`](../../results/tables/)), written before any hardware run.

# EXP006: Integral action, dual PID (inverted)

| | |
|---|---|
| **Source** | Tutorial 6 (`course material `). Safety class **HIGH** (upright). |
| **Status** | Firmware 2.1.0 implemented and host-tested; simulation EXECUTED; **hardware NOT_EXECUTED** (no working board available) |
| **Depends on** | EXP005 (balancing, capture/release, the inverted sign) |
| **Unlocked** | by the human, recorded 2026-10-21 (experiments 6–10) |
| **Run it** | `enr312_lab` → **T6**; firmware `$exp=6`; Python `run_experiment.py --exp 6` |

## 1. Objective and physical question

Add integral action to the rotor (outer) controller of the balancing pendulum and
measure what it buys and what it costs. **Physical question:** the rotor plant
already contains two integrators, so why add a third, and what does it do to the
stability of an already conditionally stable loop?

## 2. Coordinates, signs and units

As EXP005 (`docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md`): θ is the rotor angle
[deg] from the issued microsteps (+ = measured direction, EXP001 P1); ψ is the encoder
angle [deg], 0 when hanging; α = wrap180(180 − ψ) is the angle from upright [deg]; u is
the rotor angular acceleration [deg/s²] (the plant input). Inverted dual-PID law
(`firmware/enr312/inc/enr312_ctrl.h`):

    u = −u_rotor + u_pend
    u_rotor = Kp e + Ki ∫e dt + Kd ė_f      e = r − θ,  ė_f: D low-pass at fdr = 50 Hz
    u_pend  = Kpp ε + Kdp ε̇_f               ε = α_ref − α,  low-pass at fdp = 10 Hz

## 3. Parameters

| | Value | Provenance |
|---|---|---|
| Kp, Ti, Td (rotor) | 15, 5 s, 0.5 s → **Ki = Kp/Ti = 3**, Kd = Kp·Td = 7.5 | Tutorial 6 (its text says "Ki = 5": that is Ti, an arithmetic slip) |
| Kpp, Kdp (pendulum) | 300, 30 | Tutorial 5 (EXP005 source conflict resolved to Kdp 30) |
| step | 40° and back | Tutorial 6 |
| plant | ωg² 55.85 s⁻², Q 20, ωr² 0.803 | Tutorial 5, **not measured on this rig** (OI-9) |
| limits | u ≤ 1500 deg/s², arm speed ≤ 360 deg/s, |α| ≤ 15° | firmware |

## 4. Model (first principles → loop)

Linearised upright pendulum with the arm acceleration as input:
α̈ = ωg² α − γ α̇ + ωr² θ̈ (γ = ωg/Q). The inner loop closes to
s² + (γ + ωr²Kdp)s + (ωr²Kpp − ωg²) = s² + 24.46 s + 185.05 (needs Kpp > ωg²/ωr² = 69.6).
With the sign-inverted outer PID the rotor loop is

    L(s) = −(Kd s² + Kp s + Ki)(s² + γ s − ωg²) / (s³ (s² + 24.46 s + 185.05))

The pendulum's unstable pole +7.29 rad/s becomes a **right-half-plane zero** of L: the arm
must first move the wrong way. Ki adds a pole at the origin (type 3) and a third
closed-loop pole near the origin. That pole is slow: 0.22 s⁻¹ at Ki = 3.

## 5. Predictions (simulation, `results/tables/EXP006-023_sim_metrics.csv`)

| | Linear, continuous | Firmware simulation (500 Hz, filters, limits, quantisation) | Tutorial 6 |
|---|---|---|---|
| overshoot | 52.0 % | **33.8 %** | 52.6 % |
| settling | 3.18 s (2 %) | **6.3 s** (5 % band) | 3.1 s |
| wrong-way undershoot | −28 % | **−6.5 %** | – |
| phase margin | 31.42° | – | 31.45° |
| gain margins | −18.4 dB (lower) / +7.2 dB (upper) | – | 7.59 dB |
| steady-state error | 0 | −0.34° (inside the ±1° wobble) | 0 |

**Why the firmware differs from the textbook. This is the main finding to test.** The 40° step makes a
derivative kick (Kd acts on the error) that saturates the plant input at 1500 deg/s². With
the input unclamped (simulation only) the same firmware loop gives 57 % / 2.9 s / −30 %,
i.e. the linear answer. On the rig the overshoot should therefore be near 34 %, not 52 %.

Ki trade-off (linear): PM 32.75° (Ki 0) → 31.42° (3) → 28.79° (7.5) → 21.77° (15) →
**unstable at Ki = 30** (PM −5.5°).

## 6. Hypotheses (falsifiable)

* **H6-1** The rig balances through the sequence with the Tutorial 6 gains. Falsified by an abort.
* **H6-2** Overshoot 34 ± 10 % (saturation-limited), *not* 52 %. A rig value near 52 % would mean
  the actuator limit is not active as modelled.
* **H6-3** First motion of the arm is the wrong way (undershoot < 0).
* **H6-4** Raising Ki towards 15 visibly lengthens the slow drift and enlarges the arm excursion
  (simulated arm peak 53° → 69°); Ki = 30 is predicted to lose balance or wander > 100°.

## 7. Acceptance criteria

AC6-1 run reaches HOLD with no abort; AC6-2 H6-2 and H6-3 checked with
`odyssix.sim.metrics` on the saved CSV; AC6-3 rig vs simulation overlay saved with
the free-swing-identified plant (EXP001/PEND A4) if available; AC6-4 discrepancies
written down, none hidden.

## 8. Procedure

See `../PROCEDURE_UPRIGHT.md`. Data: `data/raw/EXP006/` + `data/metadata/EXP006/` (the app's
**Save rig run**).

## 9. Artifacts

`firmware/enr312/src/enr312_ctrl.c` (exp 6), `matlab/+odyssix/+sim/runCtrl.m`
(identical port, parity test), `odyssix.sim.loop` (L, margins), app **T6** (root locus,
metrics), `matlab/experiments/PEND/pend_predictions.m` (numbers above).

## 10. Measured data, comparison, conclusion

**None yet.** Hardware NOT_EXECUTED.

> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP008/`.

# EXP008: Root locus and load-disturbance rejection (inverted)

| | |
|---|---|
| **Source** | Tutorial 8. Safety class **HIGH** (upright). |
| **Status** | Firmware 2.1.0 implemented and host-tested; simulation EXECUTED; **hardware NOT_EXECUTED** |
| **Depends on** | EXP006 (integral action), EXP002 (S_D on the rotor alone) |
| **Run it** | `enr312_lab` → **T8**; `$exp=8` |

## 1. Objective and physical question
Design the rotor PID with the root locus, then test it against a **constant load
disturbance** D added at the plant input (as EXP002 did for the rotor alone).
**Physical question:** why does a PD-controlled balancing arm settle off target under a
constant load, and why does integral action remove it?

## 2. Law, sequence, units
As EXP006 with u = −u_rotor + u_pend + D. Sequence after capture, release and 5 s
of balance: step 40° (10 s), back (10 s), D on (10 s), D off (10 s), then HOLD.
D [deg/s²].

## 3. Model
S_D(s) = Y/D = T_rotor/(1 + T_rotor K_rotor). As s → 0, S_D(0) = 1/Kp without integral
action (Tutorial 8: −23.5 dB at Kp 15), and 0 with it. So the steady offset is
**−D/Kp** without Ki (negative in the inverted sign convention) and 0 with Ki.
Root locus: the closed-loop poles of den + k·num as the PID gains scale by k (app
analysis panel, T6/T8).

**Amplitude choice (ours, not the tutorial's).** Tutorial 8 gives no value for D. With 20
deg/s² the offset D/Kp = 1.3° hides in the ±1° balancing wobble; **D = 60** makes it 4°.

## 4. Predictions (firmware simulation)
| | Ki 7.5 (Tutorial 8) | Ki 0 |
|---|---|---|
| step overshoot / settling | 50.8 % / 4.7 s | – |
| disturbance peak | 5.2° | 5.3° |
| arm offset, last 3 s of D | **−0.66°** | **−4.11°** (theory −4.00) |
| pendulum peak during D | 0.3° | 0.3° |
| phase margin (linear) | 28.8° | 32.8° |

## 5. Hypotheses
* **H8-1** With Ki the arm returns to within ±1° of its reference while D is on.
* **H8-2** With Ki = 0 it sits at −D/Kp ± 1° (−4°).
* **H8-3** The root-locus gain range that keeps all poles in the LHP matches the gain
  range that balances on the rig (simulated sweep of Kp with the EXP006 gains,
  `PEND_sim_kp.csv`: balances for 2 ≤ Kp ≤ 40, loses it at 60).

## 6. Acceptance, procedure, results
AC8-1 runs with Ki = 7.5 and Ki = 0, both saved; AC8-2 offsets compared with ±D/Kp.
Procedure `../PROCEDURE_UPRIGHT.md`. **Measured data: none yet.**

# EXP023 (PEND): LQR balancing, 4 states (inverted)

| | |
|---|---|
| **Source** | PEND handout §3 C10 (LQR, Q/R trade-off, compare with PID tuning) |
| **Status** | Firmware 2.1.0; simulation EXECUTED; **hardware NOT_EXECUTED**. Safety class **HIGH** |
| **Depends on** | EXP005, EXP006, EXP010 |
| **Run it** | `enr312_lab` → **P23** (LQR designer, 4 weights); `$exp=23` |

## 1. Objective and physical question
Balance with **one** state-feedback law on x = [θ − r, θ̇, α, α̇] designed by LQR,
instead of two hand-tuned PID loops. **Physical question:** what do the weights Q and
R mean physically, and is LQR easier to tune than the dual PID?

## 2. Model
Linearised upright pendulum (degrees, u = arm acceleration):

    A = [0 1 0 0; 0 0 0 0; 0 0 0 1; 0 0 ωg² −γ],  B = [0; 1; 0; ωr²],  ẋ = Ax + Bu

(`odyssix.ctrl.pendulumModel('inverted')`: open-loop poles 0, 0, +7.29, −7.66).
u = −(k1(θ − r) + k2θ̇ + k3α + k4α̇); α̇ is a filtered difference of the encoder (fdp).
Default Q = diag(1, 1, 10, 1), R = 0.01 → K = [−10, −13.79, 382.8, 50.79], closed-loop
poles −14.6, −5.89 ± 1.84j, −1.01. The negative k1, k2 carry the same sign inversion
as the Tutorial 5 outer loop: to move the arm one way the pendulum must first be tipped
that way.

## 3. Q/R trade-off (firmware simulation, step 20°, `PEND_sim_lqr.csv`)
| Q diag | R | K | settling | α rms | peak u |
|---|---|---|---|---|---|
| 1 1 10 1 | 0.01 | [−10 −13.8 383 50.8] | 4.07 s | 0.170° | 1500 (limit) |
| 1 1 10 1 | 0.1 | [−3.16 −4.92 226 29.6] | 6.23 s | 0.195° | 803 |
| 1 1 10 1 | 0.001 | [−31.6 −41.8 888 119] | 3.05 s | 0.157° | 1500 |
| 1 1 100 1 | 0.01 | [−10 −14.0 401 51.7] | 3.91 s | 0.165° | 1431 |
| 10 1 10 1 | 0.01 | [−31.6 −21.7 476 62.8] | **1.28 s** | 0.227° | 1500 |

Raising R makes effort expensive: lower gains, slower arm, less u. Raising the θ weight
moves the arm fast at the cost of more pendulum error. Raising the α weight holds the
pendulum tighter. Compared with Tutorial 6's PID (33.8 % overshoot, α rms 0.42°), the
default LQR gives 2.3 % overshoot and α rms 0.17°: one design step, four gains, no sign
puzzles.

## 4. Hypotheses and acceptance
* **H23-1** The default LQR balances and steps with < 10 % overshoot.
* **H23-2** The ordering of settling times in the table holds on the rig.
* **H23-3** R = 0.001 runs at the input limit and may abort on SATURATION (200 ms): run it last.
Procedure `../PROCEDURE_UPRIGHT.md`. **Measured data: none yet.**

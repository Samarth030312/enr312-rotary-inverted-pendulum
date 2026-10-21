# EXP010: LQR (rotor, hanging)

| | |
|---|---|
| **Source** | Tutorial 10. Safety class LOW. |
| **Status** | Firmware 2.1.0; simulation EXECUTED; **hardware NOT_EXECUTED** |
| **Depends on** | EXP009 |
| **Run it** | `enr312_lab` → **T10** (LQR designer: diag(Q), R → k1, k2); `$exp=10` |

## 1. Objective and physical question
Choose the state-feedback gains by **minimising a cost** J = ∫(xᵀQx + uᵀRu)dt instead of
placing poles by hand. **Physical question:** what does "cheap" versus "expensive"
control (R) mean on the arm you can watch?

## 2. Model and computation
Plant ẋ = Ax + Bu, A = [0 1; 0 −b], B = [0; 1] (degrees). K = R⁻¹BᵀP, P from the
algebraic Riccati equation AᵀP + PA − PBR⁻¹BᵀP + Q = 0, solved without any toolbox by the
stable invariant subspace of the Hamiltonian (`odyssix.ctrl.lqr`). Reproduces Tutorial
10: Q = I, R = 1 → K = [1 1.7321] (b = 0) and [1 0.6458] (b = 2). For the double
integrator with Q = I: k1 = 1/√R, k2 = √(2k1 + 1/R).

## 3. Predictions (firmware simulation, step 20°)
| Q, R, b | K | poles | overshoot | settling | final |
|---|---|---|---|---|---|
| I, 1, 0 | [1 1.7321] | −0.87 ± 0.5j | 0.1 % | 4.39 s | 20.02° |
| I, 1, 2 | [1 0.6458] | −2.19, −0.46 | – | does not reach the 2 % band | **19.46°** |
| I, 0.1, 0 | [3.162 4.040] | −2.98, −1.06 | 0 % | 4.18 s | 19.80° |

b = 2 parks 0.54° short: the stepper's minimum step rate (EXP009 §3) with
(k2 + b)/k1 = 2.65 gives a bound of 0.60°. **A prediction to check, not a bug.**

## 4. Hypotheses
* **H10-1** Smaller R gives faster settling and a larger peak u (visible in the app's u plot).
* **H10-2** The b = 2 design stops 0.4–0.6° short of the target.

## 5. Acceptance, procedure, results
AC10-1 LQR gains computed in the app equal Tutorial 10's to 4 digits (verified in
software); AC10-2 three designs run on the rig and compared. Procedure
`../PROCEDURE_SUSPENDED.md`. **Measured data: none yet.**

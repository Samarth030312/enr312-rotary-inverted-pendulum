# PEND lab: how to answer every question with this rig

The ENR312 PEND handout (*Pendulum Control Experiment, Experiment Guidelines and Lab
Report Questions*) assumes the UCLA demo firmware and the `pendulum-pid` Python library.
This repository replaces both with its own firmware (C, bare metal, 500 Hz) and the
MATLAB lab app `enr312_lab`. An optional Python client (`python/`) speaks the same
protocol. This guide maps **every task and question** in the handout to the experiment,
tool, data file or derivation in this repository that answers it.

**Read the status first.** Every simulated number below comes from
`matlab/experiments/PEND/pend_predictions.m` (tables in `results/tables/PEND_sim_*.csv`)
with the **Tutorial plant values**, not this rig's measured ones. These numbers are
predictions to test, not answers to copy. The handout asks for *your measured data*.
Hardware runs of the new experiments have **not** been made yet (status:
NOT_EXECUTED); Tutorials 1–5 ran on the rig on 2026-10-12
(`results/reports/2026-10-12_rig_tutorials_1-5.md`).

| Tool | What it is |
|---|---|
| `enr312_lab` (MATLAB) | missions T1–T10 and LAB (hanging or upright; PID, LQR, state feedback, on-off; ARM go-to/step; PENDULUM target and swing-up); simulate, run on the rig, every run recorded and replayable |
| `python/run_experiment.py` | the same runs from Python (optional) |
| `odyssix.pend.*` (MATLAB) | `freeSwing`, `recovery`, `gainSweep`, `derivativeNoise`, `unstablePole` |
| `pend_swingup_study.m`, LAB → PENDULUM | energy swing-up: simulation study, and on the rig since 2026-10-21 |

---

## Section 1: tasks

| # | Task | With this rig |
|---|---|---|
| 1 | Identify components | Tower, pendulum, NEMA-17 stepper, LPD3806-600BM-G5-24C encoder, NUCLEO-F401RE, X-NUCLEO-IHM01A1 (L6474), 12 V supply, USB cable. Photograph them for the report. |
| 2 | UCLA site | Background only. The UCLA firmware is reference material (`docs/references/`), **not** what runs here. |
| 3 | STM32CubeProgrammer | Flashing here is `odyssix.stm32.flash()` in MATLAB (STM32_Programmer_CLI, the command-line CubeProgrammer, after three checks: banner, hash, chip). CubeProgrammer works as well: write `firmware/enr312/target/build/enr312_pendulum.bin` at 0x08000000. See `docs/GETTING_STARTED.md`. |
| 4 | Arduino STM32 boards | Not used: the firmware is built with arm-none-eabi-gcc + make (`make -C firmware/enr312/target`). Explain why in A3. |
| 5 | Python + pendulum-pid | Use `python/enr312_rig.py` (our protocol, same idea: send commands and gains, receive angles). |
| 6 | Run a demo | Run **T1** (open-loop moves) then **T3** (suspended PID) in the app. |
| 7.1 | PID, suspended | **T3/T4** (dual PD), **LAB · hanging · PID** (pluck, RUN: the swing is stopped; ARM GO TO holds any angle). |
| 7.2 | PID, inverted | **T5** (dual PD), **T6** (PID), **T7**, **T8**, **LAB · upright · LQR**. Two people; `experiments/PROCEDURE_UPRIGHT.md`. |

---

## Section 2: questions

Q1, Q2, Q3, Q5, Q6, Q11, Q12, Q15 are general knowledge. Answer them in your own words;
the rows below say what on this rig to point at.

| Q | Answer with this rig |
|---|---|
| 1 Microcontroller | The F401's loop: TIM4 interrupt every 2 ms → read TIM3 encoder count → control law → step rate to TIM2 → STEP pulses. `firmware/enr312/target/src/enr312_main.c`. |
| 2 Power | Nucleo: USB through the ST-LINK (5 V), or E5V / VIN / 3V3 pins (NUCLEO-64 user manual UM1724). The motor runs from the separate **12 V** supply through the IHM01A1; USB alone cannot move it. |
| 3 MCU vs MPU | The F401 has flash, RAM, timers, ADC and UART on one chip and runs bare metal; an MPU needs external memory and an OS. |
| 4 Encoder / potentiometer | Here: an **incremental quadrature encoder**, 600 lines → **2400 counts/rev** in x4 decoding (0.15° per count), A/B on PB4/PB5 into TIM3 encoder mode. Quadrature gives direction; zero is set by **Zero datums** (incremental, no absolute position). A potentiometer is absolute but analogue (ADC noise, wiper wear, < 360°). Draw: encoder supply and GND (per your kit's wiring), A→PB4, B→PB5. |
| 5 Servo vs DC motor | The rig uses neither: a **stepper** moves exact 1/16 microsteps (open loop, no position sensor needed unless steps are missed). Compare: DC motor = torque/speed from voltage, needs feedback; servo = DC motor + internal position loop. |
| 6 Motor driver | The L6474 (IHM01A1) switches 12 V and the coil currents (with current limiting) from STEP/DIR logic signals. An MCU pin gives ~20 mA at 3.3 V; a coil needs amps at 12 V and produces back-EMF. |
| 7 On-Off control | **LAB · hanging · On-off** (`experiments/EXP022`). Prediction: the arm never settles; it oscillates ±r forever (100 % overshoot), and the pendulum is shaken to 36°. Drawbacks: no settling on an acceleration-driven plant, chatter, violent actuation. |
| 8 Moving-average filter | The firmware has one on the pendulum angle (`ma` = 1–32 samples, app field on T6–T10 and LAB). `odyssix.pend.derivativeNoise`: an 8-point MA on the 500 Hz derivative cuts rms noise from 31.8 to 5.8 deg/s at the cost of 7 ms delay. A first-order filter at 10 Hz gives 4.3 deg/s with 16 ms delay. Delay costs phase margin: sweep `ma` with `gainSweep`. |
| 9 P controller | On this rig P alone on the rotor is **T9 with k2 = 0**: an undamped oscillation (±19.7°, period 3.1 s at k1 = 4). On the pendulum, Kdp = 0 falls (`PEND_sim_kdp.csv`). In Arduino-style code: `u = Kp*(ref - angle)` every fixed period, then write it to the actuator; our C equivalent is `enr312_ctrl.c`. |
| 10 High Kp oscillates | Inner loop: s² + (γ + ωr²Kdp)s + (ωr²Kpp − ωg²), ζ = (γ + ωr²Kdp)/(2√(ωr²Kpp − ωg²)). Raising Kpp raises the natural frequency and **lowers the damping**. Plus the loop delay (filters, sampling) costs more phase at higher crossover. Show it with the Kpp slider on T7 (inner poles in the analysis panel) or `gainSweep(6,'kpp',…)`. |
| 11 PID roles | P: stiffness; I: removes the offset from a constant load (T8: −4.1° → −0.7°); D: damping (Kdp = 0 falls; too much amplifies encoder noise, Kdp ≥ 150 hits the velocity limit). |
| 12 PWM | The rig does not use PWM for the motor. Torque comes from the L6474's chopper current regulation, and position from the STEP pulse count; our command is a **step rate**. Arduino Uno PWM: 8-bit `analogWrite`, ~490/980 Hz on 6 pins. |
| 13 Uno limits | 16 MHz 8-bit AVR, no FPU (software float ~tens of µs per operation), 2 KB RAM. A 500 Hz loop with filtered PID in float, step generation and a 115200-baud stream is tight. See A3. |
| 14 On-Off vs P | LAB on-off vs T9 at K = [4 0]: both oscillate ±20° (neither has damping on θ̈ = u). P is smooth (pendulum 3.1°); on-off is a parabola train (pendulum 35.9°). Add the D term (T9 reference) and it settles in 5.9 s. |
| 15 Applications | Segway / self-balancing robots, rocket thrust-vector attitude control, humanoid balance, cranes (anti-sway: the suspended case, LAB hanging), ship stabilisers. |

---

## Section 3: additional questions (S3-n)

### A. Apparatus and measurements

**S3-1 (A1) Boards and signal chain.** NUCLEO-F401RE (STM32F401RET6), X-NUCLEO-IHM01A1
(L6474PD), encoder LPD3806-600BM-G5-24C; read the part numbers off your own kit.
Chain: pendulum angle → encoder A/B → PB4/PB5 → TIM3 (x4 count) → 500 Hz control
interrupt (TIM4) → law (`enr312_ctrl.c`) → acceleration u → velocity → step rate →
TIM2 period → STEP pulses on PC7 + DIR on PA8 → L6474 → stepper → arm.
PC ↔ board: USART2 (PA2/PA3) via the ST-LINK virtual COM port, 115200 baud.
**Sent:** single-byte commands (ARM `a`, START `s`, ABORT `x`, zero `z`, keep-alive `.`)
and `$` lines (`$exp=6`, `$kp=15`, …, `$go`, `$ref=30`). **Received:** a 50 Hz stream
`D,ticks,rotor_mdeg,pend_mdeg,raw,faults,state,exp,phase,u,ref_mdeg,isr_us` and the
configuration echo `C,…`. The PC never closes the loop; it only configures and logs.

**S3-2 (A2) Resolution.** 600 PPR × 4 = 2400 counts/rev → **0.15°** per count. Stepper 200
steps/rev × 16 microsteps = 3200/rev → **0.1125°** per microstep. The minimum step rate is
2 microsteps/s (0.225 deg/s), which matters in EXP009/010.

**S3-3 (A3) Uno vs STM32.** ATmega328P: 16 MHz, 8-bit, no FPU. STM32F401: 84 MHz,
32-bit Cortex-M4F with a single-precision FPU (the firmware computes in double; that is
software emulated, yet the control interrupt measured at most **129 µs of the 2000 µs**
period on the rig on 2026-10-12 with firmware 2.0.x, and at most 216 µs with the
general controller core of 2.3.x on 2026-10-21 (`isr_max_us`, rig session logs). The stepper is **acceleration-commanded** here: the controller output u
[deg/s²] is integrated to a velocity and sent as a step rate. Torque is not commanded,
and that is why the model input is θ̈ (rotor plant 1/s²) rather than a voltage. A
stepper that misses steps loses its position silently. Watch for it in A7.

**S3-4 (A4) Free swing.** App: motor SAFE, **Free swing: record 15 s**, release from
10–20°. It reports T over 10 swings, L = g(T/2π)², the ruler length to expect, ζ by log
decrement, and the nonlinear fit (ωg², Q). Python: `run_experiment.py --free-swing 15`.
The ruler will **not** match L. The pendulum is a compound pendulum, and L is the length
of the equivalent simple pendulum, J/(m·lc) (2/3 of a uniform rod; Tutorial 5 uses
0.6805·L_rod). The tool prints the predicted ruler length L/0.6805. Prediction with the
Tutorial values: T ≈ 0.83 s, L ≈ 0.17 m, ζ ≈ 0.018. Emulator check: ωg² 56.20 vs truth
56.4, ζ 0.0206 vs 0.0208.

**S3-5 (A5) Suspended PID, time to stop a swing.** **LAB · hanging · PID**: pluck, then
RUN, for three gain sets (change Kd pendulum between runs); the app's table gives *Time to stop, inside 1 deg*
(`experiments/EXP021`). Prediction: 1.6 s / 2.7 s / 21.3 s. The pendulum Kd has the
largest effect; without it the decay is the free decay (2 ln 20/γ = 21.4 s).

**S3-6 (A6) Inverted: gains, one at a time, Kp range.** **T6** (or T5), then change one
gain at a time in the app (simulate first). On the rig, type the new gain while it
balances in HOLD: it is applied at once and logged with its time. Predictions (`PEND_sim_kpp/kdp/kp/kd/ki.csv`):

| Gain | Balances for | Outside the range |
|---|---|---|
| pendulum Kp (Kpp) | ≥ 160–170 (theory: must exceed ωg²/ωr² = 69.6 even to hold it; the full loop needs more) | ≤ 150 falls |
| pendulum Kd (Kdp) | 15–100 | ≤ 10 falls; ≥ 150 velocity limit (noise) |
| rotor Kp | 0–40 | Kp 0: balances but the **arm drifts** (77° in 20 s); 60 falls |
| rotor Kd | 2–15 | 0: violent, velocity limit; 30 falls |
| rotor Ki | 0–15 | 30: linearly unstable, the arm wanders 123° |

**S3-7 (A7) Tap.** While balancing in HOLD, tap the pendulum and save the run;
`odyssix.pend.recovery(t, alpha, t_tap, 1)` gives the recovery time. In the emulator,
taps are injected exactly (`taps` option of `runCtrl`). Prediction
(`PEND_sim_taps.csv`): a tap worth 20–100 deg/s of pendulum rate is recovered in
0.5–2.0 s, with the arm swinging out 10–75°; **120 deg/s is lost**. Missed steps: the
model has none. On the rig, compare the arm angle after recovery with a mark on the
base. If it differs from the reported θ the stepper lost steps (the firmware cannot
know: θ is the count of issued steps).

*On the rig (2026-10-21, the swing-up's balancing LQR, not the T6 PID):* 15 of 17 hand
pushes up to 83 deg/s were recovered, close to the simulated curve for that controller
(recoverable up to 100 deg/s); a 115 deg/s push was lost
(`results/reports/2026-10-21d_rig_session.md`, section 4). Press **PUSH MARK** after each
push to get a 500 Hz record of it.

### B. Simulation

**S3-8 (B8) Nonlinear model, discrete PID, slowest loop rate.** No Simulink here
(base MATLAB only). The equivalent is `odyssix.sim.runCtrl`: the nonlinear rigid
pendulum, the firmware's discrete controller at 500 Hz line for line (proved identical
to the C code by `matlab/tests/test_sim_matches_firmware.m`), quantisation and limits.
Measure your pendulum (T1 → FREE SWING) and press **USE MEASURED PENDULUM**.
Compare the tap recovery with A7. Slowest loop rate: the `div` field (500/div Hz) or
`gainSweep(6,'div',1:50)`. Prediction: balances down to **16.7 Hz**, fails at 14.3 Hz
(`PEND_sim_div.csv`); this can be tried on the rig with `$div` as well. If you build a
Simulink model on a machine that has it, check it against these numbers.

### C. Theory

**S3-9 (C9) Linearisation and poles.** `docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md`:
hanging ψ̈ = −ωg²ψ − γψ̇ + ωr²θ̈ (poles −0.14 ± 7.55j: stable); upright
α̈ = +ωg²α − γα̇ + ωr²θ̈ (poles +7.29, −7.66: one unstable). With your L:
p ≈ √(g/L). `odyssix.pend.unstablePole(L)` gives p, the tilt-doubling time
ln2/p (95 ms for p = 7.29), and the loop-rate rule of thumb (≳ 23 Hz). Compare it with
the 16.7 Hz found in B8: only ~2.3 samples per time constant 1/p = 137 ms, which is why
balance degrades sharply there (pendulum rms 0.49° at 500 Hz → 1.16° at 16.7 Hz).

**S3-10 (C10) LQR.** **LAB · upright · LQR** + the app's LQR designer (and **T10** for the rotor alone),
`experiments/EXP023`. The Q/R table there: larger R → gentler and slower; larger θ weight
→ faster arm, more pendulum error. Versus PID tuning: one design step with interpretable
weights instead of two interacting loops and a sign puzzle.

**S3-11 (C11) Quantisation and the D term.** One count is 0.15°; at 500 Hz a one-count
change is a 75 deg/s derivative spike, × Kdp 30 = 2250 deg/s² of plant input, more than
the 1500 limit. The firmware's first-order D filter (fdp 10 Hz) reduces the rms from
31.8 to 4.3 deg/s with 16 ms of lag (`odyssix.pend.derivativeNoise`, `PEND_sim_dnoise.csv`).
On the rig: raise the fdp field (less filtering) and Kdp, and watch u become noise.

**S3-12 (C12) Swing-up.** Energy E = ψ̇²/(2ωg²) + 1 − cos ψ (0 hanging, 2 upright);
dE/dt = (ψ̇/ωg²)(ωr² cos ψ · u − γψ̇), so u = u_max·sign(ψ̇ cos ψ) pumps energy in, and
an LQR catches the pendulum near the top. `pend_swingup_study.m` (**simulation
only**): at 1500 deg/s² it reaches and catches upright in 3.0 s with 65° of arm travel.
A linear PID cannot do it: the linear model assumes cos ψ ≈ −1 (near upright), but below
horizontal cos ψ changes sign and the same arm acceleration pushes the pendulum the
**other** way. sin ψ ≈ ψ is also 36 % wrong at 90°, and a linear law has no notion
of energy. **On the rig** (LAB → PENDULUM 180, firmware 2.2.0, 2026-10-21) the energy
swing-up caught the pendulum upright in 3 of 3 attempts at 7.1–8.0 s, swing for swing
like the simulation (`results/reports/2026-10-21_rig_session.md`). The first designs
stalled about 30° short: pivot friction drains about 0.2 of E per climb, so the
firmware learns that loss (δ) swing by swing (`experiments/EXP024`).
**Any other angle:** a pendulum can rest only at 0° or 180°. Holding it still at ψ
needs a constant arm acceleration (ωg²/ωr²)·tan ψ, infinite at 90°. The PENDULUM target
therefore controls the swing height E* = 1 − cos a: it swings to exactly ±a and stays
there (simulation: 45/90/135° → 46/92/136°), and 0 stops a swing.

---

*Every number here traces to a script in this repository; rerun
`pend_predictions` after changing the plant to your measured values.*

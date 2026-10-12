# Rig runs 2026-10-12: Tutorials 1–5 vs simulation

Board 1 (ST-LINK …124223), firmware 2.0.7 (ELF sha256 f886b5cc…7e), raw log
`results/evidence/logs/rig_20261012-225446.log`, data `data/raw/EXP00{2,3,4}/*_fcba006.csv`.
Simulation: `odyssix.sim.runTutorial` with the Tutorial plant values (no free-swing
identification yet), same gains; metrics from `odyssix.sim.metrics` on both.

| Run | Gains (Kp, Kd / Kpp, Kdp) | Metric | Rig | Sim |
|---|---|---|---|---|
| T2 | 9.275, 3.9 / – | overshoot | 23.75 % | 23.75 % |
| | | settling | 1.22 s | 1.23 s |
| | | disturbance offset (pred. D/Kp 0.108°) | 0.112° | 0.113° |
| | | rotor RMS(rig − sim) | 0.043° | |
| T3 | 6, 4.8 / 10, 5 | overshoot | 51.9 % | 35.0 % |
| | | final rotor (ref 2°) | 2.48–2.59° | 2.00° |
| | | pendulum at rest after the step | −0.30° | −0.01° |
| T4 | 6, 4.8 / 10, 5 | first 10 s | rotor 3.04°, pendulum −0.60° at rest | 2.00°, 0° |
| | | t = 10.5 s and 17.5 s | pendulum jumps to −40° / −21° from rest, loop recovers in ≈ 2 s | – |

## Discrepancy analysis
* **T2 matches** the simulation to the microstep. The pendulum was not clamped
  (it swung up to 11.6°); T2's loop does not use it, so the result stands.
* **T3/T4 steady offset is explained by a static pendulum offset.** At rest the
  pendulum stayed 2–4 encoder counts off vertical (−0.30°, −0.60°), most likely
  pivot Coulomb friction (not in the model). In steady state the PD terms balance:
  Kp·(θ − 2°) = Kpp·|ψ| ⇒ θ = 2 + 10·0.30/6 = **2.50°** (measured 2.48–2.59°) and
  2 + 10·0.60/6 = **3.00°** (measured 3.04°).
* **T4 jumps are external disturbances**, not instability: the rig was at rest,
  then the pendulum went to −40° within 0.5 s (a growing oscillation would build
  up over several periods). The loop rejected both. The T4 overshoot metric is
  therefore not meaningful for this run; repeat without touching the rig.
* **T5 not run**: both attempts aborted PENDULUM_LOST at once because the run was
  started with the pendulum hanging (fixed in the app, commit 7fe9d4a).

## Status
Not an acceptance result: the free-swing identification (ωg², Q) has not been
done, so the simulation still uses the Tutorial's plant values.

## Tutorial 5 attempts (`rig_20261012-233321.log`) and the fix in 2.0.8
* Attempt 1 (Kp 9, Kd 9): captured, then for 0.56 s the pendulum read within
  ±0.6° of upright while the arm drifted 0 → 6°. Then the command saturated at
  +1500 deg/s² with the pendulum only −1.35° off (arm to 35°, ≈280°/s); on the
  reversal the pendulum went 0.45 → 6 → 9.6 → 13.65° in 60 ms → PENDULUM_LOST.
* Attempt 2: aborted while waiting for capture (pendulum moved > 15° in the hand).
* Attempt 3 (Kp 17.075): same pattern, lost 0.6 s after capture.
* **Cause:** the pendulum was still held when the loop closed (the procedure said
  to hold it until the arm balances). A held pendulum cannot respond, so the
  sign-inverted outer loop drives the arm away; the 15° limit only recorded
  the loss. Emulator (`--batch exp=5 release=S`): released at capture → balanced;
  held ≥ 0.4 s after capture → lost, for Kp 9 and 17.075.
* **Not the 15° limit:** at u_limit 1500 deg/s² a pendulum cannot even be held
  static beyond ≈ 20° (θ̈ ≥ (g/r)·tan α ⇒ tan α ≤ 1500/3988), and at the abort it
  was moving at ≈ 200°/s. UCLA's limit is ±120° but it is a safety stop, not a
  recovery margin.
* **Fix (2.0.8, flashed 2026-10-12 23:53, `flash_20261012-235309.log`):** after
  capture the motor stays still until the pendulum moves 1.5° on its own (the
  hand has let go). Emulator: holding 0, 0.5, 2 or 10 s all balance identically.
  Not yet verified on the rig.

## Tutorial 5 on firmware 2.0.8 (2026-10-12 23:56 – 2026-10-13 00:15)
Logs `rig_20261012-235605.log`, `rig_20261012-235811.log`, `rig_20261013-000426.log`;
data `data/raw/EXP005/*_25f2101.csv`. Gains: System 1 (Kp 9, Kd 9; inner 300, 30).

| Run | Hand held after capture | Time under control | α RMS | Arm range | End |
|---|---|---|---|---|---|
| 1 (`182741`) | 1.1 s | 38.2 s | 0.43° | −8 … 33° | operator ABORT |
| 2 (`182942`) | 0.7 s | 26.3 s | 1.11° | −23 … 47° | PENDULUM_LOST in HOLD |
| 3 (`183152`) | 3.6 s | 77.9 s | 1.12° | −4 … 74° | PENDULUM_LOST in HOLD |
| 4 (`183622`) | 1.3 s | 18.7 s | 0.64° | 0 … 27° | SATURATION in HOLD |

"Under control" counts from the first actuator command (the release), not from
capture. Every run went through BALANCE → ROTOR_STEP → SETTLE → HOLD.

Simulation (Tutorial plant): wrong-way undershoot −34 %, arm hunting 0.56°, α peak 2.1°.

* **The capture-and-release fix works, and the rig confirms its cause:** in all
  4 runs the operator kept holding the pendulum 0.7–3.6 s after capture. On 2.0.7
  (control from capture) the emulator loses the pendulum after any hold ≥ 0.4 s;
  2.0.8 waited for the release each time and balanced through the whole
  Tutorial 5 sequence (0 of 3 attempts before 2.0.8).
* **Losses were external events, not instability.** Each time α sat within
  ±0.3° and then moved 3–7° in one 60 ms sample, which a pendulum at rest cannot
  do under gravity. After every run the hanging pendulum read within 0.6° of its
  datum (1.15° after run 4), so the encoder did not lose the 20–45 counts such a
  jump would need: the motion was real. Likely contact (hand, encoder cable
  drag); not confirmed. Next time: film the rig and tie the encoder cable.
* **Arm wander is an upright-reference bias.** Mean α in HOLD was +0.29°,
  +0.80°, −0.16°. With a bias b the loops settle at θ ≈ Kpp·b/Kp (= 300·0.8/9 ≈
  27° for run 3), which matches the drift. The bias comes from the hanging datum
  (pivot friction leaves the hanging pendulum 0.3–0.6° off true vertical). UCLA
  corrects this with a slow running estimate of the upright angle
  (`LP_CORNER_FREQ_LONG_TERM`); a candidate for the next experiment.
* Tutorial 5 metrics (undershoot, overshoot) are therefore dominated by the
  wander and not yet comparable with the simulation.

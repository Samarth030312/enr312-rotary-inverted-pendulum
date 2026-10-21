# ENR312 rotary pendulum lab: student quickstart

One MATLAB app runs every experiment, in simulation and on the real rig, and records
every rig run. For the PEND lab report, start from [the PEND answer guide](PEND_ANSWER_GUIDE.md).

```matlab
cd <this repository>
addpath(genpath('matlab'))
enr312_lab
```

## The screen

| Where | What |
|---|---|
| left | **MISSION** buttons (T1–T10 and LAB), the preset, and only the parameters this mission uses (type a number, Enter) |
| centre | the rig in 3-D, big live numbers (arm θ, pendulum, input u, phase), one status line |
| right | arm, pendulum, and one analysis plot (poles, Nyquist, impulse response, …). Grey = simulation, blue/orange = rig, violet = a replayed run |
| bottom left | CONNECT · ARM · START · RUN · STOP · ZERO DATUMS · SIMULATE |
| bottom centre | the numbers that matter (SIM / RIG / REF) and the live controls **ARM** and **PENDULUM** |
| bottom right | **RUNS**: every recorded run. Select one, then **OVERLAY RUN** draws it over the plots. **▶ PLAY** plays the run (or the simulation) on the 3-D rig; press again to pause, drag the time bar to scrub, pick 0.5×–4×. Nothing plays until you press PLAY. **NEXT ›** walks you through all experiments in order |

## Missions

| | What it teaches | Rig |
|---|---|---|
| **T1 · Actuator** | the stepper moves exact microsteps; every start and stop kicks the pendulum | hanging |
| **T2 · Sensitivity** | T(s) and S_D(s): after a load step a PD sits off by D/Kp | pendulum removed or clamped |
| **T3 · Effort** | lower gains = less control effort, slower response | hanging |
| **T4 · MIMO S(s)** | how close L(jω) comes to −1 (M_S) | hanging |
| **T5 · Inverted** | balancing; the arm first moves the wrong way (RHP zero) | upright, two people |
| **T6 · Integral** | Ki removes offsets and costs phase margin | upright |
| **T7 · Pendulum PD** | design the balancing loop; averaged impulse responses | upright |
| **T8 · Disturbance** | under a constant load: −D/Kp without Ki, 0 with Ki | upright |
| **T9 · Poles** | state feedback, k1 = ωN², k2 = 2ζωN | hanging |
| **T10 · LQR** | choose Q and R, press LQR → k | hanging |
| **LAB · Free** | hanging or upright; PID, LQR (recommended upright), state feedback, on-off; drive it live | either |

## Live controls (during a run)

- **ARM [angle] GO TO / STEP / HOME 0°:** slewed or instant set-point for the arm.
  Hanging: at any time. Upright: once it balances (HOLD).
- **PENDULUM [angle] SWING:**
  - **180°** swings the pendulum up and balances it.
  - **0 < a < 180°** swings it to exactly ±a and keeps that height.
  - **0°** stops a swing.

  A pendulum can **rest** only at 0° or 180°: holding it still at any other angle
  would need the arm to accelerate forever. That's why a target in between is a
  swing height.
- **Gains** typed during a run act on the running controller at once and are recorded as events.
- **PUSH MARK:** press it right after pushing the pendulum on purpose. The push is logged
  with the run, and the firmware (2.3.3) sends the last 1.5 s at 500 Hz, saved beside the
  run.
- **LAB → hanging → Energy (swing / swing-up)** shows the energy controller's own
  parameters (pump, arm centring, catch LQR), not PID gains.

## Recording

Every rig run is saved automatically, even when it aborts:
- `data/raw/EXPnnn/EXPnnn_<date-time>_<label>_Rnn.csv` (read-only)
- `data/metadata/EXPnnn/<same>.yaml` and `.json`: gains, plant, firmware, board, every
  live action with its time, the metrics, the result, and the raw serial log
- one line in `data/metadata/run_index.csv`

Emulator runs go to `matlab/data/synthetic/` and are never mixed with real data. Load
any run in MATLAB with `[D, M] = odyssix.data.loadRun('<run id>')`.

## First, measure your pendulum
T1 → **FREE SWING · record 15 s** (motor SAFE): displace 10–20° and let go. You get the
period, L, the ruler length to expect, ζ, ωg² and Q (PEND A4). Then **USE MEASURED
PENDULUM**: the simulation and the swing-up use your pendulum from then on.

## Safety on the rig

* **ABORT**, **Esc** or **Space** stops everything at once. Pulling the 12 V plug always works.
* ARM energises the motor (it holds; it does not move). START allows motion. Nothing
  moves until RUN or SWING.
* The firmware stops by itself on:
  * the pendulum past 15° from upright (upright runs) or 120° from hanging (others);
  * the arm past 240°;
  * sustained saturation;
  * the speed ceiling;
  * a driver fault;
  * **MATLAB going silent for 1 s**.
* **Upright runs:** zero the datums with the pendulum hanging. One person holds the
  pendulum upright and still, then RUN. After 1 s within ±2° the app shows **LET GO NOW**
  and beeps. The motor waits until the pendulum moves on its own. The other person keeps a
  hand on ABORT. STOP ends the run; until then it keeps balancing.
* **SWING UP:** clear the arm's sweep for a half turn either way; hands away from overhead.

## If the board is not found
Unplug the Nucleo's USB, wait 5 s, plug it back in. Close any other program on the serial
port (Arduino IDE, another MATLAB app). No board at all: CONNECT offers the **emulator**,
the firmware's own code on your PC.

## Instructor: before the first session
1. `scripts/flash_ready_check.sh` must end in **SOFTWARE FLASH READY: YES**.
2. Wire and check the rig: `docs/hardware/ENR312_WIRING.md` §4.
   ⚠ On the kit's 12 V supply, the **black wire with the white stripe is +12 V**.
3. Flash: `odyssix.stm32.flash()` (checks the image hash and the chip). CONNECT, turn the
   pendulum one full turn by hand, and check that it reads 360°.
4. T1 → RUN: check the +5° move with a protractor.
5. T1 → FREE SWING, then USE MEASURED PENDULUM.

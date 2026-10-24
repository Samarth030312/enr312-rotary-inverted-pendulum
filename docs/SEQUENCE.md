# Run everything, in order

One page, from a fresh computer to a balancing pendulum and a checked data set.
Steps 1–3 need no hardware. Each step says where its details are.

## 0. Get it (once)

In the MATLAB Command Window:

```matlab
gitclone("https://github.com/Samarth030312/steval-edukit.git", Depth=1); cd steval-edukit; setup open
```

`setup` checks the computer and opens the lab app. Next time: `cd steval-edukit; setup open`.
Drivers and per-system notes: [install guide](INSTALL.md).

## 1. The simulator (no rig)

In the app, press **NEXT EXPERIMENT ›** (under the mission buttons) repeatedly: it walks through T1 to T10, then LAB hanging
PID, on-off, upright LQR and the swing-up. For each one press **PLAY SIMULATION**, then
**▶ PLAY** to watch it in 3-D. Change a gain, press Enter, and simulate again.
[Simulator guide](guide/README.md).

## 2. Simulink (needs Simulink)

```matlab
P = enr312_simulink_params();            % measured pendulum, LQR
open_system('enr312_pendulum')           % press Run; double-click the scopes
out = sim('enr312_pendulum'); animate_enr312_simulink(out)    % the rig in 3-D
run_enr312_simulink()                    % all five Assignment 3 situations, about 7 min
```

[Simulink model and Assignment 3](SIMULINK.md).

## 3. Recorded data (no rig)

In the app: **RUNS** → select a run → **OVERLAY RUN** → **▶ PLAY**. Runs with 500 Hz
records show them as dots. In MATLAB:

```matlab
[D, M] = odyssix.data.loadRun('EXP024_20261021-210043_swing-up_R15');   % 50 Hz data, metadata
K = odyssix.data.loadRecords('EXP024_20261021-210043_swing-up_R15');    % its 500 Hz records
check_all_runs()                         % every run loaded, checked and drawn on one sheet
plot_session_20261021d(tempdir)          % the last session's figures, redrawn (into tempdir)
```

[Data](../data/README.md) · [results](RESULTS.md).

## 4. The rig

Before power: wiring and the staged power-up check, [wiring](hardware/ENR312_WIRING.md) §4.
Then, with the 12 V supply off:

1. Plug the Nucleo in by USB. `setup` shows the board.
2. If the app says **NO DATA** after CONNECT, flash this firmware:
   `odyssix.stm32.flash()`. It checks the image and the chip, then writes and resets.
   The board starts in SAFE: the motor is off.
3. **CONNECT**. Let the pendulum hang still, press **ZERO DATUMS**.
4. Turn on 12 V. **T1 → FREE SWING** (motor stays off): lift the pendulum 10–20°, let
   go. When the app asks, press **Use it**.
5. **NEXT EXPERIMENT ›** through T1 to T10 again, now with **ARM → START → RUN** on each. Upright
   tutorials need two people: one holds the pendulum up, one keeps a hand on **ABORT**
   (or Esc / Space). [Upright procedure](../experiments/PROCEDURE_UPRIGHT.md).
6. **LAB → hanging → SWING → 180°**: the swing-up. Clear half a turn of space for the arm.
7. While it balances, push the pendulum and press **PUSH MARK** right after each push.

Every run is saved by itself, aborted ones too. Pulling the 12 V plug always stops the
motor.

## 5. Analyse

```matlab
check_all_runs()                                     % the new runs are checked with the old
D = odyssix.data.loadRun('<the free-swing run id>');
r = odyssix.pend.freeSwing(D.t, D.psi)               % period, length, damping, your wg2
```

Compare each result with the simulation in the app (SIM and RIG columns side by side),
and add a session report under `results/reports/` the way the earlier ones are
written.

## 6. Check the software (optional, Linux or macOS)

```bash
scripts/flash_ready_check.sh        # must end SOFTWARE FLASH READY: YES (about 10 min)
```

```matlab
test_simulink_matches_runctrl       % Simulink agrees with the firmware's code
```

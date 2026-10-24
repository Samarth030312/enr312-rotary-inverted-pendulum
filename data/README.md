# Data

Everything in here was measured on the real rig (an STMicroelectronics STEVAL-EDUKIT01
rotary pendulum, NUCLEO-F401RE). Nothing in `raw/` is simulated, and nothing in it is
ever edited. Simulated and emulator runs go to `matlab/data/synthetic/` and are not in
this repository.

47 runs, 22 minutes of 50 Hz data, from five sessions (2026-10-12; 2026-10-21 morning, evening, late and last), plus 8 records at 500 Hz.

`check_all_runs()` (MATLAB) loads every run the way the app does, checks it and draws
all of them on one sheet: [overview](../results/figures/all_runs_overview.png),
[table](../results/tables/ALL_RUNS_check.csv). On 2026-10-24 all 47 passed; the median
load took 0.13 s and the 500 Hz records were placed on their runs within 0.12° rms.

| Experiment | | Runs | Days |
|---|---|---|---|
| [EXP001](raw/EXP001/) | T1 actuator | 14 | 2026-10-12, 2026-10-21 |
| [EXP002](raw/EXP002/) | T2 sensitivity | 2 | 2026-10-12, 2026-10-21 |
| [EXP003](raw/EXP003/) | T3 control effort | 2 | 2026-10-12, 2026-10-21 |
| [EXP004](raw/EXP004/) | T4 MIMO sensitivity | 2 | 2026-10-12, 2026-10-21 |
| [EXP005](raw/EXP005/) | T5 inverted | 6 | 2026-10-12, 2026-10-21 |
| [EXP006](raw/EXP006/) | T6 integral | 1 | 2026-10-21 |
| [EXP007](raw/EXP007/) | T7 pendulum PD | 3 | 2026-10-21 |
| [EXP008](raw/EXP008/) | T8 disturbance | 1 | 2026-10-21 |
| [EXP009](raw/EXP009/) | T9 pole placement | 2 | 2026-10-21 |
| [EXP010](raw/EXP010/) | T10 LQR | 1 | 2026-10-21 |
| [EXP021](raw/EXP021/) | stop a swing, hold an angle | 1 | 2026-10-21 |
| [EXP024](raw/EXP024/) | energy control, swing-up | 12 | 2026-10-21 |

What each session found:
- [2026-10-12](../results/reports/2026-10-12_rig_tutorials_1-5.md): first runs, Tutorials 1–5 (protocol 2, no `alpha` column)
- [2026-10-21 morning](../results/reports/2026-10-21_rig_session.md): first swing-ups, 3 of 3
- [2026-10-21 evening](../results/reports/2026-10-21b_rig_session.md): all ten tutorials, pendulum target, the pendulum identified, why 2.3.0 did not catch
- [2026-10-21 late](../results/reports/2026-10-21c_rig_session.md): free swing (ωg² 48 ± 1), firmware 2.3.2 swing-up caught at 3.88 s
- [2026-10-21 last](../results/reports/2026-10-21d_rig_session.md): six free swings (ωg² 48.0 ± 0.5), swing-up 4 of 4, push test 15 of 17, 500 Hz records

## Layout

```
raw/EXPnnn/<run>.csv          the samples, read-only
metadata/EXPnnn/<run>.yaml    gains, firmware, plant, live actions, metrics, result
metadata/EXPnnn/<run>.json    the same, for scripts
metadata/run_index.csv        one line per run
processed/                    derived data (each file names its source run)
raw/EXPnnn/<run>_500Hz_<n>.csv   from firmware 2.3.3: every control tick around an abort or a
                                 PUSH MARK (t_s from the trigger, tick, rotor_deg, psi_deg,
                                 alpha_deg, u, phase); metadata as <run>_500Hz_<n>.json
```

Run names: `EXPnnn_<UTC date>-<time>_<label>_Rnn`, for example
`EXP024_20261021-161431_swing-up_R04`. The four-digit-time names with a git hash at the
end (`EXP001_20261012_170911_b64cd66`) are from the first session, before the app
named runs.

## Columns

The firmware runs its control loop at 500 Hz and streams every 10th sample (50 Hz).

| Column | Unit | Meaning |
|---|---|---|
| `t` | s | time since the run started (MCU ticks, not PC time) |
| `rotor` | deg | arm angle θ, commanded microsteps × 0.1125° (the arm has no encoder; the stepper does not lose steps below its limits) |
| `psi` | deg | pendulum angle ψ from the hanging datum, encoder 2400 counts/rev (0.15°). |
| `alpha` | deg | pendulum from upright, α = ψ − 180° wrapped (2026-10-21 on) |
| `u` | deg/s² | arm acceleration command, the plant input |
| `ref` | deg | arm set-point |
| `phase` | — | 0 wait capture, 1 wait release, 2 balance, 3 step, 4 step back, 5 load on, 6 load off, 7 impulses, 8 hold, 9 idle, 10 regulate, 11 swing-up, 12 done, 13 aborted |

## Using it

```matlab
addpath(genpath('matlab'))
odyssix.data.listRuns()                                   % everything, as a table
[D, M] = odyssix.data.loadRun('EXP024_20261021-161431_swing-up_R04');
plot(D.t, D.psi)
```

Or open `enr312_lab`, pick the run in RUNS, press OVERLAY RUN and then PLAY.
The raw serial transcripts of both sessions are in `results/evidence/rig_sessions/`.

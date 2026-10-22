# Data management

> **Raw data is evidence. It is never edited, never overwritten and never deleted,
> including when the run failed.** A failed run is a result.

What is in `data/` today, with every run listed: [`data/README.md`](../data/README.md).

## 1. Three kinds of data, never mixed

| Kind | Meaning | Where | In git |
|---|---|---|---|
| **HARDWARE** | measured on the rig | `data/raw/EXPnnn/`, `data/metadata/EXPnnn/` | yes |
| **SYNTHETIC** | from the emulator, to exercise the pipeline | `matlab/data/synthetic/` | no |
| **SIMULATION** | from a model | `results/figures`, `results/tables`, labelled as simulation | yes |

The app decides the kind by itself: a run on the emulator is always SYNTHETIC and can
never land in `data/raw`.

## 2. How a run is recorded

`enr312_lab` records every rig run automatically, through `odyssix.data.saveRun`. The
run is recorded when it ends: finished, stopped or aborted.

| File | Content |
|---|---|
| `data/raw/EXPnnn/<run>.csv` | the 50 Hz stream: t, rotor, psi, alpha, u, ref, phase. **Made read-only** on writing |
| `data/metadata/EXPnnn/<run>.yaml` and `.json` | see below |
| `data/metadata/run_index.csv` | one line per run: id, experiment, class, date, label, result, duration, key metrics |
| `data/raw/EXPnnn/<run>_500Hz_<n>.csv` + `.json` | firmware 2.3.3 crash records: every control tick around an abort or a PUSH MARK |

Run names: `EXPnnn_<UTC date>-<time>_<label>_Rnn`, for example
`EXP024_20261021-210043_swing-up_R15`. Rnn counts that experiment's runs of the day.

The metadata of each run holds:

- **Identity:** run id, experiment, class, UTC date, label, result, duration, number of
  samples.
- **Provenance:** the firmware's version line, the protocol, the repository revision,
  and whether the working tree had uncommitted changes; the serial port and the raw
  serial log.
- **Configuration:** every gain and limit sent to the firmware, and the model pendulum
  used for the simulation next to it.
- **Events:** every live action with its time: set-points, gain changes, pendulum
  targets, push marks, stop.
- **Metrics:** computed by `odyssix.sim.metrics`, the same function as for the
  simulation.
- **Units** of every column.

The serial transcript of each session is kept in `results/evidence/rig_sessions/`.

## 3. Rules for analysis

1. Read from `data/raw/`; never write there.
2. Every figure and table is produced by a script in `matlab/plotting/`,
   `matlab/identification/` or `matlab/experiments/`. The script names its source
   runs, and its output says which parts are simulation.
3. When an analysis method improves, the stored metadata keeps the numbers of the old
   method. The reports give the new ones and say why. Example: the free-swing fit of
   2026-10-21 (`results/reports/2026-10-21d_rig_session.md`, section 1).
4. Corrections to a report are made in the report, dated, with the first version kept
   in git history.

## 4. Units and conventions

| Quantity | Unit | Convention |
|---|---|---|
| angles | deg | the models work in rad internally |
| t | s | MCU time from the start of the run (500 Hz ticks, 50 Hz stream) |
| rotor | deg | commanded microsteps ÷ 8.889; the arm has no sensor |
| psi | deg | encoder, 0 = the hanging datum set by ZERO DATUMS; 2400 counts/rev |
| alpha | deg | 180° − psi, wrapped to (−180, 180] |
| u | deg/s² | arm acceleration commanded by the controller |
| signs | | measured on the rig (EXP001): encoder polarity −1, rotor +1 |

## 5. Failed runs

Failed runs are kept like any other, with the abort reason in their result.
A recording of the pendulum falling is a real measurement of an unstable plant.

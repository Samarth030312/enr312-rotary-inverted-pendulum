# EXP001 Raw Data — IMMUTABLE

**Empty. No experimental data exists.** No hardware has been attached
(`st-info --probe` → 0 programmers).

## Schema

CSV written by `ENR312_Exp001_CsvHeader()` / `ENR312_Exp001_FormatCsv()`:

```
tick,t_s,phase,rotor_cmd_microsteps,rotor_cmd_deg,encoder_counts,pendulum_deg,pendulum_vel_rad_s,abort_reason
```

| Column | Unit | Meaning |
|---|---|---|
| `tick` | — | control ticks since start |
| `t_s` | s | **nominal only** = `tick × T_s`. A restatement of an assumption, not a measurement of time (EXP003/OI-10) |
| `phase` | — | 0 idle, 1 sense-only, 2 P1 staircase, 3 P3 cycles, 4 done, 5 aborted |
| `rotor_cmd_microsteps` | microsteps | **commanded**, not measured — no rotor sensor exists |
| `rotor_cmd_deg` | deg | commanded |
| `encoder_counts` | counts | relative to the start-latched origin |
| `pendulum_deg` | deg | measured |
| `pendulum_vel_rad_s` | rad/s | raw backward difference; σ ≈ 0.534 rad/s unfiltered |
| `abort_reason` | — | 0 none, 1 pendulum limit, 2 rotor limit, 3 operator |

`scripts/exp001_process_measurements.py` refuses to run on a mismatched header rather
than guessing at column meanings.

## Invariants a valid run must satisfy

1. `abort_reason` is 0 throughout.
2. Encoder counts monotonic during smooth one-directional hand rotation.
3. Metadata records the **measured** encoder and rotor polarities, not placeholders.

## What the telemetry cannot tell you

Predictions **P1** and **P3** need the **physical** arm angle read off an index mark with
a protractor. There is no rotor sensor, so no script can supply it. Those readings go by
hand into `experiments/EXP001/MEASUREMENTS.md`.

## Naming

`EXP001_<YYYYMMDD>_<HHMM>_<short-git-rev>.csv`, with a metadata sidecar of the same stem
in `data/metadata/EXP001/`. **Files here are never modified.**

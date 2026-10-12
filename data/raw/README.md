# Raw Experimental Data — IMMUTABLE

**This directory is empty. No experimental data exists.**

No target hardware has been attached to the development machine
(`st-info --probe` → 0 programmers; no `/dev/ttyACM*`). Nothing has been measured.

## Rules

1. Files here are **never** modified, overwritten, or deleted.
2. Every raw file has a metadata sidecar in `../metadata/` with the same stem.
3. Naming: `EXP<NNN>_<YYYYMMDD>_<HHMM>_<short-git-rev>.csv`
4. Derived data goes to `../processed/`, never here.

## Expected EXP001 format

CSV written by the firmware sequencer
(`ENR312_Exp001_CsvHeader` / `ENR312_Exp001_FormatCsv`):

```
tick,t_s,phase,rotor_cmd_microsteps,rotor_cmd_deg,encoder_counts,pendulum_deg,pendulum_vel_rad_s,abort_reason
```

| Column | Unit | Note |
|---|---|---|
| `tick` | — | control ticks since start |
| `t_s` | s | **nominal only**: computed as `tick × Ts` by the firmware. This is a restatement of an assumption, not a measurement of time. Real timing is EXP003. |
| `phase` | — | 0 idle, 1 sense-only, 2 P1, 3 P3, 4 done, 5 aborted |
| `rotor_cmd_microsteps` | microsteps | **commanded**, not measured — the arm has no sensor |
| `rotor_cmd_deg` | deg | commanded |
| `encoder_counts` | counts | relative to the start-latched origin |
| `pendulum_deg` | deg | measured |
| `pendulum_vel_rad_s` | rad/s | raw backward difference; σ ≈ 0.534 rad/s, unfiltered |
| `abort_reason` | — | 0 none, 1 pendulum limit, 2 rotor limit, 3 operator |

`scripts/exp001_process_measurements.py` refuses to run if the header does not match
exactly, rather than guessing at column meanings.

## What the telemetry cannot tell you

Predictions P1 and P3 need the **physical** arm angle read off an index mark with a
protractor. There is no arm sensor, so no script can supply this. Those readings are
entered by hand into `experiments/EXP001/MEASUREMENTS.md`.

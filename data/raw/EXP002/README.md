# EXP002 Raw Data — IMMUTABLE

**This directory is empty. No experimental data exists.** No hardware has been attached
(`st-info --probe` → 0 programmers).

## Schema

CSV written by `ENR312_Exp002_CsvHeader` / `ENR312_Exp002_FormatCsv`:

```
tick,t_s,phase,reference_deg,disturbance,noise_deg,error_deg,u,rotor_deg,abort_reason
```

| Column | Unit | Meaning |
|---|---|---|
| `tick` | — | control ticks since start |
| `t_s` | s | **nominal only** — computed as `tick × T_s` by the firmware. A restatement of an assumption, not a measurement of time. Real timing is EXP003 |
| `phase` | — | 0 idle, 1 ref-step, 2 ref-settle, 3 dist-step, 4 dist-settle, 5 done, 6 aborted |
| `reference_deg` | deg | `R`, at the comparator |
| `disturbance` | plant-input units | `D`, at the **plant input** |
| `noise_deg` | deg | `N`, at the **sensor** |
| `error_deg` | deg | `e = R − (Y + N)` |
| `u` | plant-input units | `U = sat(controller output) + D` |
| `rotor_deg` | deg | `Y`, rotor angle |
| `abort_reason` | — | 0 none, 1 rotor limit, 2 saturation, 3 operator |

`scripts/exp002_process_measurements.py` refuses to run if the header does not match
exactly, rather than guessing at column meanings.

## Invariants a valid run must satisfy

1. `reference_deg` and `disturbance` are **never simultaneously non-zero** — otherwise
   `T(s)` and `S_D(s)` cannot be separated from one record.
2. **Zero saturated samples.** Any clipping makes the loop nonlinear, and the measured
   response is then not a sensitivity function.
3. `abort_reason` is 0 throughout for a valid measurement.

## Naming and provenance

`EXP002_<YYYYMMDD>_<HHMM>_<short-git-rev>.csv`, with a metadata sidecar of the same stem
in `data/metadata/EXP002/`. **Files here are never modified.**

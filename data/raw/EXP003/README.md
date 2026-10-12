# EXP003 Raw Data — IMMUTABLE

**Empty. No experimental data exists.** No hardware attached.

## Schema

```
tick,t_s,phase,rotor_ref_deg,pend_ref_deg,rotor_deg,pend_deg,u_rotor,u_pend,u,abort_reason
```

| Column | Unit | Meaning |
|---|---|---|
| `tick` | — | control ticks since start |
| `t_s` | s | **nominal only** = `tick × T_s`. Not a timing measurement |
| `phase` | — | 0 idle, 1 rotor-step, 2 settle, 3 done, 4 aborted |
| `rotor_ref_deg` | deg | `φ_command` |
| `pend_ref_deg` | deg | `θ_command` — held 0 throughout Tutorial 3 |
| `rotor_deg` | deg | `φ` — **commanded, not measured** (no rotor sensor) |
| `pend_deg` | deg | `θ` — measured by the encoder |
| `u_rotor` | plant-input | `K_rotor` output, **before** saturation |
| `u_pend` | plant-input | `K_pend` output, **before** saturation |
| `u` | plant-input | `sat(u_rotor + u_pend)` — one saturation, on the sum |
| `abort_reason` | — | 0 none, 1 rotor limit, 2 pendulum limit, 3 saturation, 4 operator |

## Invariants a valid run must satisfy

1. `pend_ref_deg` is zero throughout — Tutorial 3 excites only the rotor.
2. **Zero saturated samples** (`|u| < 800`). Any clipping makes the control-effort
   metrics those of a nonlinear system.
3. `abort_reason` is 0 throughout.
4. The derivative filter corner used **must** be recorded in the metadata sidecar —
   `CE_Max` and `CE_Max_Power` are meaningless without it.

## Naming

`EXP003_<YYYYMMDD>_<HHMM>_<short-git-rev>.csv` with a metadata sidecar of the same stem in
`data/metadata/EXP003/`. **Never modified.**

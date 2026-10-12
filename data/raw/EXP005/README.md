# EXP005 Raw Data — IMMUTABLE

**Empty. No experimental data exists.**

## Schema

```
tick,t_s,phase,rotor_ref_deg,rotor_deg,pend_deg,u_rotor,u_pend,u,abort_reason
```

| Column | Meaning |
|---|---|
| `phase` | 0 wait-capture, 1 balance, 2 rotor-step, 3 settle, 4 done, 5 aborted |
| `pend_deg` | pendulum angle from **UPRIGHT** — a different datum from EXP003/EXP004 |
| `u_rotor` | `K_rotor` output **after** the inverted-mode sign inversion |
| `abort_reason` | 0 none, 1 **pendulum lost**, 2 rotor limit, 3 saturation, 4 operator |

## Invariants

1. `abort_reason` 0 throughout for a valid balance run.
2. `|pend_deg| < 15` throughout — beyond that the linear model does not describe the system.
3. Zero saturated samples.
4. Metadata **must** record that OI-10 (timing verification) was satisfied before the run.

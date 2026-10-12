# EXP004 Raw Data — IMMUTABLE

**Empty. No experimental data exists.**

## Schema

Identical to EXP003 — EXP004 changes the ANALYSIS, not the acquisition:

```
tick,t_s,phase,rotor_ref_deg,pend_ref_deg,rotor_deg,pend_deg,u_rotor,u_pend,u,abort_reason
```

## Additional metadata EXP004 requires

- **Controller realisation** (ideal, or filtered with its corner). `M_S` shifts ~0.3 dB
  between them.
- Derived `M_S`, `w_SC` and Nyquist closest approach, with the frequency grid used.

## Invariants

1. Zero saturated samples — frequency-domain metrics of a clipped loop are meaningless.
2. `pend_ref_deg` zero throughout.
3. `abort_reason` 0 throughout.

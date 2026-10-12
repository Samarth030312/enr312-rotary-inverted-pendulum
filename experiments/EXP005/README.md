> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP005/`.

# EXP005 — MIMO Unstable System Control (Inverted Mode)

| | |
|---|---|
| **Source** | Tutorial 5 · **Safety class: HIGH** |
| **Status** | Software complete; **hardware NOT_EXECUTED**; **MATLAB DEFERRED** |
| **Depends on** | EXP001–EXP004 · **EXP006+: outside this release** |

> ⚠ **First experiment with no benign failure mode.** RHP pole at +7.2888 rad/s — a
> **137 ms** fall time constant. If the loop opens, the pendulum falls and the arm slams.

## What changes: one sign

`G_pend = ω_r²s²/(s² + (ω_g/Q)s **−** ω_g²)`, with `ω_g² = 55.85` (not 57.01) and
`Q = 20` (not 27). Gravity restores a hanging pendulum and destabilises a standing one;
that is the sign, and it moves a pole to the right half plane.

## Three structural findings

**1. The inner controller now stabilises rather than damps.** `K_pend = 300 + 30s` — 30×
the suspended gain. It works: inner loop becomes `s² + 24.46s + 185.05`, `ζ = 0.899`.

**2. The outer loop must be inverted.** `T_rotor` has *negative* DC gain (−0.3018/s²), so
a positive `K_rotor` closes positive feedback. Established from evidence: with the
non-inverted sign **both** of Tutorial 5's own designs are unstable; with the inversion
both are stable and their relative stability reproduces the Tutorial's naming.

**3. Stabilising the unstable pole converts it into a non-minimum-phase zero** of
`T_rotor` at +7.2888 rad/s, capping bandwidth near **3.64 rad/s** regardless of `K_rotor`.
Observable as the step response **dipping the wrong way first** (−11 % to −40 %): the arm
must move away from the target to get under the pendulum. This is why Tutorial 5's targets
are so much looser than Tutorial 3's.

## Results

### Tutorial 5 §13 introduction designs
| | `K_P` | `K_d` | Settling | OS | Undershoot | `φ_M` | `GM` | `M_S` |
|---|---|---|---|---|---|---|---|---|
| Stable System 1 | 9 | 9 | 2.75 s | 23.6 % | −33.2 % | 47.3° | 6.01 dB | 6.37 dB |
| Quasi-Stable System 2 | 10 | 3.33 | 11.74 s | 70.8 % | −11.6 % | **17.5°** | 13.68 dB | **10.32 dB** |

System 2's margins are clearly poor — matching Tutorial 5's "not meeting stability
margins".

### Designs meeting §14 objectives
| | `K_P` | `T_d` | `K_d` | Settling | OS | `φ_M` | `GM` | `M_S` | Meets |
|---|---|---|---|---|---|---|---|---|---|
| **System 1** | 6.25 | 1.12 | 7.00 | 3.25 s | 24.8 % | 50.6° | 8.23 dB | 4.52 dB | ✔ |
| **System 2** | 0.50 | 21.5 | 10.75 | 0.83 s | 6.4 % | 58.6° | 4.76 dB | 7.86 dB | ✔ |

## Three source conflicts, all documented

1. **`K_d_pend`**: Tutorial 5 states `K_P=300, T_d=0.5, K_d=K_P·T_d=30` — but 300×0.5=150.
   `K_d=30` wins on two independent sources; implied `T_d` is **0.1 s**.
2. **System 2 `K_d`**: table says 3.33, serial transcript says 3.00. 3.33 used; both
   evaluated.
3. **"Improved performance"**: Tutorial 5 calls System 2 improved; the model shows it
   markedly worse (11.7 s vs 2.75 s). **UNRESOLVED — flagged for hardware.**

## Safety (materially tighter than EXP003)

| | EXP003 | **EXP005** |
|---|---|---|
| Pendulum abort | 120° | **15°** |
| Warning band | — | 10° held 100 ms |
| Capture gate | — | ±2° held 1 s before balancing |
| Saturation abort | 500 ms | 200 ms |

15° is chosen, not inherited: `sin` differs from the linear approximation by 1.2 % there,
so the small-angle model the design rests on is still valid.

## The most dangerous untested assumption

**Loop timing has never been measured.** A 500 Hz loop gives ~68 samples per fall time
constant — ample *if* the timing is what it is assumed to be. EXP005 is the first
experiment where inadequate or jittery timing causes a **fall**, not a poor response.
Open item **OI-10**.

## Artifacts
| Path | What |
|---|---|
| `firmware/enr312/{inc,src}/enr312_exp005.*` | Inverted-mode dual PID, capture gate, tightened safety |
| `firmware/enr312/test/test_enr312_exp005.c` | 36 host checks, incl. open-loop instability verification |
| `scripts/exp005_unstable_mimo.py` | Design tool — **executed** |
| `matlab/models/exp005_*.m`, `matlab/experiments/EXP005/` | **NOT_EXECUTED** |
| `results/figures/EXP005_fig1_step_and_nyquist.png` | Step + Nyquist |
| `results/tables/EXP005_design_results.csv` | Numerical results |

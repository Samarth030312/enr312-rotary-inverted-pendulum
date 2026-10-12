# Tutorial-by-Tutorial Execution Protocol

**Date:** 2026-08-20 · Operator-facing. Follow the numbered steps without interpretation.

> **Before any of this:** complete `docs/experiments/EXP001/HARDWARE_PROCEDURE.md`
> Stages 0–12. **Nothing below may be attempted until Stage 11 has passed.**
>
> Recording rules: `docs/EXPERIMENT_RECORDING_PROTOCOL.md`. Open the metadata sidecar
> **before** each run.

---

## Common to every experiment

```
PRE   git status --porcelain            -> must be empty
      git rev-parse --short HEAD; git describe --tags
      sha256sum <flashed elf>
      copy data/metadata/TEMPLATE.yaml -> data/metadata/EXP00N/<run-id>.yaml, fill it
      clear the swing path; 12 V switch within reach
POST  save CSV to data/raw/EXP00N/<run-id>.csv ; chmod 444 ; commit raw+metadata
      run the analysis; complete MEASUREMENTS.md, VALIDATION.md, CONCLUSION.md
E-STOP  Cut 12 V. It is the only emergency control. Power off first, diagnose second.
```

---

# EXP001 — Tutorial 1 · Digital Actuator & Angle Sensing

**Prereq:** Stage 0 blockers cleared (OI-1, datasheet, IHM01A1 manual, board layer).
**Hardware:** pendulum fitted and free · **Firmware:** `exp001-verified` + board layer
**Start state:** 12 V OFF, arm at index mark, pendulum hanging still

| Step | Action | Observe | Record |
|---|---|---|---|
| 1 | Dry run, `armed=false` | phases IDLE→SENSE→P1→P3→DONE; `rotor_cmd`=0 | completion |
| 2 | Hand-rotate pendulum 1 rev to the index mark | counts change monotonically | **P2:** counts/rev (expect **2400 ±4**) |
| 3 | Note rotation direction in prose | sign of Δcounts | **P2b:** polarity + prose description |
| 4 | 10 out-and-back rotations | residual not growing | **P4:** residual (±4 counts) |
| 5 | **12 V ON.** Command **one microstep** | arm moves; motor quiet | direction; any buzz/heat |
| 6 | Command **+45°** | — | **Stage 9 / C-1:** measured angle |
| 7 | Command −90°, then 0° | — | **P1:** each within ±1.8° |
| 8 | Write measured polarities into `enr312_rig_config.h`, rebuild, reflash | — | new commit hash |
| 9 | Full run `armed=true`, 2°, ≤1000 steps/s | 10 P3 cycles | **P3:** residual ±1.8°, not growing |

**Expected:** 2400 counts/rev; commanded ≈ achieved within one full step; zero net drift.
**Failure:** counts = 600/1200 → wrong decode mode. **Measured 22.5° at step 6 → the Edukit
Manual's 17.778 steps/° is right and every commanded angle is out by 2×** — stop and
correct the constant.
**Analysis:** `python3 scripts/exp001_process_measurements.py data/raw/EXP001/<run-id>.csv`
**MATLAB:** `exp001_run_analysis`
**Accept:** P1 ✔ P2 ✔ P2b recorded ✔ P3 ✔ P4 ✔

---

# EXP002 — Tutorial 2 · Sensitivity Function Analysis

**Prereq:** EXP001 complete; **OI-2 resolved** (signs measured)
**Hardware:** **pendulum REMOVED or CLAMPED** — rotor loop only
**Start state:** 12 V OFF, arm free over ±240°

| Step | Action | Observe | Record |
|---|---|---|---|
| 1 | Compute `u_peak = A(K_P + K_d·α/T_s)`; confirm < limit | — | predicted `u_peak` |
| 2 | Dry run | R and D never simultaneously non-zero | completion |
| 3 | **12 V ON.** `K_P=5, K_d=2.5`, R-step 2° | rotor tracks | **Q1:** peak, peak time, OS, settling |
| 4 | Continue into the D-step phase | response does **not** return to zero | **Q2:** steady offset (expect `1/K_P`=0.2) |
| 5 | Check saturated samples | — | must be **0** |
| 6 | Repeat with `K_P=6.55, K_d=4.0` | — | **recompute `u_peak` first — 485 > 400 limit (OI-8): reduce A to 1.5° or raise the limit deliberately** |

**Expected:** T peak 1.2676 @1.055 s, OS 26.76 %, settle 3.239 s; `S_D` → 0.2000 and
**never** to zero.
**Failure:** divergence → sign inverted, **cut 12 V**. `S_D` → 0 → unexpected integral
action. Any saturation → measurement invalid.
**Analysis:** `scripts/exp002_process_measurements.py` · **MATLAB:** `exp002_run_analysis`
**Accept:** Q1 ±10 % / ±5 pp · Q2 ±5 % · Q6 zero saturation

---

# EXP003 — Tutorial 3 · MIMO Control Effort (Suspended)

**Prereq:** EXP002 complete · **Hardware:** pendulum fitted, **suspended** ·
**Inner gains fixed 10 / 0 / 5**

| Step | Action | Observe | Record |
|---|---|---|---|
| 1 | Dry run | 4 phases; CE still accumulates | completion |
| 2 | **R2 first:** set `K_rotor = 0`, disturb pendulum by hand | **rotor drifts unboundedly** | drift rate + direction |
| 3 | Design 1 `K_P=6, T_d=0.8`; 2° step | — | settling, OS, `CE_Max`, `CE_Pwr`, `CE_Total` |
| 4 | **Record the derivative-filter corner used** | — | *`CE_Max` is meaningless without it* |
| 5 | Design 2 `K_P=1.5, T_d=1.15` | — | `CE_Total`; **reduction ≥2×** |
| 6 | Design 3 `K_P=0.3, T_d=2.5` | visibly sluggish | `CE_Total`; **reduction ≥2×** |

**Expected:** D1 ≈ 2.10 s / 32.4 % / CE_Total 10.90 · D2 3.99 s / 26.0 % / 3.78 (2.88×) ·
D3 9.15 s / 24.5 % / 1.65 (6.59×). Tutorial 3 permits absolute disagreement but requires
the **factor**.
**Failure:** no rotor drift at step 2 → unmodelled restoring effect. Growing pendulum
oscillation → **inner loop sign inverted, cut 12 V**.
**MATLAB:** `exp003_run_analysis` · **Accept:** settling/OS limits met and ≥2× reduction

---

# EXP004 — Tutorial 4 · MIMO Sensitivity Performance

**Prereq:** EXP003 complete · **Hardware:** identical to EXP003 (**same acquisition —
the analysis differs**)

| Step | Action | Observe | Record |
|---|---|---|---|
| 1 | Reference `K_P=6, K_d=4.8`, 2° step | — | both outputs |
| 2 | Compute `S(jω)` offline | — | **S1:** `M_S` (expect 2.794 dB ±0.5) |
| 3 | From the same data | — | `ω_SC` ≈ 3.63 rad/s |
| 4 | **S3:** watch the pendulum | displaced, then **returns to zero** | steady deflection? (expect none) |
| 5 | Plot `L(jω)` | — | **S2:** `min|1+L|` ≈ `1/M_S` |
| 6 | Design A `K_P=1.20, K_d=1.50` | — | `M_S` < 1 dB (predicted 0.995 — **tight**) |
| 7 | Design B `K_P=0.25, K_d=4.80` | **listen to the actuator** | `M_S` < 3 dB; note noise/harshness |

**Expected:** `M_S` 2.794 dB; Nyquist identity holds; pendulum returns to zero.
**Failure:** steady pendulum deflection → `G_pend(0) ≠ 0`, contradicting the model —
**record, do not tune around it.**
**MATLAB:** `exp004_run_analysis`
**Note:** Design B is nearly pure derivative (`T_d` = 19.2 s) — expect high effort and
noise. Tutorial 4 constrains neither.

---

# EXP005 — Tutorial 5 · Unstable MIMO (INVERTED) ⚠

> ## HIGHEST RISK. TWO PEOPLE. 137 ms FALL TIME CONSTANT.
> **Do not run on unverified timing (OI-10).**

**Prereq:** EXP004 complete; **OI-10 resolved** · **Inner gains fixed 300 / 0 / 30**
(**not 150**) · **rotor sign inversion active** · **Start:** pendulum held upright by hand,
12 V OFF, path clear for a **full rotation**

| Step | Action | Observe | Record |
|---|---|---|---|
| 1 | Dry run; tilt past 15° | **aborts**, reason `PENDULUM_LOST` | abort works |
| 2 | Confirm capture gate needs ±2° held 1 s | no command while waiting | gate works |
| 3 | **U1:** release from upright, **no control** | falls | time to pass 15° (expect ~0.4 s) |
| 4 | **12 V ON.** Hold upright; wait for capture; **release smoothly** | balances | balanced? |
| 5 | If not caught within ~1 s | — | **CUT POWER** |
| 6 | **U4:** command a 2° rotor step; **watch the first motion** | **arm moves the WRONG WAY first** | **undershoot % (expect ≈ −33 %)** |
| 7 | Compute margins offline | — | **U5:** `φ_M` 47.3° ±10°, `GM` 6.01 dB ±3, `M_S` 6.37 dB ±3 |
| 8 | **U6 — LAST:** `K_P=10, K_d=3.33` | pronounced ringing; may fall | balanced? behaviour |
| 9 | **U7:** compare System 1 vs 2 performance | — | which was better, on what measure |

**Expected:** balances; **visible reverse motion first** (the non-minimum-phase zero at
+7.29 rad/s); System 2 visibly closer to instability.
**Failure:** no reverse motion → plant model wrong. Growing oscillation → **cut 12 V**.
**U7 is an open question** — Tutorial 5 calls System 2 "improved performance"; the model
says 4× worse. **Record what you see; do not assume either reading.**
**MATLAB:** `exp005_run_analysis` · **Accept:** balances; margins within tolerance;
undershoot confirms the RHP zero

---

## The single most valuable observation in the whole sequence

**EXP005 Step 6.** The arm moving *away* from the commanded direction before reversing is
the non-minimum-phase zero made visible — the physical signature of the fact that
stabilising an unstable pole converts it into a right-half-plane zero. It is visible to the
naked eye and confirms the structure directly.

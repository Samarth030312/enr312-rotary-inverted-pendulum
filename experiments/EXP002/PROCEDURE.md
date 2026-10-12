> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP002/`.

# EXP002 — Hardware Procedure

**STATUS: NOT_EXECUTED.** `st-info --probe` → 0 programmers; no `/dev/ttyACM*`. Nothing
below has been performed. Flashing and all physical operation are operator-controlled.

**Prerequisite:** EXP001's hardware procedure must be complete first. EXP002 closes a loop
around the rotor; doing that with an unverified sign convention (open item **OI-2**) would
produce **positive feedback** and a violent divergence. Do not skip it.

---

## 0. Before power

- [ ] EXP001 procedure completed; `ENR312_ENCODER_POLARITY` and `ENR312_ROTOR_POLARITY`
      set from measurement, not placeholders.
- [ ] Swing path clear; arm free over its full ±240° travel.
- [ ] Pendulum **removed or clamped**. EXP002 is a rotor-only experiment; a free pendulum
      adds unmodelled dynamics to a measurement whose whole purpose is model comparison.
- [ ] Confirm gains to be tested and compute the predicted peak demand:

      u_peak = A · (K_P + K_d·α/T_s)

      For `K_P=5, K_d=2.5, α=0.11809, T_s=2 ms`: `u_peak = 152.61 · A`.
      With `A = 2°` → 305.2, inside the 400 limit. **If `u_peak` exceeds the limit,
      reduce `A` — do not raise the limit to make the number fit.**

## 1. Build

```bash
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"
cd firmware/enr312 && make test && make arm
```

Both must pass with zero warnings.

> **The EXP002 core is not yet a flashable application** — the board layer (TIM3 encoder
> init, L6474 SPI driver, step-clock ISR, telemetry UART) does not exist. Open item
> **OI-3**. Steps 2–5 cannot run until it does.

## 2. Dry run — `armed = false`

- [ ] 12 V supply **off**.
- [ ] Confirm the phase sequence: IDLE → REF_STEP → REF_SETTLE → DIST_STEP → DIST_SETTLE
      → DONE.
- [ ] Confirm `u` is computed and logged but no motion is commanded.
- [ ] Confirm `reference_deg` and `disturbance` are **never simultaneously non-zero**.

Do not proceed until the dry run completes cleanly.

## 3. Reference-step measurement → `T(s)`

1. Clear the path; power the 12 V supply on.
2. Run armed with the Tutorial 1 gains, `A = 2°`.
3. Capture the full REF_STEP phase (6 s).
4. Compute peak time, peak value, overshoot, settling (2 %).
5. **Q1 passes** if within ±10 % (peak time, settling) and ±5 pp (overshoot) of the model.

**Abort immediately if** the output diverges (sign error — cut power), the motor buzzes
or stalls, or the arm approaches its travel limit.

## 4. Load-disturbance measurement → `S_D(s)`

1. Continue into the DIST_STEP phase (`D` applied at the plant input, `R = 0`).
2. Capture the full 6 s.
3. **Q2 passes** if the steady-state offset equals `1/K_P` within ±5 %.

> Expect the response **not** to return to zero. That is correct. Measured against zero it
> never settles — the permanent offset is structural, not a fault.

## 5. Redesign and repeat

Repeat steps 3–4 with `K_P = 6.55, K_d = 4.0`. Recompute `u_peak = 2 × (6.55 + 4.0 ×
0.11809/0.002) = 485.4` — **this exceeds 400**, so either reduce `A` to 1.5° (364) or
raise the limit deliberately and record the change. Do not let it clip silently.

## 6. Shutdown

1. Command the rotor to 0°.
2. **12 V off first**, then USB.
3. Save telemetry to `data/raw/EXP002/EXP002_<YYYYMMDD>_<HHMM>_<git-rev>.csv`.
4. Write the metadata sidecar in `data/metadata/EXP002/`.
5. **Never edit a file in `data/raw/`.**

## 7. Analysis

```bash
python3 scripts/exp002_process_measurements.py data/raw/EXP002/EXP002_<...>.csv
```

Then complete `MEASUREMENTS.md` and `CONCLUSION.md`, and update `VALIDATION.md`.

---

## Abort criteria

| Trigger | Action |
|---|---|
| Output diverges instead of converging | **Cut 12 V.** Feedback sign is inverted (OI-2) |
| Sustained saturation | Firmware aborts automatically; reduce `A` |
| Rotor travel limit | Firmware aborts automatically |
| Motor buzzing, stalling, hot | **Cut 12 V immediately** |
| Anything unexpected | Cut power first, diagnose second |

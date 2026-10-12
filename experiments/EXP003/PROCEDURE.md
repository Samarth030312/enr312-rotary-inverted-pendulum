> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP003/`.

# EXP003 — Hardware Procedure

**STATUS: NOT_EXECUTED.** `st-info --probe` → 0 programmers. Flashing and physical
operation are operator-controlled. **Prerequisite: EXP001 and EXP002 hardware procedures
complete** — closing two loops with unverified sign conventions (OI-2) is worse than
closing one, because an inverted inner loop *anti-damps* a `Q = 27` resonance.

## 0. Before power

- [ ] Sign conventions from EXP001 set in firmware, not placeholders.
- [ ] **Pendulum FITTED and free to swing** (unlike EXP002, which removes it).
- [ ] **Suspended (hanging) configuration.** Not inverted — that is EXP005.
- [ ] Swing path clear; nobody within arm reach.
- [ ] Confirm gains. Inner is fixed at `K_P=10, K_I=0, K_d=5` — Tutorial 3 requires
      exactly these and the firmware hard-codes them.
- [ ] Peak demand check: `A·(K_P-Rotor + K_d-Rotor·α/T_s)`. Design 1 at 2° gives ≈579,
      inside the 800 limit. Recompute for each design.

## 1. Build

```bash
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"
cd firmware/enr312 && make test && make arm
```

> **Not yet flashable** — the board layer (TIM3 encoder, L6474 SPI, step ISR, telemetry
> UART) does not exist. Open item **OI-3**.

## 2. Dry run (`armed = false`)

- [ ] 12 V off. Confirm IDLE → ROTOR_STEP → SETTLE → DONE.
- [ ] Confirm zero commanded motion, and that CE metrics still accumulate (the dry run
      measures the *would-be* effort, which is useful).

## 3. R2 — single-loop drift (**do this first; it motivates everything else**)

1. Set `K_rotor = 0` so only the pendulum loop is active.
2. Power on. Disturb the pendulum by hand.
3. Observe rotor angle. **Expect unbounded drift** (Tutorial 3 Figure 3), while pendulum
   angle returns near zero.
4. Record the drift rate and direction.

**Abort if** the rotor approaches its travel limit — the firmware aborts automatically,
but keep a hand on the supply.

## 4. Design 1 — baseline

1. Set `K_P-Rotor = 6, T_d = 0.8` (`K_d = 4.8`).
2. Run armed with a 2° rotor step; capture the full 15 s excitation.
3. Record: settling (2 %), overshoot, `CE_Max`, `CE_Max_Power`, `CE_Total`.
4. **Quote `CE_Max` with the derivative filter corner used** — it is meaningless without it.

Expect **~31 % overshoot**, which already exceeds the 30 % limit applying from Step 2. That
is expected: Design 1 is a starting point, not a compliant design.

## 5. Step 2 / Design 2 — reduced effort

1. Set `K_P-Rotor = 1.5, T_d = 1.15` (`K_d = 1.725`).
2. Repeat step 4.
3. **Acceptance:** settling ≤ 4 s, overshoot ≤ 30 %, and a `CE_Total` reduction of **at
   least 2×** versus Design 1. Predicted 2.88×.

Tutorial 3 permits measured absolute values to disagree with simulation but requires the
**factor** to be observed.

## 6. Step 4 / Design 3 — low energy

1. Set `K_P-Rotor = 0.3, T_d = 2.5` (`K_d = 0.75`).
2. Repeat. **Acceptance:** settling < 10 s, overshoot < 30 %, `CE_Total` reduction ≥ 2×
   (predicted 6.59×).

Expect visibly sluggish motion. That is the point: this design trades speed for energy.

## 7. Shutdown

1. Rotor to 0°. **12 V off first**, then USB.
2. Save to `data/raw/EXP003/EXP003_<YYYYMMDD>_<HHMM>_<git-rev>.csv` with a metadata
   sidecar. **Never edit `data/raw/`.**

## 8. Analysis

```bash
python3 scripts/exp003_process_measurements.py data/raw/EXP003/EXP003_<...>.csv
```

Complete `MEASUREMENTS.md`, then `CONCLUSION.md` and `VALIDATION.md`.

## Abort criteria

| Trigger | Action |
|---|---|
| Pendulum oscillation **growing** | **Cut 12 V.** Inner loop sign inverted — it is anti-damping |
| Rotor diverges | Cut 12 V. Outer loop sign inverted |
| \|pendulum\| > 120° or \|rotor\| > 240° | Firmware aborts automatically |
| Sustained saturation | Firmware aborts; reduce step amplitude |
| Motor buzzing, stalling, hot | **Cut 12 V immediately** |

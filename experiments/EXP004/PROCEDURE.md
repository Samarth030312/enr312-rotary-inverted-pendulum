> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP004/`.

# EXP004 — Hardware Procedure

**STATUS: NOT_EXECUTED.** No ST-LINK, no serial device. Operator-controlled.
**Prerequisites:** EXP001–EXP003 hardware procedures complete.

## 0. Before power
- [ ] Sign conventions set from EXP001 measurement (OI-2).
- [ ] **Pendulum fitted, suspended (hanging).** Not inverted — that is EXP005.
- [ ] Inner gains fixed at `10 / 0 / 5` (Tutorial 4 §7 requires exactly these).
- [ ] Swing path clear.

## 1. Build
```bash
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"
cd firmware/enr312 && make test && make arm
```
> Not yet flashable — board layer missing (**OI-3**).

## 2. Dry run (`armed = false`)
Confirm the phase sequence and that **both** channels' metrics accumulate.

## 3. Reference design — `K_P = 6, K_d = 4.8`
1. Power on. Run armed with a 2° rotor step; capture the full excitation.
2. Record rotor settling, rotor overshoot, **pendulum peak excursion**, **pendulum settling**.
3. Compute `S(jω)` offline from the step response, then `M_S` and `ω_SC`.
4. **Acceptance (S1):** `M_S` within ±0.5 dB of 2.794 dB.

> Tutorial 4 measured 2.4 dB against a simulated 2.7 dB and called that close agreement.
> A 0.3 dB gap is the realistic expectation, not a failure.

## 4. S3 — pendulum returns to zero
Confirm the pendulum is displaced in transit and **returns to zero**, holding no steady
deflection. A steady deflection would mean `G_pend(0) ≠ 0`, contradicting the model —
record it rather than tuning around it.

## 5. Design A — `K_P = 1.20, K_d = 1.50` (Step 1, `M_S` < 1 dB)
Repeat. **Acceptance:** `M_S` < 1 dB (predicted 0.995 — a *tight* margin, so a small
model error will breach it; record the measured value either way), overshoot < 30 %,
rotor settling ≈ 4.5 s.

## 6. Design B — `K_P = 0.25, K_d = 4.80` (Step 2, `M_S` < 3 dB)
Repeat. **Acceptance:** `M_S` < 3 dB, overshoot < 30 %, settling ≈ 1.9 s.

> **Watch the actuator here.** `T_d = 19.2 s` makes this nearly a pure derivative
> controller; it has the same control effort as the reference and amplifies measurement
> noise. If the motor sounds harsh or the command looks noisy, stop and record it — that
> observation is the point of the cross-experiment finding.

## 7. Nyquist check (S2)
From the same data, plot `L(jω)` and confirm `min|1+L| ≈ 1/M_S`.

## 8. Shutdown and analysis
`data/raw/EXP004/EXP004_<YYYYMMDD>_<HHMM>_<git-rev>.csv` + metadata sidecar.
**Never edit `data/raw/`.** Then complete `MEASUREMENTS.md`.

## Abort criteria
| Trigger | Action |
|---|---|
| Pendulum oscillation growing | **Cut 12 V** — inner loop sign inverted |
| Rotor diverges | Cut 12 V — outer loop sign inverted |
| Limits exceeded | Firmware aborts automatically |
| Harsh actuator noise (esp. Design B) | Stop, record, reduce `K_d` |

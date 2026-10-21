> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results: [`results/reports/`](../../results/reports/); raw data in `data/raw/EXP005/`.

# EXP005 — Hardware Procedure

> ## ⚠ HIGHEST-RISK PROCEDURE IN THE LABORATORY
> The inverted pendulum falls with a **137 ms** time constant. There is no benign failure
> mode. **Two people**: one at the controls, one with a hand ready to catch the pendulum
> and clear of the swing path.

**STATUS: NOT_EXECUTED.** No ST-LINK, no serial device.
**Prerequisites: EXP001–EXP004 hardware procedures complete.** Do not shortcut this.

## 0. Before power — mandatory checks

- [ ] **EXP003 timing verified.** Open item **OI-10**: loop timing has never been
      measured. EXP005 is the first experiment where jittery or slow timing causes a
      **fall**, not a poor response. *Do not run EXP005 on unverified timing.*
- [ ] Sign conventions from EXP001 set in firmware (OI-2).
- [ ] **Inverted configuration**, pendulum free to swing through upright.
- [ ] Inner gains fixed at `300 / 0 / 30`. **Not 150** — see the source conflict in
      `FIRST_PRINCIPLES.md` §2.
- [ ] Rotor branch sign inversion active (`EXP005_ROTOR_SIGN = −1`).
- [ ] Swing path clear for a **full rotation** — assume it will fall.
- [ ] Second person present, hand clear but ready.
- [ ] Power switch within immediate reach of the operator.

## 1. Build
```bash
export PATH="$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin:$PATH"
cd firmware/enr312 && make test && make arm
```
> Not yet flashable — board layer missing (**OI-3**).

## 2. Dry run (`armed = false`) — do not skip

- [ ] 12 V **off**. Hold the pendulum upright by hand.
- [ ] Confirm the **capture gate** completes only when held within ±2° for 1 s.
- [ ] Confirm the sequence WAIT_CAPTURE → BALANCE → ROTOR_STEP → SETTLE → DONE.
- [ ] Tilt the pendulum past 15° and confirm **abort** with reason `PENDULUM_LOST`.
- [ ] Confirm zero commanded motion throughout.

**Do not arm until every one of these passes.**

## 3. First balance — Stable System 1 (`K_P=9, K_d=9`)

1. Clear the area. Second person in position.
2. Power on with the pendulum **held upright by hand**.
3. Wait for the capture gate to complete (±2° for 1 s), then **release smoothly** — do not
   push.
4. Observe. Expect balance with visible small corrections.
5. If it does not catch within ~1 s, **cut power**. Do not let it thrash.

**Abort immediately if:** oscillation grows; the arm runs toward a limit; the motor sounds
harsh; anything is unexpected.

## 4. U4 — the diagnostic observation (**do this deliberately**)

With balance established, command a 2° rotor step and **watch the arm's first motion**.

> **Expect it to move the WRONG WAY first** — away from the commanded direction — before
> reversing. That is the non-minimum-phase zero at +7.29 rad/s, visible to the naked eye.
> Physically the arm must get *under* the pendulum before it can carry it.

Record the undershoot magnitude. Predicted −33 % for System 1.

**If there is no reverse motion, the plant model is wrong.** Record it; do not tune around
it.

## 5. U5 — margins
From the step data, compute `φ_M`, `GM`, `M_S`, `ω_SC` offline.
**Acceptance:** within ±10° on `φ_M`, ±3 dB on `GM`/`M_S` of the model.

## 6. U6 — Quasi-Stable System 2 (`K_P=10, K_d=3.33`) — **run this LAST**

Predicted `φ_M` 17.5°, `M_S` 10.3 dB — poor margins by design.

> **Expect pronounced ringing and possible loss of balance.** This design exists to
> *demonstrate* inadequate margins. Be ready to catch the pendulum. Do not attempt to
> "rescue" it by adjusting gains mid-run.

Record whether it balances at all, and its qualitative behaviour.

## 7. U7 — the unresolved discrepancy
Tutorial 5 calls System 2 *"improved performance"*; the model says the opposite (11.7 s vs
2.75 s settling). **Record what you actually observe**, on both settling and any other
measure that seems relevant. This is an open question, not a check.

## 8. Designed systems
Repeat for System 1 design (`6.25 / 7.00`) and System 2 design (`0.50 / 10.75`).

> **Watch the System 2 design.** `T_d = 21.5 s` is almost purely derivative: expect high
> control effort and noise amplification. If the actuator sounds harsh, stop and record —
> Tutorial 5 imposes no effort or noise constraint, so this is a real gap in its objectives.

## 9. Shutdown
1. Lower the pendulum by hand to hanging **before** removing power, if it is still balanced.
2. **12 V off first**, then USB.
3. Save to `data/raw/EXP005/EXP005_<YYYYMMDD>_<HHMM>_<git-rev>.csv` + metadata sidecar.
4. **Never edit `data/raw/`.**

## Abort criteria — any one stops the run

| Trigger | Action |
|---|---|
| Pendulum beyond 15° | Firmware aborts and zeroes output automatically |
| Sustained >10° for 100 ms | Firmware aborts (warning band) |
| Oscillation **growing** | **Cut 12 V.** Sign error or inadequate margin |
| Arm toward travel limit | Firmware aborts; cut power if it does not |
| Sustained saturation 200 ms | Firmware aborts |
| Motor harsh, hot, or buzzing | **Cut 12 V immediately** |
| Anything unexpected | **Cut power first, diagnose second** |

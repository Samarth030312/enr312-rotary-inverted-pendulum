# Changelog

Firmware releases (`firmware/enr312/release/`). Each release image is built from a
clean tree and pinned by SHA-256 in `MANIFEST.txt`; MATLAB refuses to flash an
image whose hash does not match.

## 2.3.3 (2026-10-22): 500 Hz crash recorder
The 50 Hz stream shows one sample per 10 control ticks, too coarse to see how a push
or a fall develops (`results/reports/2026-10-21c_rig_session.md`, section 3).
**Not yet run on the rig.**
* The control interrupt keeps every tick of the last 2 s in RAM (16 kB,
  `src/enr312_crashrec.c`). Any run abort, or the new `k` key, freezes it 0.5 s
  later, and the main loop sends `K,BEGIN / k,… / K,END`. Control is unchanged.
* App: **PUSH MARK** logs a deliberate push in the run's events and asks for the record;
  every record is saved next to its run as `<run id>_500Hz_<n>.csv`.
* Host tests (ring order, wrap-around, trigger window, saturation) and an end-to-end
  emulator test (PUSH MARK → 1000 samples, −1.498…0.500 s, saved with the run).
* A declaration after a `case` label in `enr312_ctrl.c` is now in a block (strict C11).

## 2.3.2 (2026-10-22): swing-up robust to a wrong pendulum constant
From the identification of the 2026-10-21 data
(`matlab/identification/identify_pendulum_20261021.m`). The rig ran with ωg² 57.01, a
value derived from the Tutorial geometry, but it measures 47.6 (free decay) to 49.5
(92° swings). With ωg² set too high, the energy estimate is low near the bottom and the
pump overshoots the top. The learnt correction δ could not go below 0, so it could not
take the excess back. **On the rig (2026-10-21, 19:22 UTC), told the free-swing value
ωg² 48.5: caught at 3.88 s at the first try**, balanced 18.8 s, recovered from a
deliberate push of about 50 deg/s and fell to a larger one
(`results/reports/2026-10-21c_rig_session.md`).
* δ may go down to −0.3 in swing-up too (`CTRL_SW_DELTA_MIN`), as it already could for a
  pendulum target.
* Simulated on the identified pendulum (`matlab/experiments/PEND/swingup_versions_study.m`),
  with the firmware told 57.01: 2.2.0, 2.3.0 and 2.3.1 catch in part of the cases and
  2.3.2 in all of them. The model reproduces the rig's outcomes for 2.2.0 and 2.3.0.
* App: SWING UP offers the measured ωg² when the one in use differs by more than 8 %.
  A simulation in the app keeps the rig's 1 s host watchdog fed, so a run still active
  on the rig no longer stops while the app simulates.

## 2.3.1 (2026-10-21): a swing-up catch that works on the real pendulum
From the evening rig session (`results/reports/2026-10-21b_rig_session.md`): 2.3.0
caught one swing-up in three, after 39 s. The real pendulum passes the top at 75–120 deg/s
because the pivot has dry friction; the 60 deg/s catch rule almost never fired.
**Not yet run on the rig.**
* **Catch** at |α| ≤ 7° when slow (≤ 60 deg/s) **or** coming towards upright from 2–7°
  at ≤ 100 deg/s, and only if the LQR's first command is within 2× the arm's limit
  (a catch with the arm already moving fast cannot be stopped in time).
* A pass over the top lowers the learnt climb loss with gain 1.0 (was 0.5).
* The pendulum target (0 < amp < 179) starts with no learnt loss, so amp 0 really stops.
* Host plant and MATLAB simulation: stick-slip (Coulomb) pivot friction and an encoder
  offset. Simulated with friction 0.9–1.5 rad/s², offset 0.5° and ωg² 45–65: 7 of 7
  caught in 6–11 s in the host tests; 12 of 13 in the wider sweep. (Later
  identification put the friction at 0.48 rad/s² plus a speed-dependent loss. On that
  pendulum 2.3.1 catches in only half the cases; see 2.3.2.) Never flashed.

## 2.3.0 (2026-10-21): protocol 5, from the first rig swing-ups
Motivated by the rig session of 2026-10-21 (`results/reports/2026-10-21_rig_session.md`):
swing-up caught 3 of 3 on firmware 2.2.0, then lost to an external kick, a catch at
75 deg/s, and an arm held 23° off by a 0.6° upright offset. **Not yet run on the rig.**
* **Upright auto-trim** (HOLD): the mean α is learnt (τ 8 s) and controlled away, so the
  arm returns to its set-point (simulated 0.6° offset: arm −0.03° instead of 23°).
* **Gentler catch**: only at ≤ 60 deg/s; hold the arm where it caught 2 s, then walk home.
* **Kick tolerance**: upright HOLD aborts on saturation after 500 ms (sequences: 200 ms);
  the 15°, arm and speed bounds still guard.
* **Pendulum target `$amp`** (exp 24): 0 stops a swing, 0 < a < 179 swings to ±a
  (Åström–Furuta energy law), ≥ 179 swings up and balances; changeable live.
* Config echo: 26 values (amp appended).

## 2.2.0 (2026-10-21): protocol 4, swing-up, lab mode
**Not yet run on the rig**; verified in host tests (9 pendulum variants for the
swing-up), the rig emulator through the app, and the MATLAB simulation (identical
to the C code).
* **Swing-up (`$exp=24`)**: energy pumping from hanging, u = u_on·sat(10(2 + δ − E))·sign(ψ̇ cos ψ)
  with an arm-centring PD; δ, the energy the pivot friction drains on each climb, is
  learnt swing by swing, so the pendulum arrives at the top almost at rest; the
  4-state LQR catches it (|α| ≤ 7°, |α̇| ≤ 100 deg/s) and walks the arm home.
  Arm speed ceiling 720 deg/s for this experiment; timeout 40 s.
* **Lab mode (`$seq=0`)**: no tutorial sequence; hanging controllers regulate at once,
  upright ones go from release straight to HOLD; steps and holds come from `$ref`.
* `$wg2`: the pendulum constant (set it from the free-swing measurement).
* A pendulum at rest after a full turn (encoder 360°) is treated as hanging: the 120°
  hanging bound and the hanging controllers use the wrapped angle.
* LQR (exp 23) and swing-up use a 5 Hz pendulum-rate filter (10 Hz made the input
  chatter, u rms 212 vs 135 for the rig-proven T5 PID).
* The config echo `C,…` has 25 values (seq, wg2 appended) and is sent with
  Telemetry_Write: Printf's 192-byte buffer could truncate it.

## 2.1.0 (2026-10-21): protocol 3, Tutorials 6–10 and the PEND experiments
**Not yet run on the rig** (no working board); verified in host tests, the rig
emulator and the MATLAB simulation. 2.0.8 remains the last rig-verified release, and
Tutorials 1–5 behave identically in 2.1.0.
* New general controller core (`enr312_ctrl.c`): experiments 6 (PID, inverted),
  7 (pendulum-loop design, reference impulses), 8 (root locus, load disturbance
  60 deg/s²), 9 (state feedback, pole placement), 10 (LQR), 21 (stop a swing,
  regulate), 22 (on-off), 23 (4-state LQR balancing).
* Upright experiments balance 5 s after release before their sequence starts (the
  release transient takes ~3 s), then stay in HOLD until Stop run.
* Live set-point `$ref=deg` (slewed, `$rrate`), and live gain changes during a run.
* New `$` keys: ki fdr fdp k1–k4 bv imp uon db rrate div ma; the config echo `C,…`
  has 23 values (the first 9 unchanged).
* The `?` help repeats the firmware version line, so a host that connects after boot
  learns the protocol.
* Emulator (host build only): long output no longer overruns its 512-byte buffer.
* ELF SHA-256 `9a923608d7200cd79021c438094983b80346d361e001231f567b9743b3b23588`.

## 2.0.8 (2026-10-12)
* **Tutorial 5 waits for the operator to let go.** After capture the motor stays
  still until the pendulum moves 1.5° on its own; balancing starts only then.
  Before this, a pendulum still held after capture made the arm run away.
* Result on the rig: 4 of 4 Tutorial 5 runs balanced (0 of 3 before).
* ELF SHA-256 `78417888ddf615b6b300407c94c840b35c7dc0ef185fcb2ce411198b6ac50800`.

## 2.0.7 (2026-10-12)
* Encoder polarity set to −1. Measured on the rig: with +1, the hanging pendulum's
  first swing was opposite to the arm move in 8 of 8 moves.
* Rotor polarity +1 and the 8.889 microsteps/degree scale confirmed with a protractor.

## 2.0.6 (2026-10-12)
* Electrical self-test samples MISO with chip-select asserted. The L6474's output
  floats while CS is high, so the earlier test reported "floating" for a healthy chip.

## 2.0.5 (2026-10-12)
* **ARM fix.** The L6474 holds FLAG low after reset release. FLAG is now monitored
  only while the bridges can be energised, so ARM no longer faults itself.

## 2.0.4 (2026-10-12)
* `M`: electrical self-test of the driver's reset, MISO and FLAG lines.

## 2.0.3 (2026-10-12)
* `P`: scans the four chip-select / clock routings the shield allows, without
  energising the motor.

## 2.0.2 (2026-10-12)
* SPI chip-select timing for the L6474.
* `p`: SPI probe, SAFE state only.

## 2.0.1 (2026-10-12)
* Serial link at 115200 baud.
* The host verifies the configuration echo before GO.

## 2.0.0 (2026-10-11)
* Closed-loop Tutorials 2–5 run on the target, configured from the host (protocol 2).
* 1 s host watchdog.
* Interrupt-driven UART receive.

# Changelog

Firmware releases (`firmware/enr312/release/`). Each release image is built from a
clean tree and pinned by SHA-256 in `MANIFEST.txt`; MATLAB refuses to flash an
image whose hash does not match.

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

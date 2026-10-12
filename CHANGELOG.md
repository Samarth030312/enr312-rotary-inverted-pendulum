# Changelog

Firmware releases (`firmware/enr312/release/`). Each release image is built from a
clean tree and pinned by SHA-256 in `MANIFEST.txt`; MATLAB refuses to flash an
image whose hash does not match.

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

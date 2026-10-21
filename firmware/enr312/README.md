# ENR312 pendulum firmware

Bare-metal C for the NUCLEO-F401RE on the STEVAL-EDUKIT01 rig. No RTOS, no
dynamic allocation. Release 2.1.0 (protocol 3): 50 KB flash, 5.2 KB static RAM,
500 Hz control loop. Worst-case control interrupt measured on the rig with 2.0.8:
19–129 µs of the 2000 µs period; 2.1.0 has not run on the rig yet.

## Layout

```
inc/, src/        portable control code (no HAL, no CMSIS): compiles on the PC
  enr312_rig_config.h   every rig constant, each tagged with its source
  enr312_encoder        encoder unwrapping, polarity, velocity
  enr312_rotor          microstep accounting → arm angle
  enr312_pd             PD with a 10 Hz first-order derivative filter
  enr312_exp00N         one core per tutorial 1-5 (sequence, limits, aborts)
  enr312_ctrl           general core for Tutorials 6-10 and PEND: dual PID with
                        integral, state feedback, on-off, filters, live set-point
  enr312_metrics        step-response metrics on the target
  enr312_runner         u (deg/s²) → velocity → step rate, speed ceiling, run state
  enr312_cmd            '$' command parser
target/           STM32 application: clocks, GPIO, SPI1 L6474 driver, TIM3 encoder,
                  TIM2 step generator, TIM4 500 Hz loop, USART2, safety state machine
  enr312.ioc        pin/peripheral configuration (CubeMX), checked against the code
host/             PC-side plant model and the rig emulator
test/             host unit tests (389 checks)
cubemx/           CubeMX-generated init code from enr312.ioc, as a starting point
release/          committed, hash-pinned image that MATLAB flashes
```

Keeping the control logic free of hardware headers is what makes it testable:
every tutorial sequence, including its abort paths, runs in the unit tests and in
the emulator before it runs on the board, and the MATLAB simulation is checked
against exactly this code.

## Build

```bash
make -C firmware/enr312 test         # host unit tests (gcc)
make -C firmware/enr312 host-rig     # rig emulator
make -C firmware/enr312/target       # firmware image (arm-none-eabi-gcc 13.2.1)
make -C firmware/enr312/target isolation   # image contains no RTOS/middleware symbols
make -C firmware/enr312/target ioc-check   # enr312.ioc agrees with the init code
scripts/stm32/make_release.sh        # clean build → release/ + MANIFEST.txt
```

The portable code is compiled with `-Wall -Wextra -Wpedantic -Wshadow -Wconversion
-Wsign-conversion` and more, and must build without warnings.
The target build is reproducible (`-ffile-prefix-map`): CI checks that the source
produces exactly the committed flash image (`.bin`). The `.elf` hash also depends
on where the toolchain is installed, through its debug information.

## Flashing

From MATLAB (`enr312_lab` → *Flash firmware*, or `odyssix.stm32.flash()`), or:

```bash
make -C firmware/enr312/target flash   # your local build, via STM32_Programmer_CLI (no hash gate)
```

The board boots into SAFE: the L6474 is held in reset and the motor cannot move
until the host sends ARM and START.

## Sign conventions (measured)

`ENR312_ENCODER_POLARITY = −1`, `ENR312_ROTOR_POLARITY = +1`, 8.889 microsteps per
degree, all measured on the rig on 2026-10-12 (see
[`docs/TROUBLESHOOTING.md`](../../docs/TROUBLESHOOTING.md#signs-scales-and-datums)).
A wrong encoder sign turns negative feedback into positive feedback, so the same
constants live in `matlab/+odyssix/rigParams.m` and
`shared/parameters/edukit01_rig.yaml`, and `exp001_check_parameter_consistency`
fails if they disagree.

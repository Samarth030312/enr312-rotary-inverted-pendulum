# Getting started

The exact tool versions this repository was built and tested with, on Ubuntu
22.04.5 LTS. For installing on **Windows, macOS or Linux**, start with the
[install guide](INSTALL.md): one line in MATLAB, then only what your task needs.

## 1. What you need

### Software (versions actually used)

| Tool | Version used | Needed for |
|---|---|---|
| Ubuntu | 22.04.5 LTS (kernel 6.8) | everything below |
| MATLAB | R2026a Update 5 (26.1.0.3346908), **no toolboxes** | lab app, simulation, tests |
| STM32CubeIDE | 1.17.0 (installed under `/opt/st/stm32cubeide_1.17.0`) | provides `STM32_Programmer_CLI` v2.18.0 for flashing; the IDE itself is not required |
| Arm GNU Toolchain | 13.2.Rel1 (`arm-none-eabi-gcc` 13.2.1 20231009) | only to rebuild the firmware |
| GNU Make | 4.3 | firmware build, host tests, emulator |
| GCC (host) | 11.4.0 | host unit tests and the rig emulator |
| STM32F4 HAL driver | 1.8.5 (vendored in `Drivers/`) | firmware build |
| Python | 3.10 with matplotlib (optional) | the design scripts in `scripts/` |
| git | any recent | release script records the source revision |

Older MATLAB releases were not tried. The app uses `uifigure`, `uigridlayout`
and `serialport`, so R2020b is a realistic lower bound, but this is untested.

### Hardware

ST **STEVAL-EDUKIT01** kit: NUCLEO-F401RE, X-NUCLEO-IHM01A1 (L6474 stepper
driver), NEMA-17 stepper, LPD3806-600BM-G5-24C encoder (600 PPR), 12 V / 1 A
supply, and a USB cable that carries data (some are charge-only).

## 2. Install (Ubuntu 22.04)

```bash
# host compiler and make (unit tests, emulator)
sudo apt install build-essential git

# serial port access without sudo (log out and in afterwards)
sudo usermod -aG dialout "$USER"

# Arm GNU Toolchain 13.2.Rel1 (only to rebuild firmware); unpack under ~/.local
wget https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
tar -xf arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz -C ~/.local
```

* **STM32CubeIDE 1.17.0** from st.com (free account required). Install it to the
  default `/opt/st/`; MATLAB finds the bundled programmer there automatically.
  Installing STM32CubeProgrammer instead also works.
* **MATLAB**: the base product is enough.

The scripts look for the toolchain in `~/.local/arm-gnu-toolchain-*/bin` or on
`PATH`; override with `ARM_GCC_BIN=/path/to/bin`. The programmer can be forced
with `ODYSSIX_STM32_PROGRAMMER=/path/to/STM32_Programmer_CLI`.

## 3. Check the software (no hardware needed)

```bash
make -C firmware/enr312 test          # host unit tests (C), a few seconds
make -C firmware/enr312/target        # firmware image, needs the ARM toolchain
scripts/flash_ready_check.sh --quick  # everything except the real-time MATLAB tests
scripts/flash_ready_check.sh          # full check, about 10 minutes
```

The last line must read `SOFTWARE FLASH READY: YES`.

## 4. Run the lab

```matlab
addpath(genpath('matlab'))
enr312_lab
```

* **Without a rig:** pick a mission (T1–T10 or LAB), change a number, press
  **PLAY SIMULATION**. **CONNECT** offers the emulator: the firmware's own control
  code on the PC behind the real serial protocol.
* **With a rig:** wire and check it first ([`hardware/ENR312_WIRING.md`](hardware/ENR312_WIRING.md) §4),
  flash with `odyssix.stm32.flash()`, then **CONNECT**. The whole path from an empty
  bench is [`REPLICATE.md`](REPLICATE.md); the session guide for students is
  [`STUDENT_QUICKSTART.md`](STUDENT_QUICKSTART.md).

## macOS and Windows

See the [install guide](INSTALL.md). What remains Linux-only in the code:

* the rig emulator, which needs a POSIX pseudo-terminal (it also runs on macOS,
  not on Windows);
* `scripts/*.sh`, which use GNU coreutils (run them from WSL or Git Bash on
  Windows; on macOS, `sha256sum` is `shasum -a 256`);
* reading `/sys/bus/usb` in `odyssix.stm32.listBoards`, used only to explain an
  ST-LINK whose USB set-up failed. On Windows the ST-LINK's COM port is found
  through the device list, and on macOS by its `/dev/cu.usbmodem*` name.

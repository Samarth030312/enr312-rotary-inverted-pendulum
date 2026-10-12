# Getting started

> **Tested platform: Ubuntu 22.04.5 LTS, x86-64, only.** Every command, path and
> result in this repository comes from that machine. The MATLAB code contains
> search paths for Windows and macOS (see [below](#macos-and-windows)), but none of
> it has been run there. Treat those sections as a starting point, not as tested
> instructions.

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

* **Without a rig:** choose a tutorial (T1–T5), move the sliders, press
  *Simulate*. *Use emulator* runs the firmware's control code on the PC behind the
  real serial protocol.
* **With a rig:** wire and check it first ([`hardware/ENR312_WIRING.md`](hardware/ENR312_WIRING.md) §4),
  then *Detect board → Flash firmware → Connect*. The step-by-step session guide
  for students is [`STUDENT_QUICKSTART.md`](STUDENT_QUICKSTART.md).

## macOS and Windows

**Untested.** What should and should not work, from reading the code:

| Part | Linux (tested) | macOS (untested) | Windows (untested) |
|---|---|---|---|
| Simulation, lab app in sim mode | yes | should work: pure MATLAB | should work: pure MATLAB |
| Flashing from MATLAB | yes | searched: `/Applications/STM32CubeIDE.app/…/STM32_Programmer_CLI`, CubeProgrammer app bundle | searched: `C:\ST\STM32CubeIDE_*\…\STM32_Programmer_CLI.exe`, `C:\Program Files\STMicroelectronics\…` |
| Serial link to the board | `/dev/ttyACM0`, ST-LINK found via `/dev/serial/by-id` | `/dev/cu.usbmodem*` from `serialportlist`; pick it in the port list | `COMn` from `serialportlist`; install the ST-LINK driver (ST package STSW-LINK009) first |
| Rig emulator | yes (pseudo-terminal) | should work (POSIX pty, needs Xcode command-line tools for `gcc`/`make`) | **not supported**: uses a POSIX pseudo-terminal and `kill`; WSL processes are not reachable from Windows MATLAB as a serial port |
| Rebuilding firmware | yes | Arm toolchain for macOS + `make` | Arm toolchain for Windows + a `make` (e.g. from MSYS2); the Makefiles use POSIX shell syntax, so run them from MSYS2 or WSL |
| `scripts/*.sh` | yes | bash 3.2 ships with macOS; `sha256sum` is `shasum -a 256` there, so the release script needs a small change | run from WSL or Git Bash |

Known Linux-only details in the code, if you port it:

* `odyssix.stm32.listBoards` uses `/dev/serial/by-id` and `readlink -f` to pick
  the ST-LINK port; elsewhere it falls back to all serial ports.
* It also reads `/sys/bus/usb` to detect an ST-LINK whose USB set-up failed.
* The apps start the emulator with `&` and stop it with `kill`.
* `scripts/stm32/make_release.sh` and `flash_ready_check.sh` use GNU coreutils.

If you get it running on another platform, the list above is where to start.

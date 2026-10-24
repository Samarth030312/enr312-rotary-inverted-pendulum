# Install on Windows, macOS or Linux

## The one line

Open MATLAB and paste this into the Command Window:

```matlab
gitclone("https://github.com/Samarth030312/wobble.git", Depth=1); cd wobble; setup open
```

That downloads the repository (about 35 MB) into the current folder, checks this
computer, prints what is missing, and opens the lab app. It is the same line on
Windows, macOS and Linux. You do not need git installed, because MATLAB has its own.

The simulator, the Simulink model and every recorded run need nothing else. The
rest of this page is for the parts that do: talking to the board, flashing it, and
rebuilding the firmware.

**Next time,** in MATLAB:

```matlab
cd wobble; setup open
```

Or run `setup save` once and type `enr312_lab` from anywhere after that.

**If `gitclone` is not found** (MATLAB older than R2023b), download the ZIP
(GitHub page → green **Code** button → **Download ZIP**), unzip it, `cd` into the
folder in MATLAB and run `setup open`.

## What `setup` checks

```
Wobble, the ENR312 rotary inverted pendulum: setup check
------------------------------------------------------------------------
  MATLAB                      ok      R2026a (26.1). Tested on R2026a; R2023b or newer recommended
  toolboxes                   ok      none needed (the LQR and the fits are written in base MATLAB)
  Simulink (optional)         ok      found: matlab/simulink/ will run
  simulation                  ok      runs (the firmware's control code, in MATLAB)
  STM32 programmer            ok      /opt/st/stm32cubeide_1.17.0/plugins/.../STM32_Programmer_CLI
  board                       ok      No ST-LINK detected. Plug the Nucleo in by USB.
  serial ports                ok      none now (plug the board in to see its port)
  serial permission           ok      you are in the dialout group
  emulator (optional)         ok      make and a C compiler found
  Arm compiler (optional)     ok      /home/.../arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin
------------------------------------------------------------------------
  Ready. Start the lab with:  enr312_lab
```

Every line marked `MISSING` comes with the fix. `setup` changes nothing on the
computer; it only adds the folder to the MATLAB path for the current session, or
for good with `setup save`.

## What you need, by task

| You want to … | You need | Windows | macOS | Linux |
|---|---|---|---|---|
| use the simulator, replay runs, answer the PEND questions | MATLAB (no toolboxes) | ✓ | ✓ | ✓ |
| run the Simulink model | Simulink | ✓ | ✓ | ✓ |
| connect to the rig | the board's USB port works | ST-LINK driver (comes with CubeProgrammer) | nothing | `dialout` group |
| flash the firmware | STM32CubeProgrammer (free) | ✓ | ✓ | ✓ |
| try the rig emulator (no board) | a C compiler and `make` | not supported | Xcode command-line tools | `build-essential` |
| run the firmware's C unit tests | a C compiler and `make` | MSYS2 (untested) | Xcode command-line tools | `build-essential` |
| rebuild the firmware | Arm GNU Toolchain 13.2.Rel1 and `make` | MSYS2 `make` (untested) | Xcode tools | `build-essential` |

You do not need STM32CubeIDE, Python, Docker, or any MATLAB toolbox. The release
firmware image is already in the repository (`firmware/enr312/release/`), checked by
its SHA-256 before every flash, so a C compiler is needed only to change the firmware.

## Computer

The lab needs no more than MATLAB itself. MathWorks' figures for the current
release ([requirements](https://www.mathworks.com/support/requirements/matlab-system-requirements.html)):

| | Windows | macOS | Linux |
|---|---|---|---|
| system | Windows 10 (22H2) or 11 | the three latest macOS releases | the distributions MathWorks lists; this repository was built on Ubuntu 22.04 |
| processor | any 64-bit Intel or AMD; 4 cores with AVX2 recommended. Snapdragon X runs MATLAB through emulation | Apple silicon (M-series). From R2026b MATLAB no longer runs on Intel Macs; an Intel Mac needs R2026a or older | any 64-bit Intel or AMD |
| memory | 8 GB minimum, 16 GB recommended | same | same |
| disk | 5–8 GB for a typical MATLAB install, more with Simulink; this repository 35 MB; a recorded rig run is about 60 kB | same | same |
| graphics | no GPU needed. A graphics card with WebGL 2.0 and 2 GB makes the app's 3-D view smoother | built in | same as Windows |
| screen | 1920 × 1080 or larger shows the full app. Below 1600 pixels wide the window and the fonts shrink to fit | same | same |
| USB | one USB-A port (or an adapter) and a **data** cable: some Mini-USB cables only charge | same | same |

For scale, on the laptop this was developed on (Intel i7-9750H, 24 GB, Ubuntu 22.04):
the whole Simulink study, about 70 simulations, took 7 minutes, and the full software check
(`scripts/flash_ready_check.sh`) about 10 minutes. Anything that runs MATLAB comfortably runs
this.

---

## Windows

### 1. MATLAB

Install MATLAB from your university licence. Tick **Simulink** in the installer if
you want the Simulink model. No toolbox is needed.

### 2. STM32CubeProgrammer, which brings the USB driver

1. Download **STM32CubeProgrammer** from st.com (search "STM32CubeProgrammer",
   product STM32CubeProg; a free ST account is asked for).
2. Run the installer with the defaults. When Windows asks to install the
   STMicroelectronics device drivers, say **Install**. This is the ST-LINK driver
   (ST's package STSW-LINK009).
3. Plug the Nucleo in. Device Manager should show
   **Ports (COM & LPT) → STMicroelectronics STLink Virtual COM Port (COMn)** and
   **Universal Serial Bus devices → ST-Link Debug**.

`setup` finds the programmer in its default folder
`C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin`, or inside
an STM32CubeIDE install under `C:\ST\`. If it is somewhere else:

```matlab
setenv('ODYSSIX_STM32_PROGRAMMER', 'D:\tools\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe')
```

### 3. Flash and run

```matlab
odyssix.stm32.flash()      % checks the image, the chip, then writes, verifies and resets
enr312_lab                 % CONNECT picks the ST-LINK's COM port
```

Without MATLAB, from a Command Prompt in the repository folder:

```bat
"C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe" -c port=SWD mode=UR -w firmware\enr312\release\enr312_pendulum.bin 0x08000000 -v -rst
```

### 4. Optional: C unit tests and firmware rebuild

Untested on Windows. Install [MSYS2](https://www.msys2.org), open
**MSYS2 UCRT64** and run:

```bash
pacman -S --needed make mingw-w64-ucrt-x86_64-gcc git
make -C firmware/enr312 test
```

To rebuild the firmware, install the **Arm GNU Toolchain 13.2.Rel1**
(`arm-gnu-toolchain-13.2.rel1-mingw-w64-i686-arm-none-eabi.exe` from
developer.arm.com), tick "Add path to environment variable", then
`make -C firmware/enr312/target` in the same MSYS2 window.

The rig emulator does not run on Windows: it needs a POSIX pseudo-terminal. The
simulator inside the app runs the same control code and covers the same ground.

### What has been seen on Windows

A Windows group cloned the repository with the line above. The app opened, found the
board on COM14 and connected. Flashing from MATLAB on Windows and the C tools have
not been run there yet.

---

## macOS

### 1. MATLAB

Install MATLAB for your Mac's processor (Apple silicon is native). Add Simulink if
you want the Simulink model.

### 2. STM32CubeProgrammer

Download the macOS version from st.com and install it with the defaults. macOS needs
no USB driver for the Nucleo. If macOS refuses to open the installer, open
**System Settings → Privacy & Security** and press **Open Anyway**.

`setup` looks for the programmer in
`/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/` and inside
`/Applications/STM32CubeIDE.app`.

### 3. Flash and run

```matlab
odyssix.stm32.flash()
enr312_lab                 % the board is /dev/cu.usbmodemXXXX
```

### 4. Optional: emulator, C unit tests, firmware rebuild

```bash
xcode-select --install                 # clang, make, git
make -C firmware/enr312 test           # unit tests
```

For the firmware, download the **Arm GNU Toolchain 13.2.Rel1** for macOS
(`.pkg`, arm64 or x86_64 to match the Mac). It installs under
`/Applications/ArmGNUToolchain/`, where `setup` finds it. Then
`make -C firmware/enr312/target`.

The release script `scripts/stm32/make_release.sh` uses `sha256sum`; on macOS that
is `shasum -a 256`. Nothing else in the build is Linux-specific.

### What has been seen on macOS

Nothing yet. The code paths above are written from ST's and Arm's documented install
folders. If something differs on your Mac, the fix is one path in
`matlab/+odyssix/+stm32/tools.m`.

---

## Linux (Ubuntu 22.04, where everything was built and tested)

```bash
sudo apt install build-essential git          # emulator, unit tests
sudo usermod -aG dialout "$USER"              # serial port without sudo; log out and in
```

Install **STM32CubeProgrammer** (or STM32CubeIDE) from st.com with the defaults. Its
installer offers the udev rules that let a normal user reach the ST-LINK. Then, in
MATLAB, `setup open`.

For firmware rebuilds:

```bash
wget https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
tar -xf arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz -C ~/.local
make -C firmware/enr312/target
scripts/flash_ready_check.sh          # the full check: must end SOFTWARE FLASH READY: YES
```

---

## When something does not work

| What you see | Why | Fix |
|---|---|---|
| `gitclone` is not found | MATLAB older than R2023b | download the ZIP (above) |
| `Unrecognized function or variable 'enr312_lab'` | the folder is not on the path | `cd` into the repository, run `setup` |
| the app connects, the status says **NO DATA** and "protocol 1" | the board runs another program (a CubeIDE project, a demo), not this firmware | flash this firmware: `odyssix.stm32.flash()` |
| **no COM port** on Windows | driver missing, or a charge-only cable | install STM32CubeProgrammer, try another cable, check Device Manager |
| the port is there but **Access denied / port in use** | another program has it open: CubeIDE's terminal, a serial monitor, a second MATLAB | close it, unplug, plug in |
| Linux: `Permission denied` on `/dev/ttyACM0` | not in the `dialout` group | `sudo usermod -aG dialout $USER`, log out and in |
| flash says **old ST-LINK firmware** or cannot connect | the ST-LINK on the Nucleo needs an update | STM32CubeProgrammer → **Firmware upgrade** (ST-LINK panel) → **Open in update mode** → **Upgrade**. Unplug, plug in |
| flash: **REFUSED: image lacks the ENR312 banner** | you pointed it at another image | flash the release: `odyssix.stm32.flash()` |
| LD1 (the ST-LINK light) is red, or green | red: USB is set up, no debugger session; green: the last programming session succeeded; blinking red/green: programming in progress (Nucleo-64 manual UM1724). Neither colour says whether this firmware is running | — |
| LD1 blinks red slowly and never settles | the PC never finished the USB set-up | another cable or port; on Linux see the `error -71` row |
| Linux: `can't set config #1, error -71` in `dmesg` | the ST-LINK chip on this Nucleo does not answer USB set-up | upgrade the ST-LINK firmware on another PC (row above); try another USB port, no hub |
| the emulator does not start | no C compiler or `make` (or Windows) | install them (above), or use the app's simulator |
| the app window does not fit | small screen | it shrinks below 1600 px; for best results use 1920 × 1080 |

More, from bring-up of the real rig: [troubleshooting](TROUBLESHOOTING.md).

## Then

- [Simulator guide](guide/README.md): every screen, mission by mission.
- [Simulink model and Assignment 3](SIMULINK.md): the model, how to run it, the five PEND questions.
- [Build the rig](REPLICATE.md): from an empty bench to a balancing pendulum.

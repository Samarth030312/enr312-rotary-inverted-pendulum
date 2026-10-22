# From an empty bench to a balancing pendulum

This page takes you from nothing to a pendulum balancing upright, using only this
repository. Each step says what to do, what you should see, and where the details are.
Plan for one afternoon. The steps that can hurt the hardware are marked ⚠.

## 1. Parts

| Part | Notes |
|---|---|
| ST **STEVAL-EDUKIT01** | includes the NUCLEO-F401RE, the X-NUCLEO-IHM01A1 stepper driver (L6474), a NEMA-17 stepper, a 600 PPR encoder (LPD3806-600BM-G5-24C), the pendulum and a 12 V / 1 A supply |
| USB-A to mini-USB cable | it must carry data; some cables only charge |
| 2 A slow-blow fuse and a switch | in the +12 V line; recommended, not in the kit |
| a multimeter | for the electrical check |
| a protractor | to check the first move |

You can also build it without the kit: any NEMA-17 rated around 12 V / 0.8 A and a
600 PPR open-collector quadrature encoder will do. The arm radius, pendulum length and
mass then change, so measure them and do the free swing (step 7) before you trust the
model.

## 2. Software

Tested only on Ubuntu 22.04.5. The exact versions are in
[GETTING_STARTED.md](GETTING_STARTED.md#1-what-you-need).

```bash
sudo apt install build-essential git
sudo usermod -aG dialout "$USER"          # serial port without sudo; log out and back in
git clone https://github.com/Samarth030312/enr312-rotary-inverted-pendulum.git
cd enr312-rotary-inverted-pendulum
make -C firmware/enr312 test              # C unit tests, a few seconds: must end in 0 failures
```

Then install:

- **STM32CubeProgrammer** or **STM32CubeIDE** (free from st.com), for the flashing tool.
- **MATLAB** with no toolboxes, for the lab app.

You do not need the Arm compiler. The firmware image is committed and pinned by its
SHA-256 in [`firmware/enr312/release/MANIFEST.txt`](../firmware/enr312/release/MANIFEST.txt).

## 3. Wiring ⚠

Follow [hardware/ENR312_WIRING.md](hardware/ENR312_WIRING.md) section 1. Two things
matter more than the rest:

1. **On the kit's 12 V supply, the black wire with the white stripe is +12 V.** Plain
   black is ground. Swapping them destroys the driver board.
2. **The encoder must not pull its outputs up to 5 V** on the Nucleo's 3.3 V pins.
   Measure it (check A3 in section 4 of the wiring page) before you connect it.

Then do the staged check in section 4 of the wiring page: nothing powered, then USB
only, then 12 V with the motor off. Each stage lists the expected reading and what to
do if it is wrong.

## 3b. Mechanics

The controller can only be as good as the mechanics. Check these once, with the power off.

| What | How | Why |
|---|---|---|
| Arm on the motor shaft | The M3 screw that holds the motor shaft in its flange (UM2717 step 8c) must sit on the shaft's flat, tight. With the motor holding (ARM), push the arm gently: arm and shaft move together or not at all. | a slipping arm is an arm jerk the firmware cannot see |
| Pendulum rod on the encoder shaft | The rod's M3 screw (UM2717 step 11), tight. Draw a pen line across rod and shaft and check that it stays aligned. | the encoder must see every motion of the rod |
| Base level | A spirit level on the base, in two directions. | a tilt δ shifts "upright" by δ·sin(arm angle − β) (Tutorial 12), so the balance point moves as the arm turns |
| Base held | Clamp it to the table, or at least use the four rubber pads (UM2717 step 5). | at full arm acceleration the base pushes back |
| Encoder cable | A loose loop from the arm hub, routed upward or away, never dragging on the base. | the arm sweeps ±100° in a swing-up |

## 4. Flash the firmware

From MATLAB (this checks the image hash and the chip first):

```matlab
addpath(genpath('matlab'))
odyssix.stm32.flash()
```

Without MATLAB:

```bash
sha256sum firmware/enr312/release/enr312_pendulum.bin      # must match MANIFEST.txt
STM32_Programmer_CLI -c port=SWD -w firmware/enr312/release/enr312_pendulum.bin 0x08000000 -v -rst
```

To rebuild the image yourself, install Arm GNU Toolchain 13.2.Rel1 and run
`make -C firmware/enr312/target`. The build is byte-reproducible, so your `.bin`
should have the same hash as the committed one (with the same compiler version).

## 5. First contact (motor off)

```matlab
enr312_lab
```

1. Press **CONNECT**. The top bar shows `RIG` and the state `SAFE`.
2. Let the pendulum hang still, then press **ZERO DATUMS**.
3. Turn the pendulum one full turn by hand and back. PENDULUM must read ±360° at the
   turn and 0° back at the bottom; that shows no counts are lost.

## 6. First move ⚠

T1 → **ARM**, **START**, **RUN**. The arm moves +5° and comes back. Check the 5° with
the protractor. Then check the encoder's sign: when the arm starts moving in +θ, the
hanging pendulum must first swing in +ψ. If yours swings the other way, change
`ENR312_ENCODER_POLARITY`
([TROUBLESHOOTING.md](TROUBLESHOOTING.md#the-pendulum-swings-the-wrong-way)).

The stop controls:

- **ABORT** (or the Esc or Space key) stops the motor at once.
- Pulling the 12 V plug always works.
- If MATLAB stops talking for 1 s, the firmware stops by itself.

## 7. Measure your pendulum

T1 → **FREE SWING · record 15 s**, with the motor off. Lift the pendulum 10–20° and let
it go. The app fits the period and the damping, and gives you ωg², the pendulum length
and its Q. Press **USE MEASURED PENDULUM**: from then on the simulation and the
swing-up use your pendulum instead of the textbook values.

Do not skip this step before a swing-up. The swing-up computes the pendulum's energy
from ωg². Our rig ran with the Tutorial's 57 while it really measures 48.0 ± 0.5, and
it caught one swing-up in three. Told the measured value, it caught at the first try
in 3.9 s
([evening report, section 1](../results/reports/2026-10-21b_rig_session.md)).

Our pivot also has dry friction, about 0.5 rad/s². A small swing dies within two
cycles, and the pendulum stops slightly off vertical. If yours does the same, that is
the pivot, not your wiring.

## 8. The tutorials, in order

Press **NEXT ›** in the app; it walks through T1 to T10. Each experiment has its own
page under [`experiments/`](../experiments/) with:

- the physics;
- the prediction;
- the procedure;
- what counts as a pass.

Every run is saved automatically under `data/` ([data/README.md](../data/README.md)).

## 9. Balance it ⚠

Upright runs need two people: one holds the pendulum up, the other keeps a hand on
ABORT. The order:

1. Zero the datums with the pendulum hanging.
2. Choose **T5** or **LAB → UPRIGHT → LQR**, then ARM, START, RUN.
3. Hold the pendulum upright and still. After 1 s within ±2° the app beeps and says
   **LET GO NOW**.

Or let it swing itself up: **LAB → HANGING → Energy**, PENDULUM **180°**, **SWING**.
Before you press SWING, clear a half turn of the arm's sweep either way and keep your
hands away from above the rig.

## When something is wrong

[TROUBLESHOOTING.md](TROUBLESHOOTING.md) lists every problem we met during bring-up,
its cause and its fix. The most common:

| Problem | Fix |
|---|---|
| The board is not found | Unplug the USB, wait 5 s, plug it back in, and close other serial programs. |
| ARM fails | The 12 V supply is not on. |
| FAULT 0x10 when a run starts, the pendulum reads e.g. 1439° | The datum was not zeroed; let it hang and press ZERO DATUMS. |

# ENR312 rotary pendulum lab: student quickstart

One MATLAB app runs all five tutorials, in simulation and on the real rig.

```matlab
cd <this repository>
addpath(genpath('matlab'))
enr312_lab
```

1. Choose a **Tutorial** and a **preset** (the Tutorial's own designs).
2. Move any slider. The simulation reruns in under a second, and the plots,
   metrics and margins update.
3. Press **▶ Simulate** to watch the rig move.
4. On the rig: **Connect**, let the pendulum hang still, **Zero datums**, **ARM**,
   **START**, then **▶ Run on rig**. (The app refuses to run unless the pendulum
   has read within 10° of its datum for half a second.) The same
   gains run on the board, and the measurement (blue) lands on top of the
   simulation (grey), scored with the same metrics.

**No rig on your desk?** Press *Use emulator*. It runs the firmware's own
control code on your PC, so everything behaves as on the board. Its data is
marked SYNTHETIC.

## What you can change

| Group | Sliders | What they are |
|---|---|---|
| Controller | Kp, Kd rotor (outer) | **your design** in Tutorials 2–5 |
| | Kp, Kd pendulum (inner) | supplied by Tutorials 3–5; change them to see why |
| | Rotor step, load disturbance D, actuator limit | the experiment's excitation and limits |
| Physics | Pendulum length L → ωg² | gravity term: a shorter pendulum falls faster |
| | Q | pivot damping |
| | Arm radius r → ωr² | how strongly the arm pushes the pendulum |
| | Nonlinear physics | untick to see the Tutorials' linear model |
| | Quantisation | untick to remove encoder and microstep steps (the rig cannot) |

The yellow box in the app lists what the model includes and what it leaves out.
Read it before trusting a number.

## The tutorials

| | Rig set-up | Try | Watch for |
|---|---|---|---|
| **1 Actuator & sensing** | pendulum hanging, free | +5°, +20° moves; free swing | the arm moves exactly N × 0.1125°; each start and stop **kicks** the pendulum; measure ωg² and Q with *Free swing*, then *Use measured* |
| **2 Sensitivity** | **pendulum removed or clamped** | raise Kp, then Kd | overshoot and settling; after the load step the arm **never returns to 0**: offset = D/Kp |
| **3 Control effort** | pendulum hanging | Designs 1 → 2 → 3 | effort falls at least 2× per design and the response slows; untick quantisation to see how much effort is chatter |
| **4 Sensitivity (MIMO)** | pendulum hanging | Reference, A, B | Nyquist: how close L comes to −1; M_S |
| **5 Inverted** | **two people**, path clear for a full turn | System 1, then System 2 | the arm moves the **wrong way first**; System 2's margins; the *Pendulum encoder sign wrong* lesson is in `exp005_lab` |

## Safety on the rig

* **ABORT** button, **Esc** or **Space** stop everything at once. Pulling the 12 V
  plug always works.
* ARM energises the motor (it holds; it does not move). START allows motion.
  Nothing moves until you press *Run on rig*.
* The firmware aborts by itself on: pendulum past 15° (Tutorial 5) or 120°
  (others), arm past 240°, actuator saturation, speed above 360°/s, a driver
  fault, or **MATLAB going silent for 1 s**.
* **Tutorial 5:** zero the datums with the pendulum hanging. Then one person
  holds the pendulum upright and still **before** *Run on rig* is pressed (the run
  aborts at once if the pendulum is more than 15° from upright, and the app
  refuses to start it). After 1 s within ±2° the app shows **LET GO NOW** and
  beeps: let go. The motor stays still until the pendulum moves 1.5° on its own
  (firmware 2.0.8), so holding on a little too long is harmless; balancing
  starts the moment it is free. The other person
  keeps a hand on ABORT. When you have seen enough, press **Stop run**: the
  rig keeps balancing until then.

## If the board is not found

*Detect board* says **"ST-LINK is on USB but not configured"**: unplug the Nucleo's
USB cable, wait 5 s, and plug it back in. Close any other program that uses the
serial port (Arduino IDE, another MATLAB app): two programs on one port corrupt
the data.

## Saving your data

*Save rig run* writes the measurement to `data/raw/EXP00N/` (read-only) with a
metadata file next to it. Fill in your name in it. Emulator runs go to
`matlab/data/synthetic/` and are never mixed with real data.

## Instructor: before the first session

1. `scripts/flash_ready_check.sh` must end in **SOFTWARE FLASH READY: YES**.
2. Wire and check the rig: `docs/hardware/ENR312_WIRING.md` §4 (checks A1–D2).
   ⚠ On the kit's 12 V supply, the **black wire with the white stripe is +12 V**.
3. `enr312_lab` → *Detect board* → *Flash firmware*. Then *Connect*, turn the
   pendulum one full turn by hand, and check that it reads 360°.
4. Tutorial 1 → *Run on rig*: check the +5° move with a protractor. If the arm
   moves 10°, conflict C-1 applies: tell the developer before any closed-loop
   run.
5. Tutorial 1 → *Free swing*, then *Use measured*: from then on the simulations
   use your rig's pendulum.

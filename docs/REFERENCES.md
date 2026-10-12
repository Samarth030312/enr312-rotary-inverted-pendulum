# References

None of the documents below are redistributed in this repository. Obtain them
from their publishers or from the course.

## Course

* **ENR312 Control Engineering Laboratory**, Ahmedabad University, Monsoon
  Semester 2026. Course outline and laboratory handout.
* W. J. Kaiser, *Edukit Rotary Inverted Pendulum* tutorial series (UCLA), used by
  the course. The experiments here follow:
  * Tutorial 1: *Introduction to Control System Design Tools and Performance
    Analysis with Digital Actuators* (EXP001)
  * Tutorial 2: *Performance Analysis by Sensitivity Function Measurement* (EXP002)
  * Tutorial 3: *Control of MIMO Systems and Control Effort, Suspended Mode* (EXP003)
  * Tutorial 4: *MIMO Sensitivity Function Performance* (EXP004)
  * Tutorial 5: *Multiple Output (MIMO) Unstable System Control* (EXP005)
* W. J. Kaiser, *Edukit Rotary Inverted Pendulum: An Open and Configurable System
  With Digital Motor Controller Technology*, Revision 2.0, 2021 (system manual).

Where a document here quotes a tutorial value (gains, plant parameters,
performance figures), the tutorial is named next to it. Values were taken from the
tutorials and checked, not copied blindly: for example, Tutorial 5 states both
Td = 0.5 s and Kd = Kp·Td = 30 for Kp = 300, which cannot both hold. The firmware
uses Kd = 30 and records why (`firmware/enr312/test/test_enr312_exp005.c`).

## Hardware

* STMicroelectronics, **UM2717** Rev 1, *Getting started with the evaluation kit
  for education on motor control and control systems* (STEVAL-EDUKIT01). Source of
  the wiring (Figure 15) and the supply polarity.
* STMicroelectronics, **UM1857**, *Getting started with the X-NUCLEO-IHM01A1 stepper
  motor driver expansion board* (chip-select / clock routing resistors, Tables 3–4),
  and the X-NUCLEO-IHM01A1 schematic.
* Relevant datasheets (not quoted directly here): STMicroelectronics **L6474**
  stepper driver, **STM32F401xD/xE** microcontroller. The Arduino-to-STM32 pin map in
  `hardware/ENR312_WIRING.md` follows the standard Nucleo-64 layout; ST UM1724 was not
  consulted (see the note on that page).

## Software

* UCLA Edukit reference firmware: <https://github.com/wjkaiser/Edukit_Rotary_Inverted_Pendulum_Project>
  (`scripts/clone_ucla_reference.sh` clones it into `docs/references/ucla-source/`,
  which is git-ignored). Used for comparison only; see ENGINEERING_STANDARDS §15.
* STMicroelectronics STM32CubeF4 (HAL 1.8.5, vendored under `Drivers/`), STM32CubeIDE 1.17.0,
  STM32CubeProgrammer 2.18.0.
* Arm GNU Toolchain 13.2.Rel1.

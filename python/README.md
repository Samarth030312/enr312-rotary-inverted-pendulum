# Python client (optional)

The rig is driven by the **C firmware** (`firmware/enr312/`) and used through
the **MATLAB lab app** (`matlab/apps/enr312_lab.m`). This folder is an optional
extra: a small Python client for the same serial protocol, for students who
prefer Python (the PEND handout uses Python). It contains no controller. Every
control law runs on the STM32, and nothing here is needed to build or run the
firmware or the MATLAB app.

| File | What it is |
|---|---|
| `enr312_rig.py` | `Rig` class: connect, ARM/START (explicit), configure an experiment (checked against the board's echo), go/stop, live set-point `set_ref`, live gains `set_live`, CSV export; `free_swing` and `recovery` for PEND A4, A5, A7 |
| `run_experiment.py` | command line: run one experiment and save a CSV, or record and analyse a free swing |
| `test_emulator.py` | tests against the rig emulator (the firmware's C code on the PC) |

Requirements: Python 3.8+, `pip install pyserial`.

```bash
# no board: build the emulator, run the tests (about 30 s, synthetic)
make -C firmware/enr312 host-rig
python3 python/test_emulator.py

# a board flashed with firmware 2.1.0 (protocol 3)
cd python
python3 run_experiment.py --port /dev/ttyACM0 --free-swing 15            # PEND A4
python3 run_experiment.py --port /dev/ttyACM0 --exp 21 --seconds 20 --ref 20@10
python3 run_experiment.py --port /dev/ttyACM0 --exp 9 --set k1=4 --set k2=0.8 --csv t9.csv
```

```python
from enr312_rig import Rig
with Rig("/dev/ttyACM0") as rig:        # closing (or an exception) sends ABORT
    rig.arm(); rig.start()              # the human decides; never implicit
    rig.configure(21, kdp=5)            # raises if the board does not echo exactly this
    rig.go()                            # a thread feeds the firmware's 1 s watchdog
    ...
    rig.set_ref(20)                     # hold the arm at 20 deg
    rig.stop(); rig.save_csv("p21.csv")
```

Safety is the same as in the MATLAB app. The human ARMs and STARTs. Ctrl-C
and `close()` send ABORT. While a run is active the client sends the
keep-alive `.` every 0.2 s, so if Python stops, the firmware stops the motor
within 1 s. Upright experiments (5, 6, 7, 8, 23) need two people, as in
Tutorial 5.

Experiments, parameters and sequences: `shared/experiment_contracts/` and
`firmware/enr312/inc/enr312_ctrl.h`. On Windows the port is `COM5` (etc.); the
emulator test needs Linux or macOS.

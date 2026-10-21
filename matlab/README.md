# MATLAB

Base MATLAB only (no toolboxes). Developed and tested on R2026a, Ubuntu 22.04.
All paths are derived from the repository root (`odyssix.repoRoot`), so the tree
can be cloned anywhere.

```matlab
addpath(genpath('matlab'))
enr312_lab        % the lab app: Tutorials 1-10 + PEND, simulation + rig + emulator
```

## Layout

| Folder | Contents |
|---|---|
| `apps/` | `enr312_lab` (main app), `enr312_rig` (rig bring-up: flash, connect, free swing), scripted demo tours |
| `+odyssix/+sim/` | `runTutorial` (line-by-line port of the firmware control path), `plant`, `defaults`, `metrics` |
| `+odyssix/+stm32/` | `tools`, `listBoards`, `flash`, `build`, `RigLink` (serial protocol), `emulatorBinary`, `sha256` |
| `+odyssix/` | `rigParams` (sign conventions and scales, checked against the C header), `repoRoot`, UI helpers |
| `models/` | pendulum parameters and equations of motion; per-tutorial linear models |
| `experiments/` | per-tutorial analysis scripts; `EXP005/exp005_lab` is a focused Tutorial 5 app |
| `identification/` | free-swing fit for ωg² and Q, and a simulator to test it |
| `validation/` | model validators, parameter-consistency check, physics validation |
| `tests/` | `test_sim_matches_firmware`, end-to-end tests of both apps against the emulator |
| `plotting/` | figure scripts, including `plot_rig_vs_sim` (rig data vs simulation) |
| `hardware/` | `enr312_live_view`: plot the telemetry stream from a script |

## Scripted use

```matlab
odyssix.stm32.listBoards()                     % ST-LINK probes and their serial ports
R = odyssix.stm32.flash();                     % flash the committed release image
L = odyssix.stm32.RigLink(); L.open('/dev/ttyACM0'); L.stream(true);
S = odyssix.sim.runTutorial(odyssix.sim.defaults(2), odyssix.sim.plant(2));
m = odyssix.sim.metrics(S, odyssix.sim.defaults(2));
```

How flashing, the serial link, the emulator and the simulation fit together:
[`docs/MATLAB_STM32_INTEGRATION.md`](../docs/MATLAB_STM32_INTEGRATION.md).

## Tests

```matlab
assert(rotary_pendulum_validate_physics())     % physics model, 14 checks
assert(test_sim_matches_firmware())            % MATLAB port == firmware C code
assert(e2e_lab_all_tutorials())                % lab app, all tutorials, sim + emulator
assert(e2e_rig_app_emulator())                 % rig app against the emulator
```

Data saved from the emulator is marked SYNTHETIC and goes to the git-ignored
`matlab/data/synthetic/`; rig data goes to `data/raw/` (read-only) with metadata.

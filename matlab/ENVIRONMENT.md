> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`docs/GETTING_STARTED.md`](../docs/GETTING_STARTED.md).

# MATLAB Environment — OdyssiX ENR312 Simulation Lab

> ## EXECUTION STATUS: NOTHING IN `matlab/` HAS EVER BEEN EXECUTED
>
> Verified on the development machine, 2026-08-19:
> ```
> $ which matlab     # not found
> $ which octave     # not found
> ```
> Every `.m` file here is `NOT_EXECUTED`. Their presence in Git is not evidence that
> they run, and no output of theirs appears anywhere in this repository.

---

## Expected MATLAB version

**R2019b or later.** Required for `arguments` blocks, `xline`/`yline`, `exportgraphics`
and `sgtitle`, all of which are used.

Octave: `arguments` blocks and `exportgraphics` are not supported by Octave. The ENR312
course materials supply separate `*_Octave.m` variants of their own tools; equivalent
Octave ports of *these* files have not been written.

## Required toolboxes

**None.** Base MATLAB only.

This is a deliberate design constraint, not an accident:

- `exp002_step_response.m` computes step responses from a **closed-form pole/residue
  expansion** rather than calling `step()` or `tf()`, so **Control System Toolbox is not
  required**.
- Transfer functions are carried as `[num den]` coefficient vectors, not `tf` objects.
- No Simulink model exists.
- No Symbolic Math, Optimization or System Identification toolbox is used.

**Do not add a toolbox dependency without recording it here and justifying it.** A
laboratory that cannot run on a bare MATLAB installation is one that fails on the
student machine that matters.

## Portability

No absolute path appears anywhere. Every path derives from `odyssix.repoRoot()`, which
locates the repository from the location of `matlab/+odyssix/repoRoot.m`. The tree can be
cloned or copied to any MATLAB workstation and will work unchanged.

Forbidden, and absent: `/home/odyssix/…`, `/home/samarth/…`, `C:\Users\…`.

## Directory structure

| Directory | Contents |
|---|---|
| `+odyssix/` | Shared package: `repoRoot`, `rigParams` |
| `models/` | Physical and control models (EXP001 sensing, EXP002 sensitivity) |
| `experiments/` | Per-experiment entry points; `experiments/EXP002/` |
| `validation/` | Self-checking validation with stated expected values |
| `plotting/` | Reusable plotting |
| `data/synthetic/` | **SYNTHETIC data only** — every file says so |
| `controllers/`, `identification/`, `utilities/` | Reserved; currently empty |

Note: this repository uses `plotting/` (not `plots/`) and `data/synthetic/` to avoid
creating a second competing structure alongside the one established for EXP001.

## Execution procedure

From the repository root on a MATLAB-capable workstation:

```matlab
addpath(genpath(fullfile(pwd, 'matlab')));

exp001_run_analysis      % EXP001: sensing/actuation chain
exp002_run_analysis      % EXP002: sensitivity functions
```

Each entry point:
1. runs its validation function, which **errors** if any check fails;
2. writes figures to `results/figures/EXP002_matlab_*.png`.

## Expected outputs

`exp002_validate_sensitivity_model` must report exactly:

| Check | Expected |
|---|---|
| `wn` | 2.2360680 |
| `zeta` | 0.5590170 |
| `SD_final` | 0.2000000 (= 1/K_P) |
| `T_zero` | −2.0000000 |
| `T_peak` | 1.2676 |
| `T_peak_time` | 1.055 s |
| `T_overshoot` | 26.76 % |
| `T_settling` | 3.239 s |
| `SD_peak` | 0.2241 |
| `SD_peak_time` | 1.694 s |
| `SD_overshoot` | 12.03 % |
| `SD_settling` | 2.617 s |
| `S_plus_T_equals_1` | 0 (identity holds at every sample) |
| `sel_zeta` | 0.7814616 |
| `sel_SD_final` | 0.1526718 |

## Independent corroboration already obtained

Because MATLAB is unavailable, the **same equations** were evaluated independently in
Python (`scripts/exp002_sensitivity_design.py`), which **has** been executed. Its results
are the source of the expected values above.

**This is corroboration of the mathematics, not a substitute for MATLAB execution.** The
Python script is not a port of the MATLAB code; it is an independent implementation of
the same derivation, which is why agreement between them is informative. The MATLAB
artifacts remain `NOT_EXECUTED` and the Python run does not change that.

Python results are always labelled `INDEPENDENT SOFTWARE NUMERICAL CHECK` and are never
presented as MATLAB output.

## Recording an execution

When these are first executed, record in the relevant `experiments/EXP00N/MEASUREMENTS.md`:

- operating system and version
- MATLAB version and release (`version`, `ver`)
- toolboxes actually used (expected: none beyond base)
- execution date
- repository revision (`git rev-parse --short HEAD`)
- the full validation output

Then change the status here and in the experiment's `VALIDATION.md` from `DEFERRED` to
`EXECUTED`, and to `VALIDATED` only once every check has passed.

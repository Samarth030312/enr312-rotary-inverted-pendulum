> **Historical record (pre-hardware, before 2026-10-12).** Kept because other
> documents and code comments cite it. Parts are superseded; the current
> reference is [`matlab/README.md`](README.md).

# EXP001 MATLAB Artifacts

> ## EXECUTION STATUS: DEFERRED — MATLAB EXECUTION ENVIRONMENT REQUIRED
>
> Verified on the development machine on 2026-08-19:
>
> ```
> $ which matlab     # not found
> $ which octave     # not found
> ```
>
> **None of the files below have ever been executed.** Their existence in Git is not
> evidence that they run, and is certainly not evidence of any result. No output of
> theirs appears anywhere in this repository.

---

## Files

| File | Purpose |
|---|---|
| `+odyssix/repoRoot.m` | Derives the repository root from the file's own location |
| `+odyssix/rigParams.m` | Parameter set `PS-EDUKIT01-v1` |
| `models/exp001_sensing_model.m` | Equations (5)–(14): resolution, quantisation, velocity noise |
| `models/exp001_step_rate_model.m` | Equations (2)–(3): step-rate quantisation |
| `validation/exp001_validate_sensing_model.m` | 20 self-checking assertions + Monte-Carlo |
| `validation/exp001_check_parameter_consistency.m` | Parses the C header; fails if firmware and MATLAB disagree |
| `plotting/exp001_plot_quantisation.m` | Sensing-chain figures |
| `plotting/exp001_plot_step_rate.m` | Step-rate figure |
| `experiments/exp001_run_analysis.m` | Top-level entry point |

## Portability

No absolute path appears anywhere. Every path is derived from
`odyssix.repoRoot()`, which locates the repository from the location of
`matlab/+odyssix/repoRoot.m`. The tree can be cloned or copied to any MATLAB
workstation and will work unchanged.

## Required toolboxes

**None.** EXP001 uses only base MATLAB — arithmetic, `randn`, and plotting. Control
System Toolbox is not needed because EXP001 has no plant model and no controller. If a
later experiment needs a toolbox, record it then, for that experiment only.

Language features used require **R2019b or later** (`arguments` blocks, `xline`/`yline`,
`exportgraphics`, `sgtitle`).

## Execution procedure

On a MATLAB-capable workstation, from the repository root:

```matlab
addpath(genpath(fullfile(pwd, 'matlab')));
exp001_run_analysis
```

Expected behaviour:

1. `exp001_check_parameter_consistency` parses
   `firmware/enr312/inc/enr312_rig_config.h` and confirms every shared constant matches
   `odyssix.rigParams()`. It **errors** on any mismatch.
2. `exp001_validate_sensing_model` runs 20 checks against hand-derived values from
   `FIRST_PRINCIPLES.md` plus a 2×10⁶-sample Monte-Carlo confirmation of equations (11)
   and (14). It **errors** if any check fails.
3. Three figures are written to `results/figures/EXP001_matlab_fig*.png`.

## Expected values

If the model is correct, the validation must report exactly these:

| Quantity | Expected |
|---|---|
| `counts_per_rev` | 2400 |
| `deg_per_count` | 0.15 |
| `rad_per_count` | 2.617993877991494×10⁻³ |
| `sigma_theta_rad` | 7.557497350975908×10⁻⁴ |
| `vel_granularity_rads` | 1.308996938995747 |
| `sigma_omega_rads` | 0.5343957625674435 |
| `alias_limit_rev_s` | 6826.666666666667 |
| `microsteps_per_rev` | 3200 |
| `rad_per_microstep` | 1.963495408493621×10⁻³ |
| `ref_encoder_angle_scale` | 6.666667 (matches UCLA reference) |
| `ref_stepper_steps_per_deg` | 8.888889 (matches UCLA reference) |
| `arr_at_1000Hz` | 81 |
| `factual_1000Hz` | 1000.3811 |
| `arr_at_10kHz` | 7 |
| `errpct_10kHz` | +2.5391 |
| `sigma_omega_10Hz_filtered` | 0.1358 |
| `mc_sigma_theta` | within 2 % of 7.5575×10⁻⁴ |
| `mc_sigma_omega` | within 2 % of 0.53440 |

## Independent corroboration already obtained

Because MATLAB is unavailable, the **same equations** were evaluated independently in
Python (`scripts/exp001_sensing_analysis.py`), which **has** been executed:

| Quantity | Analytic | Python Monte-Carlo | Ratio |
|---|---|---|---|
| σ_θ | 7.557497×10⁻⁴ rad | 7.555111×10⁻⁴ rad | 0.9997 |
| σ_ω | 0.534396 rad/s | 0.534222 rad/s | 0.9997 |

**This is corroboration of the mathematics, not a substitute for MATLAB execution.** The
MATLAB artifacts remain `NOT_EXECUTED` and the Python run does not change that. The
Python script is not a port of the MATLAB code; it is an independent implementation of
the same derivation, which is why the agreement is informative.

## On recording execution

When these are first executed, record in `experiments/EXP001/MEASUREMENTS.md`:

- operating system and version
- MATLAB version and release (`version`, `ver`)
- installed toolboxes actually used (expected: none beyond base)
- execution date
- repository revision (`git rev-parse --short HEAD`)
- the full validation output

Then change the status in this file and in `experiments/EXP001/VALIDATION.md` AC-11 from
`DEFERRED` to `EXECUTED`, and to `VALIDATED` only once every check has passed.

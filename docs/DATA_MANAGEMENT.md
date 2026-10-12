# Data Management

**Date:** 2026-08-20 · Applies to EXP001–EXP005.

> **Raw data is evidence. It is never edited, never overwritten, never deleted — including
> when the run failed.** A failed run is a result.

---

## 1. Three data classes — never mixed

| Class | Meaning | Location | Marking |
|---|---|---|---|
| **HARDWARE** | Measured on the physical rig | `data/raw/EXP00N/` | metadata `data_class: HARDWARE` |
| **SIMULATION** | Produced by a model | `results/`, `matlab/data/` | figure titles say `MODEL, not measured` |
| **SYNTHETIC** | Generated to exercise a pipeline | `data/processed/*_selftest_synthetic.csv`, `matlab/data/synthetic/` | filename contains `synthetic`; **git-ignored** |

**Currently: 0 HARDWARE files.** `find data/raw -name '*.csv'` → 0.

Synthetic artifacts are git-ignored deliberately — a synthetic file sitting beside real
evidence is exactly the confusion docs/ENGINEERING_STANDARDS.md §11 warns about, and they regenerate on demand.

---

## 2. Directory contract

```
data/
  raw/EXP00N/        IMMUTABLE hardware data + schema README
  processed/EXP00N/  derived; must name its source raw file
  metadata/EXP00N/   one YAML sidecar per raw file
  metadata/TEMPLATE.yaml
results/
  figures/           generated; each states its data source and class
  tables/            numerical results
```

All five experiments have all three directories.

---

## 3. Naming

```
EXP00N_<YYYYMMDD>_<HHMM>_<short-git-rev>.csv        raw
EXP00N_<YYYYMMDD>_<HHMM>_<short-git-rev>.yaml       metadata (same stem)
EXP00N_<...>_processed_<script-rev>.csv             processed
```

The git revision in the filename means a dataset can never be silently detached from the
firmware that produced it.

---

## 4. Metadata — mandatory fields

Template: `data/metadata/TEMPLATE.yaml`. A raw file without a **complete** sidecar is not
evidence, because it cannot be traced.

| Group | Fields |
|---|---|
| Identity | `experiment_id`, `experiment_version`, `raw_data_file`, `date`, `time_utc`, `operator`, `second_person` |
| Provenance | `firmware.commit`, `.short_commit`, **`.tag`**, **`.dirty`**, `.elf_sha256`, `.toolchain`, `.build_command` |
| Parameters | `parameter_set.id`, `.file`, `.physical_parameters_version`, `.any_value_measured` |
| Hardware | `rig`, `rig_confirmed_by_inspection`, `configuration`, part numbers, `psu_*`, `encoder_pull_up`, **`encoder_idle_high_v`**, `common_ground_confirmed` |
| Calibration | `encoder_counts_per_rev`, `encoder_polarity` + **prose**, `rotor_polarity`, `rotor_control_gain_steps_per_deg`, `rotor_gain_conflict_resolved` |
| Controller | both PID sets, `derivative_lowpass_hz`, `output_limit`, **`realisation`** |
| Acquisition | `sampling.*` incl. **`timing_verified`**, `excitation.*` incl. `predicted_u_peak`, **`saturated_samples`** |
| Outcome | `completed`, `abort_reason`, `anomalies`, `processing.script` + revision |
| Status | `execution_status`, `data_class` |

**`firmware.dirty` must be honest.** Data produced from an uncommitted tree is not
reproducible, and recording that is more useful than hiding it.

---

## 5. Units and conventions — recorded per dataset, not assumed

| Quantity | Unit | Convention |
|---|---|---|
| Angles in telemetry | **deg** | models use rad |
| `t_s` | s | **nominal** = `tick × Ts`; **not a timing measurement** |
| Encoder | counts | origin latched at start; **arbitrary until EXP002** |
| Rotor | microsteps / deg | **commanded, never measured** |
| `u` | plant-input units | rotor angular acceleration demand (OI-7 unverified) |
| Error | — | `e = reference − measurement` |
| Pendulum zero | — | **hanging** (EXP003/004) vs **upright** (EXP005) — *different datums* |

The sign conventions are `UNDETERMINED` until EXP001 measures them, so every sidecar
carries them explicitly rather than referring to a default.

---

## 6. Processing rules

1. Read from `data/raw/`; **never write there.**
2. Every processed file names its source raw file and the script revision.
3. Every figure states its dataset and class (`MEASURED` / `MODEL` / `SYNTHETIC`).
4. Analysis scripts **verify the CSV header exactly** and refuse to run on a mismatch
   rather than guessing at columns.
5. Re-processing must be reproducible from raw + script revision alone.

---

## 7. Failed runs

**Preserve them.** Assign the run ID, write the sidecar with
`execution_status: FAILED` and `outcome.anomalies`, diagnose, then **repeat under a new
run ID**. Never overwrite, never delete, never reuse an ID.

A dataset showing the pendulum falling is a genuine measurement of an unstable plant.

---

## 8. Current state

| | Count |
|---|---|
| HARDWARE datasets | **0** |
| SIMULATION figures | 13 |
| SYNTHETIC datasets (git-ignored) | 2 |
| Metadata sidecars | 0 (template ready) |
| Schemas defined | **5 / 5** |

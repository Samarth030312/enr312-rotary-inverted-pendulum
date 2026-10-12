# Experiment Recording Protocol

**Date:** 2026-08-20 · Applies to every physical run of EXP001–EXP005.

> **The repository must let another engineer reconstruct what happened from the record
> alone.** If it is not written down at the time, it did not happen.

---

## 1. Before the run — open the record first

1. Confirm a **clean tree**: `git status --porcelain` → empty. If not, commit or record
   `firmware.dirty: true`.
2. Capture provenance:
   ```bash
   git rev-parse HEAD; git rev-parse --short HEAD
   git describe --tags --exact-match 2>/dev/null || echo "(no tag)"
   sha256sum build/odyssix_stm32_core.elf
   ```
3. Allocate a **run ID**: `EXP00N_<YYYYMMDD>_<HHMM>_<short-rev>`.
4. Copy `data/metadata/TEMPLATE.yaml` → `data/metadata/EXP00N/<run-id>.yaml` and fill
   **everything knowable before powering on**.

**Do not start the run until the sidecar exists.** Metadata written afterwards is
reconstructed, not recorded.

---

## 2. During the run

Record contemporaneously, not from memory:

| Item | How |
|---|---|
| Wall-clock start/stop | into the sidecar |
| Physical starting state | pendulum position, arm index mark alignment |
| **Protractor readings** | into `experiments/EXP00N/MEASUREMENTS.md` — **no script can supply these** |
| Every anomaly | sound, heat, vibration, unexpected motion — time-stamped |
| Any deviation from procedure | what and why |
| Aborts | reason code, phase, pendulum angle at abort |

**Photograph** the wiring before first power-up, the index marks, and any anomaly.
**Video** is strongly advised for EXP005 — an inverted-mode fall takes ~137 ms and is not
reliably observable in real time.

Store media as `docs/experiments/EXP00N/media/<run-id>_<description>.{jpg,mp4}` and
reference it from the sidecar's `notes`.

---

## 3. Immediately after

1. Save telemetry to `data/raw/EXP00N/<run-id>.csv`. **Never edit it.**
2. Complete the sidecar: `execution_status`, `outcome.*`, `anomalies`, `data_class: HARDWARE`.
3. Make raw data read-only:
   ```bash
   chmod 444 data/raw/EXP00N/<run-id>.csv
   ```
4. Commit raw + metadata **before** any analysis, so the evidence is fixed before it is
   interpreted:
   ```bash
   git add data/raw/EXP00N/<run-id>.csv data/metadata/EXP00N/<run-id>.yaml
   git commit -m "data(exp00N): raw capture <run-id>"
   ```

---

## 4. Analysis

```bash
python3 scripts/exp00N_process_measurements.py data/raw/EXP00N/<run-id>.csv
```

Then complete `experiments/EXP00N/MEASUREMENTS.md`, update `VALIDATION.md` with the
measured outcome per acceptance criterion, and write `CONCLUSION.md`.

Only now may a category in `docs/EXPERIMENT_READINESS.md` change:

- `HARDWARE_TESTED: NO → YES` — **only** after the run physically happened.
- `EXPERIMENTALLY_VALIDATED: NO → YES` — **only** after measured data was compared against
  the stated acceptance criteria and passed.

**A run that happened but failed its criteria gives `HARDWARE_TESTED: YES` and
`EXPERIMENTALLY_VALIDATED: NO`.** That is a legitimate and useful state.

---

## 5. Failures

**Preserve everything.**

1. Keep the dataset. Set `execution_status: FAILED`.
2. Record what happened, when, and the abort reason.
3. Diagnose in `experiments/EXP00N/CONCLUSION.md` under "Failures encountered".
4. **Repeat under a new run ID.** Never reuse, never overwrite.

A failed run is often more informative than a successful one — a fall reveals real
dynamics, a lost step reveals a torque limit, a wrong sign reveals a wiring fact. Deleting
it destroys evidence.

---

## 6. Conclusion template

```markdown
## Run <run-id>
**Date/operator:** · **Firmware:** <short-rev> (<tag>) · **Config:** suspended|inverted|rotor-only
**Parameter set:** PS-EDUKIT01-v1 · **Class:** HARDWARE

### What was done
### What was observed          (measured values, with units and instrument)
### Predicted vs measured      (table; state the tolerance)
### Discrepancies              (do not explain away — record and diagnose)
### Anomalies
### Acceptance                 (per criterion: PASS / FAIL / NOT_EVALUABLE)
### Conclusion
### Next action
```

---

## 7. Rules

1. **Never edit raw data.**
2. **Never delete a failed run.**
3. **Never reuse a run ID.**
4. **Never record a value the run did not produce.**
5. **Never mark a category YES before the act.**
6. Record disagreement with the model as a *finding*, not an error to be tuned away.
7. If the procedure was deviated from, the deviation is part of the result.

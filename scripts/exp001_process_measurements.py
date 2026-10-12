#!/usr/bin/env python3
"""
EXP001 measured-data processing and acceptance evaluation.

Consumes a telemetry CSV produced by the EXP001 firmware sequencer
(ENR312_Exp001_CsvHeader / ENR312_Exp001_FormatCsv) and evaluates predictions
P1, P2b, P3 and P6 against their stated tolerances.

  python3 scripts/exp001_process_measurements.py data/raw/<run>.csv

STATUS: NO MEASURED DATA EXISTS. This script has been executed only against a
SYNTHETIC self-test (--selftest), which verifies the parser and the acceptance
logic, NOT the rig. Running it on synthetic data produces no experimental claim
and the output is labelled accordingly.

Raw data is never modified. Outputs go to data/processed/ and results/.
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
from pathlib import Path

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent

COUNTS_PER_REV = 2400
DEG_PER_COUNT = 360.0 / COUNTS_PER_REV
Q_RAD = 2.0 * math.pi / COUNTS_PER_REV
TS = 0.002

EXPECTED_COLUMNS = [
    "tick", "t_s", "phase", "rotor_cmd_microsteps", "rotor_cmd_deg",
    "encoder_counts", "pendulum_deg", "pendulum_vel_rad_s", "abort_reason",
]

PHASE_IDLE, PHASE_SENSE_ONLY, PHASE_STEP_P1, PHASE_RETURN_P3, PHASE_DONE, PHASE_ABORTED = range(6)

# Tolerances from experiments/EXP001/HYPOTHESIS.md.
TOL_P1_DEG = 1.8          # one full step
TOL_P3_DEG = 1.8
TOL_P2_COUNTS = 4


def load(path: Path) -> dict:
    with path.open() as fh:
        rdr = csv.DictReader(fh)
        if rdr.fieldnames != EXPECTED_COLUMNS:
            raise SystemExit(
                f"ERROR: column mismatch in {path}\n"
                f"  expected: {EXPECTED_COLUMNS}\n"
                f"  found:    {rdr.fieldnames}\n"
                "The firmware CSV header and this parser must agree; refusing to "
                "guess at column meanings."
            )
        rows = list(rdr)
    if not rows:
        raise SystemExit(f"ERROR: {path} contains no data rows.")

    return {
        c: np.array([float(r[c]) for r in rows],
                    dtype=np.int64 if c in ("tick", "phase", "rotor_cmd_microsteps",
                                            "encoder_counts", "abort_reason")
                    else float)
        for c in EXPECTED_COLUMNS
    }


def evaluate(d: dict, measured: bool) -> list[tuple[str, str, str]]:
    """Return (prediction, verdict, evidence) rows."""
    out: list[tuple[str, str, str]] = []
    verdict_suffix = "" if measured else " (SYNTHETIC — no experimental meaning)"

    # --- Run integrity -----------------------------------------------------
    aborted = int(d["abort_reason"][-1]) != 0
    out.append((
        "RUN", "ABORTED" if aborted else "COMPLETED",
        f"final phase={int(d['phase'][-1])}, abort_reason={int(d['abort_reason'][-1])}"
        + verdict_suffix,
    ))

    # --- P3: zero-net-motion return ---------------------------------------
    p3 = d["phase"] == PHASE_RETURN_P3
    if p3.any():
        # Probe the LAST sample of the whole run, not the last RETURN_P3 sample.
        # The firmware issues the closing goto(0) and advances to DONE in the
        # same tick, so the final RETURN_P3 record still carries the -90 deg
        # command. Reading that record would report a closure failure on a
        # perfectly closed run.
        cmd_end = int(d["rotor_cmd_microsteps"][-1])
        cmd_deg_end = cmd_end * 360.0 / 3200.0
        ok = abs(cmd_deg_end) <= TOL_P3_DEG
        out.append((
            "P3 commanded-position closure",
            "PASS" if ok else "FAIL",
            f"final commanded arm angle {cmd_deg_end:+.4f} deg "
            f"(tolerance +/-{TOL_P3_DEG} deg){verdict_suffix}",
        ))
        out.append((
            "P3 physical closure",
            "NOT_EVALUABLE",
            "The arm has NO position sensor. Physical closure must be read off a "
            "mechanical index mark by the operator and entered in MEASUREMENTS.md. "
            "Telemetry cannot answer this — that is precisely why P3 exists.",
        ))

    # --- P1: commanded setpoints actually visited --------------------------
    p1 = d["phase"] == PHASE_STEP_P1
    if p1.any():
        visited = sorted(set(np.round(d["rotor_cmd_deg"][p1], 4).tolist()))
        out.append((
            "P1 commanded setpoints",
            "OBSERVED",
            f"commanded arm angles visited: {visited} deg. Measured PHYSICAL "
            f"angles must be entered manually — no arm sensor exists.{verdict_suffix}",
        ))

    # --- P2b: sign consistency during the hand-rotation phase --------------
    so = d["phase"] == PHASE_SENSE_ONLY
    if so.any() and so.sum() > 2:
        c = d["encoder_counts"][so]
        dc = np.diff(c)
        moved = dc[dc != 0]
        if moved.size == 0:
            out.append(("P2b sign convention", "NO_DATA",
                        "encoder never moved during SENSE_ONLY — the operator must "
                        "rotate the pendulum by hand during this phase"))
        else:
            pos, neg = int((moved > 0).sum()), int((moved < 0).sum())
            total = float(np.sum(moved))
            out.append((
                "P2b sign convention",
                "OBSERVED",
                f"net {total:+.0f} counts ({total * DEG_PER_COUNT:+.2f} deg); "
                f"{pos} increasing / {neg} decreasing transitions. Compare against "
                f"the hand direction recorded in MEASUREMENTS.md.{verdict_suffix}",
            ))
            span = float(c.max() - c.min())
            out.append((
                "P2 resolution (counts per rev)",
                "OBSERVED",
                f"count span during SENSE_ONLY = {span:.0f} counts = "
                f"{span / COUNTS_PER_REV:.3f} rev at the assumed 2400 c/rev. "
                f"A deliberate one-revolution rotation should read "
                f"2400 +/-{TOL_P2_COUNTS}.{verdict_suffix}",
            ))

    # --- P6: velocity granularity -----------------------------------------
    v = d["pendulum_vel_rad_s"]
    nz = v[v != 0.0]
    if nz.size:
        k = nz / (Q_RAD / TS)
        max_dev = float(np.max(np.abs(k - np.round(k))))
        ok = max_dev < 1e-6
        out.append((
            "P6 velocity granularity",
            "PASS" if ok else "FAIL",
            f"max deviation from an integer multiple of q/Ts = {max_dev:.3e} "
            f"(should be ~0){verdict_suffix}",
        ))

    # --- Timing regularity (an EXP003 question, observed here) -------------
    dt = np.diff(d["t_s"])
    if dt.size:
        out.append((
            "Tick spacing (nominal)",
            "INFO",
            f"mean {np.mean(dt) * 1e3:.4f} ms, std {np.std(dt) * 1e3:.4f} ms. "
            "NOTE: t_s is computed as tick*Ts by the firmware, so this measures "
            "NOTHING about real timing. Real jitter requires an independent "
            "time source — that is EXP003.",
        ))

    return out


def plot(d: dict, stem: str, measured: bool) -> Path:
    tag = "MEASURED" if measured else "SYNTHETIC — NOT A MEASUREMENT"
    fig, ax = plt.subplots(3, 1, figsize=(11, 9), sharex=True)

    ax[0].plot(d["t_s"], d["rotor_cmd_deg"], lw=1.4)
    ax[0].set_ylabel("commanded arm\nangle [deg]")
    ax[0].grid(alpha=0.3)
    ax[0].set_title(f"EXP001 telemetry — {stem}   [{tag}]")

    ax[1].plot(d["t_s"], d["pendulum_deg"], lw=1.0, color="tab:orange")
    ax[1].axhline(+120, color="crimson", ls="--", lw=0.9)
    ax[1].axhline(-120, color="crimson", ls="--", lw=0.9)
    ax[1].set_ylabel("measured pendulum\nangle [deg]")
    ax[1].grid(alpha=0.3)

    ax[2].plot(d["t_s"], d["pendulum_vel_rad_s"], lw=0.7, color="tab:green")
    ax[2].set_ylabel("raw backward-diff\nvelocity [rad/s]")
    ax[2].set_xlabel("time [s]  (nominal, = tick * Ts)")
    ax[2].grid(alpha=0.3)

    # Shade the phases so the sequence is readable at a glance.
    names = {PHASE_IDLE: "idle", PHASE_SENSE_ONLY: "sense", PHASE_STEP_P1: "P1",
             PHASE_RETURN_P3: "P3", PHASE_DONE: "done", PHASE_ABORTED: "ABORT"}
    colors = {PHASE_IDLE: "0.9", PHASE_SENSE_ONLY: "#dbeafe",
              PHASE_STEP_P1: "#dcfce7", PHASE_RETURN_P3: "#fef3c7",
              PHASE_DONE: "0.95", PHASE_ABORTED: "#fecaca"}
    ph = d["phase"]
    edges = np.flatnonzero(np.diff(ph)) + 1
    for s, e in zip(np.r_[0, edges], np.r_[edges, len(ph)]):
        p = int(ph[s])
        for a in ax:
            a.axvspan(d["t_s"][s], d["t_s"][e - 1], color=colors.get(p, "white"),
                      alpha=0.55, zorder=0)
        ax[0].text((d["t_s"][s] + d["t_s"][e - 1]) / 2,
                   ax[0].get_ylim()[1] * 0.85, names.get(p, "?"),
                   ha="center", fontsize=8, color="0.35")

    fig.tight_layout()
    out = REPO / "results" / "figures" / f"EXP001_telemetry_{stem}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150)
    plt.close(fig)
    return out


def make_selftest_csv(path: Path) -> None:
    """Generate a synthetic run to exercise the parser and acceptance logic."""
    path.parent.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(7)
    rows, tick = [], 0
    counts = 0

    def emit(phase: int, cmd_us: int, n: int, hand_rate: float = 0.0) -> None:
        nonlocal tick, counts
        prev_rel = counts
        for _ in range(n):
            counts += int(rng.normal(hand_rate, 0.4))
            vel = (counts - prev_rel) * Q_RAD / TS
            prev_rel = counts
            rows.append([tick, tick * TS, phase, cmd_us, cmd_us * 360.0 / 3200.0,
                         counts, counts * DEG_PER_COUNT, vel, 0])
            tick += 1

    emit(PHASE_IDLE, 0, 500)
    emit(PHASE_SENSE_ONLY, 0, 2400, hand_rate=1.0)   # ~1 rev by hand
    emit(PHASE_SENSE_ONLY, 0, 2600, hand_rate=-0.92)
    for sp in (0, 400, 0, -800, 0):
        emit(PHASE_STEP_P1, sp, 500)
    for _ in range(10):
        for sp in (0, 800, 0, -800):
            emit(PHASE_RETURN_P3, sp, 250)
    emit(PHASE_DONE, 0, 10)

    with path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(EXPECTED_COLUMNS)
        w.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs="?", type=Path, help="telemetry CSV under data/raw/")
    ap.add_argument("--selftest", action="store_true",
                    help="generate and analyse synthetic data (no experimental claim)")
    args = ap.parse_args()

    if args.selftest:
        path = REPO / "data" / "processed" / "EXP001_selftest_synthetic.csv"
        make_selftest_csv(path)
        measured = False
        print("SELF-TEST MODE — synthetic data. This validates the PARSER and the")
        print("ACCEPTANCE LOGIC only. It says nothing whatever about the rig.\n")
    elif args.csv:
        path = args.csv
        measured = True
        if not path.exists():
            raise SystemExit(f"ERROR: {path} not found.")
    else:
        ap.print_help()
        print("\nNo measured EXP001 data exists in this repository yet.")
        print("Run with --selftest to exercise the pipeline.")
        return 2

    d = load(path)
    stem = path.stem
    print(f"Loaded {len(d['tick'])} samples from {path.relative_to(REPO)}")
    print(f"Duration (nominal): {d['t_s'][-1]:.3f} s\n")

    rows = evaluate(d, measured)
    width = max(len(r[0]) for r in rows)
    for name, verdict, evidence in rows:
        print(f"  {name:<{width}}  {verdict:<14} {evidence}")

    fig = plot(d, stem, measured)
    print(f"\n  wrote {fig.relative_to(REPO)}")

    if not measured:
        print("\n  REMINDER: SYNTHETIC. Not experimental evidence. "
              "EXP001 hardware status remains NOT_EXECUTED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
EXP002 measured-data processing and acceptance evaluation.

Consumes telemetry produced by the EXP002 firmware sequencer
(ENR312_Exp002_CsvHeader / ENR312_Exp002_FormatCsv), extracts the complementary
sensitivity and load-disturbance step responses, and evaluates them against the
Tutorial 2 design objectives.

  python3 scripts/exp002_process_measurements.py data/raw/EXP002/<run>.csv
  python3 scripts/exp002_process_measurements.py --selftest

STATUS: NO MEASURED DATA EXISTS. This has been executed only against a SYNTHETIC
self-test, which verifies the parser and the acceptance logic, NOT the rig.
Raw data is never modified.
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
TS = 0.002

COLUMNS = ["tick", "t_s", "phase", "reference_deg", "disturbance", "noise_deg",
           "error_deg", "u", "rotor_deg", "abort_reason"]

(PH_IDLE, PH_REF_STEP, PH_REF_SETTLE, PH_DIST_STEP, PH_DIST_SETTLE,
 PH_DONE, PH_ABORTED) = range(7)

SPEC = {"T": dict(peak_time=2.0, overshoot=30.0, settling=4.0),
        "SD": dict(peak_time=3.0, overshoot=15.0, settling=4.0)}


def load(path: Path) -> dict:
    with path.open() as fh:
        rdr = csv.DictReader(fh)
        if rdr.fieldnames != COLUMNS:
            raise SystemExit(
                f"ERROR: column mismatch in {path}\n  expected: {COLUMNS}\n"
                f"  found:    {rdr.fieldnames}\n"
                "Refusing to guess at column meanings.")
        rows = list(rdr)
    if not rows:
        raise SystemExit(f"ERROR: {path} contains no data rows.")
    return {c: np.array([float(r[c]) for r in rows]) for c in COLUMNS}


def metrics(t, y, yf, tol=0.02):
    """Peak/overshoot/settling relative to the response's OWN final value."""
    if abs(yf) < 1e-12:
        return None
    i = int(np.argmax(np.abs(y)))
    peak, tpk = float(y[i]), float(t[i] - t[0])
    os = 100.0 * (abs(peak) - abs(yf)) / abs(yf)
    outside = np.where(np.abs(y - yf) > tol * abs(yf))[0]
    settling = float(t[outside[-1]] - t[0]) if outside.size else 0.0
    never = bool(outside.size and outside[-1] >= y.size - 2)
    return dict(final=yf, peak=peak, peak_time=tpk, overshoot=os,
                settling=math.inf if never else settling)


def segment(d, phase):
    m = d["phase"] == phase
    return (d["t_s"][m], d["rotor_deg"][m]) if m.any() else (None, None)


def evaluate(d, measured: bool):
    out = []
    tag = "" if measured else "  (SYNTHETIC - no experimental meaning)"

    aborted = int(d["abort_reason"][-1]) != 0
    out.append(("RUN", "ABORTED" if aborted else "COMPLETED",
                f"final phase={int(d['phase'][-1])}, "
                f"abort_reason={int(d['abort_reason'][-1])}{tag}"))

    # --- Complementary sensitivity T(s), from the reference-step phase ------
    t, y = segment(d, PH_REF_STEP)
    if t is not None and t.size > 10:
        R = float(np.median(d["reference_deg"][d["phase"] == PH_REF_STEP]))
        yf = float(np.mean(y[-max(10, y.size // 10):]))
        m = metrics(t, y, yf)
        if m:
            ok = (m["peak_time"] <= SPEC["T"]["peak_time"] and
                  m["overshoot"] <= SPEC["T"]["overshoot"] and
                  m["settling"] <= SPEC["T"]["settling"])
            out.append(("T(s) reference tracking", "PASS" if ok else "FAIL",
                        f"R={R:.2f} deg, final={yf:.4f} deg, peak={m['peak']:.4f}, "
                        f"peak_time={m['peak_time']:.3f}s, OS={m['overshoot']:.2f}%, "
                        f"settle={m['settling']:.3f}s{tag}"))
            out.append(("  DC tracking ratio", "INFO",
                        f"final/R = {yf/R:.4f} (model predicts 1.0000 exactly, "
                        f"since T(0)=1)" if R else "R=0"))

    # --- Load-disturbance sensitivity SD(s) --------------------------------
    t, y = segment(d, PH_DIST_STEP)
    if t is not None and t.size > 10:
        yf = float(np.mean(y[-max(10, y.size // 10):]))
        m = metrics(t, y, yf)
        if m:
            ok = (m["peak_time"] <= SPEC["SD"]["peak_time"] and
                  m["overshoot"] <= SPEC["SD"]["overshoot"] and
                  m["settling"] <= SPEC["SD"]["settling"])
            out.append(("SD(s) disturbance rejection", "PASS" if ok else "FAIL",
                        f"final={yf:.4f}, peak={m['peak']:.4f}, "
                        f"peak_time={m['peak_time']:.3f}s, OS={m['overshoot']:.2f}%, "
                        f"settle={m['settling']:.3f}s{tag}"))
            out.append(("  steady-state offset", "INFO",
                        f"{yf:.4f}. Model predicts 1/Kp. NON-ZERO is CORRECT: a PD "
                        "controller has no integral action, so a constant load leaves "
                        "a permanent offset."))
            # The convention that matters.
            pk = max(abs(y.max()), abs(y.min()))
            never = np.any(np.abs(y[-10:]) > 0.02 * pk)
            out.append(("  settling measured vs ZERO", "INFO",
                        "NEVER settles - permanent offset (expected for PD; motivates "
                        "integral action, Tutorial 6)" if never
                        else "settles to zero - UNEXPECTED, implies integral action"))

    # --- Saturation --------------------------------------------------------
    sat = int(np.sum(np.abs(d["u"]) >= 399.999))
    out.append(("Saturation samples", "INFO",
                f"{sat} of {d['u'].size}. Non-zero means the measured response is of a "
                "NONLINEAR system and the sensitivity functions are not valid."))

    out.append(("Timing", "INFO",
                "t_s is computed by the firmware as tick*Ts. It measures NOTHING about "
                "real timing. Real jitter requires an independent time source - EXP003."))
    return out


def plot(d, stem, measured):
    tag = "MEASURED" if measured else "SYNTHETIC - NOT A MEASUREMENT"
    fig, ax = plt.subplots(3, 1, figsize=(11, 9), sharex=True)
    ax[0].plot(d["t_s"], d["reference_deg"], lw=1.4, label="R reference")
    ax[0].plot(d["t_s"], d["rotor_deg"], lw=1.4, label="Y rotor angle")
    ax[0].set_ylabel("angle [deg]"); ax[0].legend(); ax[0].grid(alpha=0.3)
    ax[0].set_title(f"EXP002 telemetry - {stem}   [{tag}]")

    ax[1].plot(d["t_s"], d["error_deg"], lw=1.0, color="tab:orange", label="e")
    ax[1].plot(d["t_s"], d["disturbance"], lw=1.2, color="tab:red", label="D")
    ax[1].set_ylabel("error [deg] / D"); ax[1].legend(); ax[1].grid(alpha=0.3)

    ax[2].plot(d["t_s"], d["u"], lw=0.8, color="tab:green")
    ax[2].set_ylabel("U plant input"); ax[2].set_xlabel("time [s] (nominal)")
    ax[2].grid(alpha=0.3)

    names = {PH_IDLE: "idle", PH_REF_STEP: "R step", PH_REF_SETTLE: "settle",
             PH_DIST_STEP: "D step", PH_DIST_SETTLE: "settle", PH_DONE: "done",
             PH_ABORTED: "ABORT"}
    colors = {PH_IDLE: "0.92", PH_REF_STEP: "#dcfce7", PH_REF_SETTLE: "0.95",
              PH_DIST_STEP: "#fef3c7", PH_DIST_SETTLE: "0.95", PH_DONE: "0.97",
              PH_ABORTED: "#fecaca"}
    ph = d["phase"]
    edges = np.flatnonzero(np.diff(ph)) + 1
    for s, e in zip(np.r_[0, edges], np.r_[edges, len(ph)]):
        p = int(ph[s])
        for a in ax:
            a.axvspan(d["t_s"][s], d["t_s"][e - 1], color=colors.get(p, "white"),
                      alpha=0.55, zorder=0)
        ax[0].text((d["t_s"][s] + d["t_s"][e - 1]) / 2, ax[0].get_ylim()[1] * 0.88,
                   names.get(p, "?"), ha="center", fontsize=8, color="0.35")

    fig.tight_layout()
    out = REPO / "results" / "figures" / f"EXP002_telemetry_{stem}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150)
    plt.close(fig)
    return out


def make_selftest(path: Path, kp=5.0, kd=2.5):
    """Synthetic run: closed loop of the PD on a discrete 1/s^2 plant."""
    path.parent.mkdir(parents=True, exist_ok=True)
    a = 1.0 - math.exp(-2 * math.pi * 10.0 * TS)
    y = v = ds = prev_e = 0.0
    have_prev = False
    rows, tick = [], 0

    def phase_of(k):
        if k < 500: return PH_IDLE, 0.0, 0.0
        if k < 3500: return PH_REF_STEP, 2.0, 0.0
        if k < 5000: return PH_REF_SETTLE, 0.0, 0.0
        if k < 8000: return PH_DIST_STEP, 0.0, 1.0
        if k < 9500: return PH_DIST_SETTLE, 0.0, 0.0
        return PH_DONE, 0.0, 0.0

    for k in range(9600):
        ph, R, D = phase_of(k)
        e = R - y
        raw = (e - prev_e) / TS if have_prev else 0.0
        ds += a * (raw - ds)
        u_unsat = kp * e + kd * ds
        u = max(-400.0, min(400.0, u_unsat)) + D
        rows.append([tick, tick * TS, ph, R, D, 0.0, e, u, y, 0])
        y += TS * v + 0.5 * TS * TS * u
        v += TS * u
        prev_e, have_prev, tick = e, True, tick + 1

    with path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(COLUMNS)
        w.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv", nargs="?", type=Path)
    ap.add_argument("--selftest", action="store_true",
                    help="generate and analyse synthetic data (no experimental claim)")
    args = ap.parse_args()

    if args.selftest:
        path = REPO / "data" / "processed" / "EXP002_selftest_synthetic.csv"
        make_selftest(path)
        measured = False
        print("SELF-TEST MODE - synthetic data from a closed-loop model of the")
        print("PD controller on a discrete 1/s^2 plant. This validates the PARSER and")
        print("the ACCEPTANCE LOGIC only. It says nothing whatever about the rig.\n")
    elif args.csv:
        path, measured = args.csv, True
        if not path.exists():
            raise SystemExit(f"ERROR: {path} not found.")
    else:
        ap.print_help()
        print("\nNo measured EXP002 data exists. Run with --selftest.")
        return 2

    d = load(path)
    print(f"Loaded {len(d['tick'])} samples from {path.relative_to(REPO)}")
    print(f"Duration (nominal): {d['t_s'][-1]:.3f} s\n")

    rows = evaluate(d, measured)
    w = max(len(r[0]) for r in rows)
    for name, verdict, ev in rows:
        print(f"  {name:<{w}}  {verdict:<10} {ev}")

    fig = plot(d, path.stem, measured)
    print(f"\n  wrote {fig.relative_to(REPO)}")
    if not measured:
        print("\n  REMINDER: SYNTHETIC. Not experimental evidence. "
              "EXP002 hardware status remains NOT_EXECUTED.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

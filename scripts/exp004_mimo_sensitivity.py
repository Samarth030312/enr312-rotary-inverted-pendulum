#!/usr/bin/env python3
"""
EXP004 (Tutorial 4) -- MIMO Performance Analysis with Sensitivity Functions.

INDEPENDENT SOFTWARE NUMERICAL CHECK.
================================================================================
NOT MATLAB. MATLAB and Octave are both absent (verified). Tutorial 4 uses
Edukit_Single_Rotor_PID_Suspended_Mode_Design.m and
Edukit_Stability_and_Sensitivity_Function_Computation_Matlab.m. Those problems
are fully specified, so they are solved here independently. MATLAB equivalents
exist under matlab/ and are NOT_EXECUTED.
================================================================================

WHAT EXP004 ADDS TO EXP003

EXP003 designed the rotor controller for rotor-angle performance and control
effort. Tutorial 4 section 1 points out what that left out: "application of a
Reference Tracking input signal to the MIMO system results in Pendulum Angle
displacement in addition to Rotor Angle", and adds a ROBUSTNESS constraint --
immunity to variation in plant and controller characteristics.

SENSITIVITY FUNCTION (Tutorial 4 section 5, derived from first principles there)

    S(s) = lim   [dT/T] / [dP/P]  =  P/T * dT/dP  =  1/(1 + P(s)C(s))
           d->0

Here P = T_rotor (the inner closed loop from EXP003) and C = K_rotor.
S measures the FRACTIONAL change in closed-loop behaviour produced by a
fractional change in the plant -- so small |S| means a design whose performance
survives supply variation, temperature and manufacturing tolerance.

METRICS (Tutorial 4 section 6)

    M_S    = max over w of |S(jw)|          reported in dB
    w_SC   = the frequency where |S(jw)| = 1     (sensitivity crossover)

    Design objectives: meet settling time and overshoot while
        1) REDUCING M_S      2) INCREASING w_SC

NYQUIST INTERPRETATION (Tutorial 4 section 6)

    1/S = 1 + PC, which is the vector from the point (-1, 0) to P(jw)C(jw).
    Therefore |V_S| = 1/|S|, and

        M_S = 1 / min |1 + L(jw)|   =  1 / (closest approach of the Nyquist
                                            curve to the -1 point)

    |S| < 1 outside the unit circle centred on (-1,0); |S| > 1 inside it.
    This script verifies the identity numerically rather than asserting it.

WHY NO DERIVATIVE FILTER HERE (and why EXP003 needed one)

EXP003's CE_Max is a TIME-DOMAIN metric of an IMPROPER transfer function, so it
required a derivative realisation and a discretisation. M_S and w_SC are
FREQUENCY-DOMAIN metrics of a proper transfer function and need neither.
Computing M_S for Kp=6, Kd=4.8 with the ideal controller gives 2.794 dB against
Tutorial 4's published 2.7 dB (0.09 dB); adding an N=100 filter shifts it to
3.12 dB and away from the source. The ideal controller is therefore used
throughout EXP004, matching what the tutorial evidently does.

DESIGN OBJECTIVES (Tutorial 4 section 8)
    Search range: 0.25 <= Kp <= 5 and 0.25 <= Kd <= 5
    Step 1: M_S < 1 dB, minimum settling time, overshoot < 30 %
    Step 2: M_S < 3 dB, minimum settling time, overshoot < 30 %

Run:  python3 scripts/exp004_mimo_sensitivity.py
"""

from __future__ import annotations

import csv
import math
from pathlib import Path

import numpy as np
from scipy import signal
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent
FIGDIR = REPO / "results" / "figures"
TABDIR = REPO / "results" / "tables"

# Suspended-mode pendulum, Tutorial 12. REFERENCE/ASSUMED -- open item OI-9.
WR2, WG2, QF = 0.803, 57.01, 27.0
GAMMA = math.sqrt(WG2) / QF
DEN_PEND = [1.0, GAMMA, WG2]

# Inner controller: SUPPLIED and FIXED by Tutorials 3 and 4.
KP_PEND, KD_PEND = 10.0, 5.0

# Tutorial 4 reference point (Figures 7, 9, 11).
REF_KP, REF_KD = 6.0, 4.8
TUTORIAL_MS_DB_SIM = 2.7
TUTORIAL_MS_DB_EXP = 2.4

# Tutorial 4 section 8 search range and objectives.
KP_RANGE = (0.25, 5.0)
KD_RANGE = (0.25, 5.0)
STEP1 = dict(ms_db_max=1.0, overshoot_max=30.0, name="Step 1: M_S < 1 dB")
STEP2 = dict(ms_db_max=3.0, overshoot_max=30.0, name="Step 2: M_S < 3 dB")

# Reporting grid: dense, for accurate M_S and w_SC on the designs we publish.
W = np.logspace(-3.0, 4.0, 200000)
# Search grid: 2000 points is ample to rank designs by M_S and keeps a 96x96
# sweep to seconds. Winners are re-measured on W before anything is reported.
W_SEARCH = np.logspace(-3.0, 4.0, 2000)


def loop(kp: float, kd: float):
    """Open-loop L = T_rotor * K_rotor, plus T_rotor and G_pend, as (num, den)."""
    inner = np.polyadd(DEN_PEND, np.polymul([WR2], [KD_PEND, KP_PEND]))
    tr_num = np.array(DEN_PEND, dtype=float)
    tr_den = np.polymul([1.0, 0.0, 0.0], inner)
    kr = np.array([kd, kp], dtype=float)
    return (np.polymul(tr_num, kr), tr_den), (tr_num, tr_den)


def sensitivity(kp: float, kd: float, w=None) -> dict:
    """M_S, w_SC and the Nyquist closest-approach check."""
    if w is None:
        w = W
    (ln, ld), _ = loop(kp, kd)
    lj = np.polyval(ln, 1j * w) / np.polyval(ld, 1j * w)
    s = 1.0 / (1.0 + lj)
    mag = np.abs(s)

    ms = float(np.max(mag))
    ms_db = 20.0 * math.log10(ms)

    # Sensitivity crossover: lowest frequency at which |S| first reaches 1.
    cross = np.where(np.diff(np.sign(mag - 1.0)))[0]
    w_sc = float(w[cross[0]]) if cross.size else float("nan")

    # Nyquist identity: M_S = 1 / min|1 + L|.
    dmin = float(np.min(np.abs(-1.0 - lj)))
    return dict(ms=ms, ms_db=ms_db, w_sc=w_sc, nyquist_dmin=dmin,
                nyquist_identity_err=abs(dmin - 1.0 / ms))


def responses(kp: float, kd: float, t_end: float = 40.0, n: int = 8001) -> dict:
    """Rotor and pendulum step responses to a rotor reference step."""
    (ln, ld), (trn, trd) = loop(kp, kd)
    cl = np.polyadd(ld, np.concatenate([np.zeros(len(ld) - len(ln)), ln]))
    t_track = (ln, cl)
    # theta/phi_cmd = G_pend * T_tracking
    gp_num = np.polymul([WR2], [1.0, 0.0, 0.0])
    pend = (np.polymul(gp_num, ln), np.polymul(DEN_PEND, cl))

    t = np.linspace(0.0, t_end, n)
    _, y = signal.step(t_track, T=t)
    _, th = signal.step(pend, T=t)
    y = np.asarray(y).ravel()
    th = np.asarray(th).ravel()
    if not (np.all(np.isfinite(y)) and np.all(np.isfinite(th))):
        return None

    overshoot = 100.0 * (float(np.max(y)) - 1.0)
    out = np.where(np.abs(y - 1.0) > 0.02)[0]
    settling = float(t[out[-1]]) if out.size else 0.0
    if out.size and out[-1] >= n - 2:
        settling = math.inf

    # Pendulum settling: back inside 2 % of its own peak excursion.
    pk = float(np.max(np.abs(th)))
    if pk > 1e-12:
        po = np.where(np.abs(th) > 0.02 * pk)[0]
        pend_settling = float(t[po[-1]]) if po.size else 0.0
        if po.size and po[-1] >= n - 2:
            pend_settling = math.inf
    else:
        pend_settling = 0.0

    return dict(settling=settling, overshoot=overshoot,
                pend_peak=pk, pend_settling=pend_settling, t=t, y=y, th=th)


def analyse(kp: float, kd: float, **kw) -> dict | None:
    r = responses(kp, kd, **kw)
    if r is None:
        return None
    r.update(sensitivity(kp, kd))
    r.update(kp=kp, kd=kd, td=(kd / kp if kp else math.nan))
    return r


def is_stable(kp: float, kd: float) -> bool:
    (ln, ld), _ = loop(kp, kd)
    cl = np.polyadd(ld, np.concatenate([np.zeros(len(ld) - len(ln)), ln]))
    r = np.roots(cl)
    return bool(r.size == 0 or float(np.max(r.real)) < -1e-9)


def search(obj: dict):
    """Minimum settling time subject to M_S and overshoot limits.

    M_S is screened first: it needs only a frequency response, which is far
    cheaper than a step simulation, and it eliminates most of the grid.
    """
    best = None
    for kp in np.arange(KP_RANGE[0], KP_RANGE[1] + 1e-9, 0.05):
        for kd in np.arange(KD_RANGE[0], KD_RANGE[1] + 1e-9, 0.05):
            if not is_stable(float(kp), float(kd)):
                continue
            sen = sensitivity(float(kp), float(kd), w=W_SEARCH)
            if sen["ms_db"] > obj["ms_db_max"]:
                continue
            r = responses(float(kp), float(kd), t_end=40.0, n=4001)
            if r is None or r["overshoot"] > obj["overshoot_max"]:
                continue
            if best is None or r["settling"] < best["settling"]:
                best = dict(kp=float(kp), kd=float(kd), settling=r["settling"])
    return analyse(best["kp"], best["kd"], n=16001) if best else None


def report(tag: str, r: dict, obj: dict | None = None) -> None:
    print(f"  {tag}")
    print(f"    Kp = {r['kp']:.4f}   Td = {r['td']:.4f} s   Kd = {r['kd']:.4f}")
    print(f"    M_S                     {r['ms']:8.4f} = {r['ms_db']:7.3f} dB")
    print(f"    w_SC (|S| = 1)          {r['w_sc']:8.4f} rad/s")
    print(f"    Rotor settling (2%)     {r['settling']:8.3f} s")
    print(f"    Rotor overshoot         {r['overshoot']:8.2f} %")
    print(f"    Pendulum peak excursion {r['pend_peak']:8.4f} (per unit rotor step)")
    print(f"    Pendulum settling       {r['pend_settling']:8.3f} s")
    print(f"    Nyquist min|1+L|        {r['nyquist_dmin']:8.5f}  "
          f"(1/M_S = {1.0/r['ms']:.5f}, err {r['nyquist_identity_err']:.2e})")
    if obj:
        ok = r["ms_db"] <= obj["ms_db_max"] and r["overshoot"] <= obj["overshoot_max"]
        print(f"    Meets {obj['name']} and overshoot <= {obj['overshoot_max']} %: "
              f"{'YES' if ok else 'NO'}")
    print()


def make_figures(designs: list[tuple[str, dict]]) -> None:
    # --- Sensitivity magnitude ---------------------------------------------
    fig, ax = plt.subplots(1, 2, figsize=(13, 5))
    for name, r in designs:
        if r is None:
            continue
        (ln, ld), _ = loop(r["kp"], r["kd"])
        lj = np.polyval(ln, 1j * W) / np.polyval(ld, 1j * W)
        mag = np.abs(1.0 / (1.0 + lj))
        ax[0].semilogx(W, 20 * np.log10(mag), lw=1.7,
                       label=f"{name}: Kp={r['kp']:.2f} Kd={r['kd']:.2f}, "
                             f"$M_S$={r['ms_db']:.2f} dB")
        ax[0].plot([r["w_sc"]], [0.0], "o", ms=6)
    ax[0].axhline(0.0, color="k", lw=0.9, ls="--")
    ax[0].axhline(1.0, color="seagreen", lw=0.9, ls=":", label="1 dB limit (Step 1)")
    ax[0].axhline(3.0, color="darkorange", lw=0.9, ls=":", label="3 dB limit (Step 2)")
    ax[0].set_xlim(1e-2, 1e3); ax[0].set_ylim(-40, 8)
    ax[0].set_xlabel("frequency [rad/s]"); ax[0].set_ylabel("$|S(j\\omega)|$ [dB]")
    ax[0].set_title("Sensitivity function\n(markers: $\\omega_{SC}$ where $|S|=1$)")
    ax[0].legend(fontsize=7.5, loc="lower right"); ax[0].grid(alpha=0.3, which="both")

    # --- Nyquist with the unit circle about -1 ------------------------------
    wn = np.logspace(-2, 3, 40000)
    for name, r in designs:
        if r is None:
            continue
        (ln, ld), _ = loop(r["kp"], r["kd"])
        lj = np.polyval(ln, 1j * wn) / np.polyval(ld, 1j * wn)
        ax[1].plot(lj.real, lj.imag, lw=1.4, label=f"{name} ($M_S$={r['ms_db']:.2f} dB)")
    th = np.linspace(0, 2 * np.pi, 400)
    ax[1].plot(-1 + np.cos(th), np.sin(th), "k--", lw=1.0, label="unit circle about (-1,0)")
    ax[1].plot([-1], [0], "rx", ms=9, mew=2)
    ax[1].set_xlim(-3, 1.5); ax[1].set_ylim(-2.5, 2.5)
    ax[1].set_xlabel("Re $L(j\\omega)$"); ax[1].set_ylabel("Im $L(j\\omega)$")
    ax[1].set_title("Nyquist: $M_S = 1/\\min|1+L|$\n$|S|>1$ inside the circle")
    ax[1].legend(fontsize=7.5, loc="lower left"); ax[1].grid(alpha=0.3)
    ax[1].set_aspect("equal", adjustable="box")

    fig.suptitle("EXP004 (Tutorial 4) -- MIMO sensitivity-function performance  "
                 "[MODEL; INDEPENDENT NUMERICAL CHECK, not MATLAB]", fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    fig.savefig(FIGDIR / "EXP004_fig1_sensitivity_and_nyquist.png", dpi=150)
    plt.close(fig)

    # --- Both outputs -------------------------------------------------------
    fig, ax = plt.subplots(1, 2, figsize=(13, 4.8))
    for name, r in designs:
        if r is None:
            continue
        lbl = f"{name}: $M_S$={r['ms_db']:.2f} dB, $t_s$={r['settling']:.2f} s"
        ax[0].plot(r["t"], r["y"], lw=1.7, label=lbl)
        ax[1].plot(r["t"], r["th"], lw=1.5, label=lbl)
    ax[0].axhline(1.0, color="k", lw=0.8)
    ax[0].axhspan(0.98, 1.02, color="seagreen", alpha=0.12)
    ax[0].set_xlim(0, 25); ax[0].set_xlabel("time [s]")
    ax[0].set_ylabel("rotor angle / reference [-]")
    ax[0].set_title("Rotor angle -- the output EXP003 designed for")
    ax[0].legend(fontsize=8); ax[0].grid(alpha=0.3)

    ax[1].axhline(0.0, color="k", lw=0.8)
    ax[1].set_xlim(0, 25); ax[1].set_xlabel("time [s]")
    ax[1].set_ylabel("pendulum angle / rotor reference [-]")
    ax[1].set_title("Pendulum angle -- the output EXP004 adds\n"
                    "a rotor command displaces the pendulum")
    ax[1].legend(fontsize=8); ax[1].grid(alpha=0.3)

    fig.suptitle("EXP004 -- BOTH outputs respond to a rotor reference step "
                 "[MODEL, not measured]", fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    fig.savefig(FIGDIR / "EXP004_fig2_both_outputs.png", dpi=150)
    plt.close(fig)


def main() -> None:
    FIGDIR.mkdir(parents=True, exist_ok=True)
    TABDIR.mkdir(parents=True, exist_ok=True)

    print("EXP004 (Tutorial 4) -- MIMO sensitivity-function performance")
    print("INDEPENDENT SOFTWARE NUMERICAL CHECK -- NOT MATLAB, NOT hardware")
    print("=" * 76)
    print(f"\n  S(s) = 1/(1 + T_rotor*K_rotor);  M_S = max|S|;  w_SC where |S| = 1")
    print(f"  K_pend = {KP_PEND} + {KD_PEND} s  (SUPPLIED and FIXED)\n")

    ref = analyse(REF_KP, REF_KD, n=16001)
    report("REFERENCE -- Tutorial 4 Figures 7/9/11 (Kp=6, Kd=4.8)", ref)

    print("  VALIDATION against Tutorial 4's published values")
    print(f"    M_S (simulation)   tutorial {TUTORIAL_MS_DB_SIM:5.2f} dB   "
          f"computed {ref['ms_db']:6.3f} dB   diff {ref['ms_db']-TUTORIAL_MS_DB_SIM:+.3f} dB")
    print(f"    M_S (experiment)   tutorial {TUTORIAL_MS_DB_EXP:5.2f} dB   "
          f"(hardware -- NOT reproduced here, no rig)")
    print(f"    Nyquist identity   min|1+L| = {ref['nyquist_dmin']:.6f}  vs  "
          f"1/M_S = {1.0/ref['ms']:.6f}   err {ref['nyquist_identity_err']:.2e}")
    print()

    d1 = search(STEP1)
    if d1:
        report(f"DESIGN A -- {STEP1['name']}, minimum settling time", d1, STEP1)
    else:
        print(f"  NO design in the Tutorial 4 range meets {STEP1['name']}.\n")

    d2 = search(STEP2)
    if d2:
        report(f"DESIGN B -- {STEP2['name']}, minimum settling time", d2, STEP2)
    else:
        print(f"  NO design in the Tutorial 4 range meets {STEP2['name']}.\n")

    make_figures([("Reference (Kp=6, Kd=4.8)", ref), ("Design A (<1 dB)", d1),
                  ("Design B (<3 dB)", d2)])

    rows = [("parameter_set", "EXP004-T4", "-"),
            ("tutorial_ms_db_sim", TUTORIAL_MS_DB_SIM, "dB"),
            ("tutorial_ms_db_exp", TUTORIAL_MS_DB_EXP, "dB")]
    for tag, r in (("ref", ref), ("designA", d1), ("designB", d2)):
        if r is None:
            continue
        rows += [(f"{tag}_kp", f"{r['kp']:.4f}", "-"),
                 (f"{tag}_td", f"{r['td']:.4f}", "s"),
                 (f"{tag}_kd", f"{r['kd']:.4f}", "-"),
                 (f"{tag}_ms_db", f"{r['ms_db']:.4f}", "dB"),
                 (f"{tag}_w_sc", f"{r['w_sc']:.4f}", "rad/s"),
                 (f"{tag}_settling", f"{r['settling']:.4f}", "s"),
                 (f"{tag}_overshoot", f"{r['overshoot']:.4f}", "%"),
                 (f"{tag}_pend_peak", f"{r['pend_peak']:.6f}", "-"),
                 (f"{tag}_pend_settling", f"{r['pend_settling']:.4f}", "s")]
    out = TABDIR / "EXP004_design_results.csv"
    with out.open("w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["quantity", "value", "unit"]); w.writerows(rows)

    print(f"  wrote {out.relative_to(REPO)}")
    for nm in ("EXP004_fig1_sensitivity_and_nyquist.png",
               "EXP004_fig2_both_outputs.png"):
        print(f"  wrote {(FIGDIR / nm).relative_to(REPO)}")
    print("\n  STATUS: INDEPENDENT SOFTWARE NUMERICAL CHECK -- EXECUTED.")
    print("  STATUS: MATLAB tools -- DEFERRED, MATLAB EXECUTION ENVIRONMENT REQUIRED.")
    print("  STATUS: hardware measurement -- NOT_EXECUTED, no rig attached.")


if __name__ == "__main__":
    main()

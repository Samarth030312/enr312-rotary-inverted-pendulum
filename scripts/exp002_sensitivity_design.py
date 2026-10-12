#!/usr/bin/env python3
"""
EXP002 (Tutorial 2) -- Performance Analysis by Sensitivity Function.

INDEPENDENT SOFTWARE NUMERICAL CHECK.
================================================================================
This is NOT MATLAB and does NOT represent MATLAB execution. MATLAB and Octave are
both absent from this machine (verified: `which matlab`, `which octave`).

Tutorial 2 performs this design with Edukit_PID_Motor_Control_Design.m. The problem
is fully specified and analytically tractable, so it is solved here independently in
Python. The MATLAB equivalents exist under matlab/ and are marked NOT_EXECUTED.
Results below are real computations; they are simply not MATLAB's.
================================================================================

PLANT AND CONTROLLER (Tutorial 1 section 2, Tutorial 2 section 1)

    Rotor plant        P(s) = 1/s^2          [rad per rad, double integrator]
    Rotor controller   C(s) = Kp + Kd*s      Kd = Kp*Td

CLOSED-LOOP TRANSFER FUNCTIONS (Tutorial 2 section 1)

    Loop                  L(s)   = P C       = (Kd s + Kp) / s^2
    Sensitivity           S(s)   = 1/(1+L)   = s^2        / (s^2 + Kd s + Kp)
    Complementary sens.   T(s)   = L/(1+L)   = (Kd s + Kp)/ (s^2 + Kd s + Kp)
    Load-disturbance sens SD(s)  = P/(1+L)   = 1          / (s^2 + Kd s + Kp)

    All three share the closed-loop denominator, so
        omega_n = sqrt(Kp)   [rad/s]     zeta = Kd / (2 sqrt(Kp))   [-]

SIGN AND UNIT CONVENTIONS -- stated explicitly, never implied

    Kp   [1/s^2] acting on rotor-angle error in rad -> rotor-angle acceleration command
    Kd   [1/s]   Kd = Kp*Td, Td in seconds
    T step response: output is rotor angle, normalised to a unit reference step.
                     Final value 1 (exact, since T(0) = 1).
    SD step response: output is rotor angle deviation caused by a unit load-disturbance
                     step at the plant input. Final value SD(0) = 1/Kp, NOT zero --
                     a PD controller has no integral action, so a constant load leaves a
                     constant offset. Overshoot for SD is therefore measured RELATIVE TO
                     ITS OWN FINAL VALUE 1/Kp, and settling is to 2 % of that final value.
                     This convention is stated because it is the one place where a
                     careless reading would silently compare against zero.

Run:  python3 scripts/exp002_sensitivity_design.py
"""

from __future__ import annotations

import csv
import math
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parent.parent
FIGDIR = REPO / "results" / "figures"
TABDIR = REPO / "results" / "tables"

# Tutorial 2 section 3 design objectives ------------------------------------
SPEC = {
    "rotor_peak_time_max_s":   2.0,
    "rotor_overshoot_max_pct": 30.0,
    "rotor_settling_max_s":    4.0,
    "dist_peak_time_max_s":    3.0,
    "dist_overshoot_max_pct":  15.0,
    "dist_settling_max_s":     4.0,
}
KD_RANGE = (0.0, 4.0)      # Tutorial 2: "Design for Kd in range of 0 to 4.0"
KP_RANGE = (0.5, 10.0)     # Tutorial 2: "Design for Kp in range 0.5 < Kp < 10"

# Tutorial 1 section 4 design -----------------------------------------------
T1_KP, T1_TD = 5.0, 0.5
T1_KD = T1_KP * T1_TD      # 2.5


def _responses(kp, kd, t):
    """Exact closed-form step responses of T(s) and SD(s), vectorised over t.

    Both share the denominator s^2 + Kd s + Kp with poles p1, p2 (p1*p2 = Kp).
    Working from the poles rather than calling a numerical ODE solver makes the
    design sweep about four orders of magnitude cheaper, and it is exact rather
    than approximate.

        g(t) = 1 + (p2 e^{p1 t} - p1 e^{p2 t}) / (p1 - p2)     unit-DC-gain step
        h(t) = (e^{p1 t} - e^{p2 t}) / (p1 - p2)               impulse of 1/den

        SD step = g(t) / Kp          because SD = 1/den and SD(0) = 1/Kp
        T  step = g(t) + Kd * h(t)   because T = (Kd s + Kp)/den

    Valid for distinct poles; the repeated-pole case (Kd^2 = 4 Kp) is a measure-zero
    set on the search grid and is skipped by the caller.
    """
    disc = complex(kd * kd - 4.0 * kp)
    r = np.sqrt(disc)
    p1 = (-kd + r) / 2.0
    p2 = (-kd - r) / 2.0
    d = p1 - p2
    if abs(d) < 1e-12:
        return None, None
    e1 = np.exp(p1 * t)
    e2 = np.exp(p2 * t)
    g = np.real(1.0 + (p2 * e1 - p1 * e2) / d)
    h = np.real((e1 - e2) / d)
    return g / kp, g + kd * h        # (SD step, T step)


def _metrics(y, yf, t, settle_tol=0.02):
    """Peak value/time, overshoot relative to the system's OWN final value, 2% settling."""
    ipk = int(np.argmax(y))
    peak, tpk = float(y[ipk]), float(t[ipk])
    overshoot = 100.0 * (peak - yf) / abs(yf)
    outside = np.where(np.abs(y - yf) > settle_tol * abs(yf))[0]
    if outside.size == 0:
        settling = 0.0
    elif outside[-1] >= y.size - 2:
        settling = float("inf")          # never settled inside the window
    else:
        settling = float(t[outside[-1]])
    return dict(final=yf, peak=peak, peak_time=tpk,
                overshoot_pct=overshoot, settling_s=settling)


_T_SEARCH = np.linspace(0.0, 30.0, 3001)     # 10 ms grid, ample for a 4 s spec
_T_FINE = np.linspace(0.0, 60.0, 60001)      # 1 ms grid for the reported designs


def analyse(kp: float, kd: float, fine: bool = False) -> dict | None:
    """All Tutorial 2 quantities for one (Kp, Kd) pair."""
    t = _T_FINE if fine else _T_SEARCH
    sd_y, t_y = _responses(kp, kd, t)
    if sd_y is None:
        return None
    SD = _metrics(sd_y, 1.0 / kp, t)          # SD(0) = 1/Kp, NOT zero
    T = _metrics(t_y, 1.0, t)                 # T(0)  = 1 exactly
    wn = math.sqrt(kp)
    zeta = kd / (2.0 * wn) if wn > 0 else float("inf")
    return dict(kp=kp, kd=kd, td=(kd / kp if kp else float("nan")),
                wn=wn, zeta=zeta, T=T, SD=SD)


def meets_spec(r: dict) -> bool:
    T, SD = r["T"], r["SD"]
    return (T["peak_time"] <= SPEC["rotor_peak_time_max_s"] and
            T["overshoot_pct"] <= SPEC["rotor_overshoot_max_pct"] and
            T["settling_s"] <= SPEC["rotor_settling_max_s"] and
            SD["peak_time"] <= SPEC["dist_peak_time_max_s"] and
            SD["overshoot_pct"] <= SPEC["dist_overshoot_max_pct"] and
            SD["settling_s"] <= SPEC["dist_settling_max_s"])


def report(tag: str, r: dict) -> None:
    T, SD = r["T"], r["SD"]
    print(f"  {tag}")
    print(f"    Kp = {r['kp']:.4f}   Td = {r['td']:.4f} s   Kd = {r['kd']:.4f}")
    print(f"    omega_n = {r['wn']:.4f} rad/s    zeta = {r['zeta']:.4f}")
    print(f"    Complementary sensitivity T(s)  [reference tracking, final value 1]")
    print(f"        peak time     {T['peak_time']:8.3f} s   (spec <= {SPEC['rotor_peak_time_max_s']})")
    print(f"        peak value    {T['peak']:8.4f}")
    print(f"        overshoot     {T['overshoot_pct']:8.2f} %   (spec <= {SPEC['rotor_overshoot_max_pct']})")
    print(f"        settling 2%   {T['settling_s']:8.3f} s   (spec <= {SPEC['rotor_settling_max_s']})")
    print(f"    Load-disturbance sensitivity SD(s)  [final value 1/Kp = {SD['final']:.4f}]")
    print(f"        peak time     {SD['peak_time']:8.3f} s   (spec <= {SPEC['dist_peak_time_max_s']})")
    print(f"        peak value    {SD['peak']:8.4f}")
    print(f"        overshoot     {SD['overshoot_pct']:8.2f} %   (spec <= {SPEC['dist_overshoot_max_pct']})")
    print(f"        settling 2%   {SD['settling_s']:8.3f} s   (spec <= {SPEC['dist_settling_max_s']})")
    print(f"    MEETS ALL TUTORIAL 2 OBJECTIVES: {'YES' if meets_spec(r) else 'NO'}")
    print()


def search():
    """Grid search the Tutorial 2 admissible region for compliant designs."""
    best, feasible = None, []
    for kp in np.arange(0.55, 10.0001, 0.05):
        for kd in np.arange(0.10, 4.0001, 0.05):
            r = analyse(float(kp), float(kd))
            if r is not None and meets_spec(r):
                feasible.append(r)
                # Prefer the fastest disturbance settling, then least overshoot.
                key = (r["SD"]["settling_s"], r["SD"]["overshoot_pct"])
                if best is None or key < (best["SD"]["settling_s"],
                                          best["SD"]["overshoot_pct"]):
                    best = r
    return best, feasible


def make_figures(t1: dict, sel: dict | None) -> None:
    """Two figures, each answering a stated engineering question."""
    t = np.linspace(0.0, 12.0, 12001)

    # --- Fig 1: the two sensitivity step responses, model vs specification ---
    fig, ax = plt.subplots(1, 2, figsize=(12.5, 5))
    for r, style in ((t1, "-"), (sel, "--")):
        if r is None:
            continue
        sd, tt = _responses(r["kp"], r["kd"], t)
        lbl = f"Kp={r['kp']:.2f}, Kd={r['kd']:.2f}"
        ax[0].plot(t, tt, style, lw=1.8, label=lbl)
        ax[1].plot(t, sd, style, lw=1.8, label=lbl)
        ax[1].axhline(1.0 / r["kp"], color="grey", ls=":", lw=0.8)

    ax[0].axhline(1.0, color="k", lw=0.8)
    ax[0].axhspan(0.98, 1.02, color="seagreen", alpha=0.12, label="2 % band")
    ax[0].set_xlabel("time [s]"); ax[0].set_ylabel("rotor angle / reference [-]")
    ax[0].set_title("Complementary sensitivity T(s)\nreference tracking, final value 1")
    ax[0].legend(); ax[0].grid(alpha=0.3)

    ax[1].axhline(0.0, color="k", lw=0.8)
    ax[1].set_xlabel("time [s]"); ax[1].set_ylabel("rotor angle deviation [-]")
    ax[1].set_title("Load-disturbance sensitivity SD(s)\n"
                    "dotted = final value 1/Kp: a PERMANENT offset")
    ax[1].legend(); ax[1].grid(alpha=0.3)
    ax[1].text(0.5, 0.06,
               "A PD controller has no integral action, so the\n"
               "response never returns to zero. Measured against\n"
               "zero it never settles -- this is why Tutorial 2\n"
               "warns of extended settling time, and why\n"
               "Tutorial 6 introduces integral action.",
               transform=ax[1].transAxes, fontsize=8.5,
               bbox=dict(fc="white", alpha=0.85, ec="grey"))

    fig.suptitle("EXP002 (Tutorial 2) -- sensitivity step responses  "
                 "[MODEL, not measured; INDEPENDENT NUMERICAL CHECK, not MATLAB]",
                 fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.93))
    fig.savefig(FIGDIR / "EXP002_fig1_sensitivity_step_responses.png", dpi=150)
    plt.close(fig)

    # --- Fig 2: feasible design region -------------------------------------
    kps = np.arange(0.55, 10.0001, 0.10)
    kds = np.arange(0.10, 4.0001, 0.05)
    ok = np.zeros((kds.size, kps.size))
    for i, kd in enumerate(kds):
        for j, kp in enumerate(kps):
            r = analyse(float(kp), float(kd))
            ok[i, j] = 1.0 if (r is not None and meets_spec(r)) else 0.0

    fig, ax = plt.subplots(figsize=(9, 6))
    ax.pcolormesh(kps, kds, ok, cmap="Greens", vmin=0, vmax=1.6, shading="auto")
    ax.plot(t1["kp"], t1["kd"], "o", ms=11, mfc="none", mec="crimson", mew=2.2,
            label=f"Tutorial 1 design ({t1['kp']:.2f}, {t1['kd']:.2f})")
    if sel is not None:
        ax.plot(sel["kp"], sel["kd"], "*", ms=17, color="navy",
                label=f"EXP002 selected ({sel['kp']:.2f}, {sel['kd']:.2f})")
    ax.set_xlabel("$K_P$"); ax.set_ylabel("$K_d$")
    ax.set_title("EXP002 -- designs meeting ALL SIX Tutorial 2 objectives (green)\n"
                 "[MODEL, not measured]")
    ax.legend(loc="lower right"); ax.grid(alpha=0.25)
    fig.tight_layout()
    fig.savefig(FIGDIR / "EXP002_fig2_feasible_design_region.png", dpi=150)
    plt.close(fig)


def main() -> None:
    FIGDIR.mkdir(parents=True, exist_ok=True)
    TABDIR.mkdir(parents=True, exist_ok=True)

    print(__doc__.split("Run:")[0].strip()[:0] or "", end="")
    print("EXP002 (Tutorial 2) sensitivity-function design")
    print("INDEPENDENT SOFTWARE NUMERICAL CHECK -- NOT MATLAB, NOT hardware")
    print("=" * 74)
    print()
    print("Plant P(s) = 1/s^2 ; Controller C(s) = Kp + Kd s")
    print()

    t1 = analyse(T1_KP, T1_KD, fine=True)
    report("TUTORIAL 1 DESIGN (Kp = 5, Td = 0.5, Kd = 2.5)", t1)

    best, feasible = search()
    print(f"  Grid search over {KP_RANGE[0]} < Kp < {KP_RANGE[1]}, "
          f"{KD_RANGE[0]} < Kd <= {KD_RANGE[1]}")
    print(f"  Feasible designs found: {len(feasible)}")
    print()
    if best is not None:
        best = analyse(best["kp"], best["kd"], fine=True)   # re-measure on the fine grid
    if best is None:
        print("  NO DESIGN in the admissible region meets all six objectives.")
        print("  This is a real finding, not a tooling failure -- see EXP002 "
              "FIRST_PRINCIPLES.md.")
    else:
        report("EXP002 SELECTED DESIGN (fastest disturbance settling)", best)

    make_figures(t1, best)

    rows = [("parameter_set", "EXP002-T2", "-"),
            ("plant", "1/s^2", "-"),
            ("controller", "Kp + Kd*s", "-")]
    for tag, r in (("t1", t1), ("sel", best)):
        if r is None:
            continue
        rows += [
            (f"{tag}_kp", f"{r['kp']:.6f}", "1/s^2"),
            (f"{tag}_td", f"{r['td']:.6f}", "s"),
            (f"{tag}_kd", f"{r['kd']:.6f}", "1/s"),
            (f"{tag}_omega_n", f"{r['wn']:.6f}", "rad/s"),
            (f"{tag}_zeta", f"{r['zeta']:.6f}", "-"),
            (f"{tag}_T_peak_time", f"{r['T']['peak_time']:.6f}", "s"),
            (f"{tag}_T_peak", f"{r['T']['peak']:.6f}", "-"),
            (f"{tag}_T_overshoot", f"{r['T']['overshoot_pct']:.6f}", "%"),
            (f"{tag}_T_settling", f"{r['T']['settling_s']:.6f}", "s"),
            (f"{tag}_SD_final", f"{r['SD']['final']:.6f}", "-"),
            (f"{tag}_SD_peak_time", f"{r['SD']['peak_time']:.6f}", "s"),
            (f"{tag}_SD_peak", f"{r['SD']['peak']:.6f}", "-"),
            (f"{tag}_SD_overshoot", f"{r['SD']['overshoot_pct']:.6f}", "%"),
            (f"{tag}_SD_settling", f"{r['SD']['settling_s']:.6f}", "s"),
        ]
    out = TABDIR / "EXP002_design_results.csv"
    with out.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["quantity", "value", "unit"])
        w.writerows(rows)
    print(f"  wrote {out.relative_to(REPO)}")
    for nm in ("EXP002_fig1_sensitivity_step_responses.png",
               "EXP002_fig2_feasible_design_region.png"):
        print(f"  wrote {(FIGDIR / nm).relative_to(REPO)}")
    print()
    print("  STATUS: INDEPENDENT SOFTWARE NUMERICAL CHECK -- EXECUTED.")
    print("  STATUS: MATLAB design tool -- DEFERRED, MATLAB EXECUTION ENVIRONMENT REQUIRED.")
    print("  STATUS: hardware sensitivity measurement -- NOT_EXECUTED, no rig attached.")


if __name__ == "__main__":
    main()

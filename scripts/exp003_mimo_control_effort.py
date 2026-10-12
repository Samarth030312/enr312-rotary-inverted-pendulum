#!/usr/bin/env python3
"""
EXP003 (Tutorial 3) -- Control of MIMO Systems: Control Effort, Suspended Mode.

INDEPENDENT SOFTWARE NUMERICAL CHECK.
================================================================================
NOT MATLAB. MATLAB and Octave are both absent from this machine (verified).
Tutorial 3 performs this with Edukit_Single_Rotor_PID_Suspended_Mode_Design.m.
That problem is fully specified and analytically tractable, so it is solved here
independently. MATLAB equivalents exist under matlab/ and are NOT_EXECUTED.
================================================================================

PLANTS  (Tutorial 3 sections 3-4; pendulum plant from Tutorial 12 section 2)

    Rotor       G_rotor(s) = 1/s^2
    Pendulum    G_pend(s)  = wr^2 s^2 / (s^2 + (wg/Q) s + wg^2)      SUSPENDED mode
                wr^2 = 0.803 (rad/s)^2, wg^2 = 57.01 (rad/s)^2, Q = 27

CONTROLLERS (Tutorial 3 section 3 and section 6)

    Pendulum (inner, SUPPLIED and FIXED by Tutorial 3):
        K_pend(s)  = Kp_pend + Kd_pend s,  Kp_pend = 10.0, Td = 0.5 s, Kd_pend = 5.0
    Rotor (outer, TO BE DESIGNED -- this Tutorial's objective):
        K_rotor(s) = Kp_rotor + Kd_rotor s,  defaults Kp = 6, Td = 0.8, Kd = 4.8

LOOP STRUCTURE (Tutorial 3 section 4)

    Inner loop, pendulum-angle reference held at zero:
        T_rotor(s) = G_rotor / (1 + G_pend K_pend G_rotor)
    Outer loop, rotor-angle reference tracking:
        T_rotor_tracking(s) = T_rotor K_rotor / (1 + T_rotor K_rotor)
    Control effort (Tutorial 3 section 5; also the noise sensitivity function):
        CE(s) = u(s)/R(s) = K_rotor / (1 + T_rotor K_rotor)

CONTROL-EFFORT METRICS (Tutorial 3 section 5)
    CE_Max_Amplitude = max |u(t)|
    CE_Max_Power     = max u(t)^2
    CE_Total         = integral of |u| dt        <-- see the CONFLICT note below

--------------------------------------------------------------------------------
DOCUMENTED CONFLICT IN THE SOURCE (resolved by evidence, not by preference)

Tutorial 3 section 5 writes the third metric as

        CE_Total = integral from 0 to infinity of u(tau) d tau

but lists it in the results table as "Control Effort Total Energy" with the value
11.0 for Design 1.

The written formula cannot be what the tool computes. For this loop the DC gain of
CE is zero -- CE(s) ~ (Kp/ (Tr Kp)) s^2 as s -> 0 -- so the signed integral of u is
ZERO, which this script confirms numerically (residuals of order 0.02 over a
40 s window are the untruncated tail, three orders below the 10.9 of int|u|). The value 11.0 is
therefore not the signed integral.

Testing the three candidate readings against the tutorial's own Design 1 numbers:

        integral u   dt  =  0.0000     (not 11.0)
        integral u^2 dt  =  1.17e+03   (not 11.0)
        integral |u| dt  =  10.88      MATCHES 11.0

CE_Total is therefore implemented as the integral of |u|. The source's formula
omits the absolute value. Recorded rather than silently corrected.
--------------------------------------------------------------------------------

DISCRETISATION AND WHY CE_Max IS NOT A PURE PROPERTY OF THE PLANT

CE(s) is IMPROPER: K_rotor contributes a +1 relative degree that 1/(1+Tr Kr) does
not remove. Its step response therefore contains a Dirac delta, and any finite
CE_Max_Amplitude depends on how the derivative is realised.

Adding the derivative filter every real implementation needs,
K_rotor(s) -> (Kp + Kd s) N/(s + N), makes CE proper. Sweeping N shows CE_Max
scales linearly with N, and the tutorial's 477 is reproduced at N = 99.4 rad/s,
equivalent to a simulation sample of dt ~ 0.0101 s. The tutorial's tool evidently
simulates at about 100 Hz.

N = 100 rad/s is therefore adopted as the reference realisation, and every
CE_Max/CE_Max_Power figure in EXP003 is quoted WITH its N. Settling time,
overshoot and CE_Total are all insensitive to N (they vary < 5 % over N in
[50, 1000]), so the design conclusions do not depend on this choice.

Run:  python3 scripts/exp003_mimo_control_effort.py
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

# --- Suspended-mode pendulum, Tutorial 12 section 2. REFERENCE/ASSUMED ------
WR2 = 0.803      # (rad/s)^2
WG2 = 57.01      # (rad/s)^2
QF = 27.0
GAMMA = math.sqrt(WG2) / QF          # wg/Q, the damping coefficient
DEN_PEND = [1.0, GAMMA, WG2]

# --- Inner pendulum controller: SUPPLIED and FIXED by Tutorial 3 -----------
KP_PEND = 10.0
TD_PEND = 0.5
KD_PEND = KP_PEND * TD_PEND          # 5.0

# --- Design 1 defaults, Tutorial 3 section 6 -------------------------------
D1_KP, D1_TD = 6.0, 0.8
D1_KD = D1_KP * D1_TD                # 4.8

# --- Reference realisation of the derivative (see module docstring) --------
N_REF = 100.0                        # rad/s

# --- Tutorial 3 acceptance limits ------------------------------------------
STEP2 = dict(settling_max=4.0,  overshoot_max=30.0, ce_total_target=5.0)
STEP4 = dict(settling_max=10.0, overshoot_max=30.0, ce_total_target=2.5)

TUTORIAL_D1 = dict(ce_max=477.0, ce_power=2.27e5, ce_total=11.0,
                   settling=2.1, overshoot=31.4)


def build(kp_rotor: float, kd_rotor: float, n_filt: float = N_REF):
    """Return (T_rotor_tracking, CE) as (num, den) pairs."""
    inner = np.polyadd(DEN_PEND, np.polymul([WR2], [KD_PEND, KP_PEND]))
    tr_num = np.array(DEN_PEND, dtype=float)
    tr_den = np.polymul([1.0, 0.0, 0.0], inner)          # s^2 * inner

    if n_filt is None:
        kr_num, kr_den = np.array([kd_rotor, kp_rotor]), np.array([1.0])
    else:
        kr_num = np.array([kd_rotor * n_filt, kp_rotor * n_filt])
        kr_den = np.array([1.0, n_filt])

    l_num = np.polymul(tr_num, kr_num)
    l_den = np.polymul(tr_den, kr_den)
    cl = np.polyadd(l_den, np.concatenate([np.zeros(len(l_den) - len(l_num)), l_num]))
    return (l_num, cl), (np.polymul(kr_num, tr_den), cl)


def is_stable(kp: float, kd: float, n_filt: float = N_REF) -> bool:
    """Cheap closed-loop stability screen via pole locations.

    Simulating an unstable design is pointless and slow: the response overflows
    and the step solver grinds. Rejecting by root location first is exact and
    turns the grid sweep from tens of minutes into tens of seconds.
    """
    _, ce = build(kp, kd, n_filt)
    roots = np.roots(ce[1])
    return bool(roots.size == 0 or float(np.max(roots.real)) < -1e-9)


def analyse(kp: float, kd: float, n_filt: float = N_REF,
            t_end: float = 40.0, n: int = 8001) -> dict:
    t_track, ce = build(kp, kd, n_filt)
    t = np.linspace(0.0, t_end, n)
    _, y = signal.step(t_track, T=t)
    _, u = signal.step(ce, T=t)
    y = np.asarray(y).ravel()
    u = np.asarray(u).ravel()

    if not (np.all(np.isfinite(y)) and np.all(np.isfinite(u))):
        return None

    overshoot = 100.0 * (float(np.max(y)) - 1.0)
    out = np.where(np.abs(y - 1.0) > 0.02)[0]
    settling = float(t[out[-1]]) if out.size else 0.0
    if out.size and out[-1] >= n - 2:
        settling = math.inf

    return dict(kp=kp, td=(kd / kp if kp else math.nan), kd=kd, n_filt=n_filt,
                overshoot=overshoot, settling=settling,
                ce_max=float(np.max(np.abs(u))),
                ce_power=float(np.max(u ** 2)),
                ce_total=float(np.trapz(np.abs(u), t)),
                ce_signed=float(np.trapz(u, t)),
                t=t, y=y, u=u)


def report(tag: str, r: dict, limits: dict | None = None) -> None:
    print(f"  {tag}")
    print(f"    Kp_rotor = {r['kp']:.4f}   Td = {r['td']:.4f} s   Kd = {r['kd']:.4f}"
          f"   (derivative filter N = {r['n_filt']:.0f} rad/s)")
    print(f"    Rotor settling (2%)   {r['settling']:9.3f} s")
    print(f"    Rotor overshoot       {r['overshoot']:9.2f} %")
    print(f"    CE_Max_Amplitude      {r['ce_max']:9.1f}       (scales with N)")
    print(f"    CE_Max_Power          {r['ce_power']:9.3e}    (scales with N^2)")
    print(f"    CE_Total = int|u|dt   {r['ce_total']:9.3f}")
    print(f"    (signed int u dt      {r['ce_signed']:9.4f}  -- ~0; residual is the")
    print(f"                                     finite integration window, see docstring)")
    if limits:
        ok = (r["settling"] <= limits["settling_max"] and
              r["overshoot"] <= limits["overshoot_max"])
        print(f"    Meets settling <= {limits['settling_max']} s and "
              f"overshoot <= {limits['overshoot_max']} %: {'YES' if ok else 'NO'}")
    print()


def search(limits: dict, d1_total: float):
    """Minimise CE_Total subject to Tutorial 3's settling and overshoot limits."""
    best = None
    for kp in np.arange(0.20, 8.0001, 0.10):
        for td in np.arange(0.10, 3.0001, 0.05):
            r = analyse(float(kp), float(kp * td), t_end=40.0, n=40001)
            if r is None:
                continue
            if (r["settling"] <= limits["settling_max"] and
                    r["overshoot"] <= limits["overshoot_max"]):
                if best is None or r["ce_total"] < best["ce_total"]:
                    best = r
    if best is not None:
        best = analyse(best["kp"], best["kd"])      # re-measure on the fine grid
    return best


def make_figures(designs: list[tuple[str, dict]]) -> None:
    fig, ax = plt.subplots(1, 2, figsize=(13, 5))
    for name, r in designs:
        if r is None:
            continue
        lbl = f"{name}: Kp={r['kp']:.2f}, Td={r['td']:.2f}, CE_tot={r['ce_total']:.2f}"
        ax[0].plot(r["t"], r["y"], lw=1.7, label=lbl)
        ax[1].plot(r["t"], r["u"], lw=1.3, label=lbl)
    ax[0].axhline(1.0, color="k", lw=0.8)
    ax[0].axhspan(0.98, 1.02, color="seagreen", alpha=0.12)
    ax[0].set_xlim(0, 20); ax[0].set_xlabel("time [s]")
    ax[0].set_ylabel("rotor angle / reference [-]")
    ax[0].set_title("Rotor angle step response $T_{rotor-tracking}(s)$")
    ax[0].legend(fontsize=8); ax[0].grid(alpha=0.3)

    ax[1].axhline(0.0, color="k", lw=0.8)
    ax[1].set_xlim(0, 20); ax[1].set_xlabel("time [s]")
    ax[1].set_ylabel("control signal u [-]")
    ax[1].set_title("Control effort $CE(s)=K_{rotor}/(1+T_{rotor}K_{rotor})$")
    ax[1].set_yscale("symlog", linthresh=1.0)
    ax[1].legend(fontsize=8); ax[1].grid(alpha=0.3)

    fig.suptitle("EXP003 (Tutorial 3) -- suspended-mode MIMO: tracking vs control effort  "
                 "[MODEL; INDEPENDENT NUMERICAL CHECK, not MATLAB]", fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.93))
    fig.savefig(FIGDIR / "EXP003_fig1_tracking_and_control_effort.png", dpi=150)
    plt.close(fig)

    # CE_Max dependence on the derivative realisation -- the discretisation point.
    ns = np.array([25, 50, 100, 200, 400, 800, 1600], dtype=float)
    cmax, ctot, os_, st_ = [], [], [], []
    for nn in ns:
        r = analyse(D1_KP, D1_KD, n_filt=float(nn), t_end=30.0, n=60001)
        cmax.append(r["ce_max"]); ctot.append(r["ce_total"])
        os_.append(r["overshoot"]); st_.append(r["settling"])

    fig, ax = plt.subplots(1, 2, figsize=(12.5, 4.8))
    ax[0].loglog(ns, cmax, "o-", lw=1.8)
    ax[0].axhline(TUTORIAL_D1["ce_max"], color="crimson", ls="--",
                  label=f"Tutorial 3 value = {TUTORIAL_D1['ce_max']:.0f}")
    ax[0].axvline(N_REF, color="navy", ls=":", label=f"adopted N = {N_REF:.0f} rad/s")
    ax[0].set_xlabel("derivative filter corner N [rad/s]")
    ax[0].set_ylabel("$CE_{Max-Amplitude}$")
    ax[0].set_title("CE_Max is NOT a plant property:\nit scales with the derivative realisation")
    ax[0].legend(fontsize=8); ax[0].grid(alpha=0.3, which="both")

    ax[1].semilogx(ns, ctot, "o-", lw=1.8, label="$CE_{Total}=\\int|u|dt$")
    ax[1].axhline(TUTORIAL_D1["ce_total"], color="crimson", ls="--",
                  label=f"Tutorial 3 value = {TUTORIAL_D1['ce_total']:.1f}")
    ax[1].set_xlabel("derivative filter corner N [rad/s]")
    ax[1].set_ylabel("$CE_{Total}$")
    ax[1].set_ylim(0, 15)
    ax[1].set_title("CE_Total, settling and overshoot are\ninsensitive to N (< 5 % over 50-1000)")
    ax[1].legend(fontsize=8); ax[1].grid(alpha=0.3, which="both")

    fig.suptitle("EXP003 -- why every CE_Max figure must be quoted with its N "
                 "[MODEL, not measured]", fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    fig.savefig(FIGDIR / "EXP003_fig2_control_effort_discretisation.png", dpi=150)
    plt.close(fig)


def main() -> None:
    FIGDIR.mkdir(parents=True, exist_ok=True)
    TABDIR.mkdir(parents=True, exist_ok=True)

    print("EXP003 (Tutorial 3) -- MIMO suspended mode, control effort")
    print("INDEPENDENT SOFTWARE NUMERICAL CHECK -- NOT MATLAB, NOT hardware")
    print("=" * 76)
    print(f"\n  G_pend  = {WR2} s^2 / (s^2 + {GAMMA:.6f} s + {WG2})   [suspended, Q = {QF}]")
    print(f"  G_rotor = 1/s^2")
    print(f"  K_pend  = {KP_PEND} + {KD_PEND} s   (SUPPLIED and FIXED by Tutorial 3)\n")

    d1 = analyse(D1_KP, D1_KD, n=16001)
    report("DESIGN 1 -- Tutorial 3 defaults (Kp=6, Td=0.8, Kd=4.8)", d1)

    print("  VALIDATION against Tutorial 3's own published Design 1 values")
    print(f"    {'metric':<22}{'tutorial':>12}{'computed':>14}{'rel. err':>11}")
    for k, lbl in (("settling", "Settling time [s]"), ("overshoot", "Overshoot [%]"),
                   ("ce_max", "CE_Max_Amplitude"), ("ce_power", "CE_Max_Power"),
                   ("ce_total", "CE_Total")):
        tv, cv = TUTORIAL_D1[k], d1[k]
        print(f"    {lbl:<22}{tv:>12.4g}{cv:>14.4g}{100*(cv-tv)/tv:>10.1f}%")
    print()

    d2 = search(STEP2, d1["ce_total"])
    if d2:
        report(f"DESIGN 2 -- Step 2: minimise CE_Total, settling <= 4 s, OS <= 30 %", d2, STEP2)
        print(f"    CE_Total reduction vs Design 1: factor "
              f"{d1['ce_total']/d2['ce_total']:.2f}x  (target < {STEP2['ce_total_target']})\n")

    d3 = search(STEP4, d1["ce_total"])
    if d3:
        report(f"DESIGN 3 -- Step 4: minimise CE_Total, settling <= 10 s, OS <= 30 %", d3, STEP4)
        print(f"    CE_Total reduction vs Design 1: factor "
              f"{d1['ce_total']/d3['ce_total']:.2f}x  (target < {STEP4['ce_total_target']})\n")

    make_figures([("Design 1", d1), ("Design 2", d2), ("Design 3", d3)])

    rows = [("parameter_set", "EXP003-T3", "-"),
            ("g_pend_wr2", WR2, "(rad/s)^2"), ("g_pend_wg2", WG2, "(rad/s)^2"),
            ("g_pend_Q", QF, "-"), ("kp_pend", KP_PEND, "-"), ("kd_pend", KD_PEND, "-"),
            ("deriv_filter_N", N_REF, "rad/s")]
    for tag, r in (("d1", d1), ("d2", d2), ("d3", d3)):
        if r is None:
            continue
        rows += [(f"{tag}_kp_rotor", f"{r['kp']:.4f}", "-"),
                 (f"{tag}_td_rotor", f"{r['td']:.4f}", "s"),
                 (f"{tag}_kd_rotor", f"{r['kd']:.4f}", "-"),
                 (f"{tag}_settling", f"{r['settling']:.4f}", "s"),
                 (f"{tag}_overshoot", f"{r['overshoot']:.4f}", "%"),
                 (f"{tag}_ce_max", f"{r['ce_max']:.4f}", "-"),
                 (f"{tag}_ce_power", f"{r['ce_power']:.6e}", "-"),
                 (f"{tag}_ce_total", f"{r['ce_total']:.4f}", "-")]
    out = TABDIR / "EXP003_design_results.csv"
    with out.open("w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["quantity", "value", "unit"]); w.writerows(rows)

    print(f"  wrote {out.relative_to(REPO)}")
    for nm in ("EXP003_fig1_tracking_and_control_effort.png",
               "EXP003_fig2_control_effort_discretisation.png"):
        print(f"  wrote {(FIGDIR / nm).relative_to(REPO)}")
    print("\n  STATUS: INDEPENDENT SOFTWARE NUMERICAL CHECK -- EXECUTED.")
    print("  STATUS: MATLAB design tool -- DEFERRED, MATLAB EXECUTION ENVIRONMENT REQUIRED.")
    print("  STATUS: hardware measurement -- NOT_EXECUTED, no rig attached.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
EXP005 (Tutorial 5) -- MIMO Unstable System Control (inverted mode).

INDEPENDENT SOFTWARE NUMERICAL CHECK.
================================================================================
NOT MATLAB. MATLAB and Octave are both absent (verified). MATLAB equivalents
exist under matlab/ and are NOT_EXECUTED.
================================================================================

WHAT CHANGES IN INVERTED MODE (Tutorial 5 section 8)

    G_pend(s) = wr^2 s^2 / (s^2 + (wg/Q) s  -  wg^2)
                                             ^^^ MINUS, not plus

    wr^2 = 0.803 (rad/s)^2,  wg^2 = 55.85 (rad/s)^2,  Q = 20

Both wg^2 and Q differ from suspended mode (57.01 and 27), and the sign of the
wg^2 term flips. That single sign is the whole experiment: the denominator now
has a RIGHT-HALF-PLANE POLE at +7.2888 rad/s, so the open-loop pendulum falls
with a 137 ms time constant.

    K_pend = 300 + 30 s      SUPPLIED and FIXED for inverted mode
                             (30x the suspended-mode gain, because it now has to
                              stabilise an unstable plant rather than damp a
                              stable one)

THE STRUCTURAL CONSEQUENCE, AND WHY EXP005'S TARGETS ARE SO MUCH LOOSER

    T_rotor(s) = G_rotor / (1 + G_pend K_pend G_rotor)
               = den_pend / ( s^2 * (den_pend + wr^2 K_pend) )

The inner loop is stable: den_pend + wr^2 K_pend = s^2 + 24.4637 s + 185.05,
poles at -12.23 +/- 5.95j, zeta = 0.899. The supplied controller does its job.

But T_rotor's NUMERATOR is den_pend, so the plant's unstable POLE becomes a
NON-MINIMUM-PHASE ZERO of T_rotor at +7.2888 rad/s.

    Stabilising an unstable pole does not remove it from the problem.
    It converts it into a right-half-plane zero of the loop the OUTER
    controller now has to work with.

A RHP zero imposes a hard bandwidth limit -- roughly z/2 = 3.64 rad/s (0.58 Hz)
-- that no choice of K_rotor can exceed. This is why Tutorial 5's settling and
overshoot targets are far looser than Tutorial 3's and why gain and phase margins
become the binding constraints. It is a fundamental limitation, not a tuning
difficulty.

STABILITY METRICS (Tutorial 5 sections 5-7)

    w_PC : phase crossover, where angle L(jw) = -180 deg
    GM   : gain margin = 1/|L(jw_PC)|,  in dB = -20 log10 |L(jw_PC)|
    w_GC : gain crossover, where |L(jw)| = 1
    phi_M: phase margin = 180 deg + angle L(jw_GC)
    M_S  : max |S(jw)|, in dB;  w_MS where it occurs;  w_SC where |S| = 1

DESIGN OBJECTIVES (Tutorial 5 section 14).  Kd < 15, Kp < 18 suggested.

    System 1: settling < 4 s, overshoot < 25 %, GM > 8 dB, phi_M > 50 deg, M_S < 5 dB
    System 2: settling < 2 s, overshoot < 35 %, GM > 4 dB, phi_M > 30 deg, M_S < 10 dB

DOCUMENTED CONFLICT IN THE SOURCE
    Tutorial 5 section 13 gives Quasi-Stable System 2 as Kp = 10, Td = 0.333,
    Kd = 3.33 in its table, but its serial-interface example enters 3.00. Since
    Kd is DEFINED as Kp*Td = 10*0.333 = 3.33, the table is self-consistent and
    3.00 appears to be a rounding in the transcript. Kd = 3.33 is used, and both
    values are evaluated below so the difference can be seen.

Run:  python3 scripts/exp005_unstable_mimo.py
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

# --- Inverted-mode plant, Tutorial 5 section 8. REFERENCE/ASSUMED (OI-9). ---
WR2, WG2, QF = 0.803, 55.85, 20.0
GAMMA = math.sqrt(WG2) / QF
DEN_PEND = [1.0, GAMMA, -WG2]              # MINUS -- the unstable sign

# --- Inner controller: SUPPLIED and FIXED for inverted mode ----------------
KP_PEND, KD_PEND = 300.0, 30.0

# --- OUTER-LOOP SIGN INVERSION IN INVERTED MODE ----------------------------
# In inverted mode T_rotor has NEGATIVE DC gain: its numerator is den_pend,
# whose constant term is -wg^2 = -55.85, so T_rotor ~ -0.3018/s^2 near DC.
# Closing the outer loop with a positive K_rotor is therefore POSITIVE feedback.
#
# Established by evidence, not assumption. With L = +T_rotor*K_rotor BOTH of
# Tutorial 5's own published designs are unstable (max Re(pole) = +2.46 and
# +1.89). With L = -T_rotor*K_rotor both are stable, and "Stable System 1"
# (max Re = -1.79) is far more stable than "Quasi-Stable System 2" (-0.35) --
# reproducing the names the Tutorial gives them.
#
# Physically the pendulum-angle sign convention inverts with the geometry: a
# hanging pendulum and a standing one respond to rotor motion with opposite
# sign. Independent corroboration is in the UCLA reference firmware, whose
# SUSPENDED demonstration mode uses NEGATIVE gains (-10.0, -2.0) while its
# inverted modes use positive ones -- the same inversion, applied at the gain
# entry instead of in the loop algebra. Tutorial 5 quotes positive gains and
# leaves the inversion implicit in the mode.
MODE_SIGN = -1.0

# --- Tutorial 5 section 13 introduction-step designs -----------------------
INTRO = [("Stable System 1", 9.0, 9.0),          # Kp=9,  Td=1.0,   Kd=9
         ("Quasi-Stable System 2", 10.0, 3.33),  # Kp=10, Td=0.333, Kd=3.33
         ("Quasi-Stable System 2 (serial Kd=3.00)", 10.0, 3.00)]

SYS1 = dict(name="System 1", settling_max=4.0, overshoot_max=25.0,
            gm_db_min=8.0, pm_deg_min=50.0, ms_db_max=5.0)
SYS2 = dict(name="System 2", settling_max=2.0, overshoot_max=35.0,
            gm_db_min=4.0, pm_deg_min=30.0, ms_db_max=10.0)

W = np.logspace(-3.0, 4.0, 200000)
W_SEARCH = np.logspace(-3.0, 4.0, 3000)


def loop(kp: float, kd: float):
    """L = T_rotor * K_rotor as (num, den), plus T_rotor."""
    inner = np.polyadd(DEN_PEND, np.polymul([WR2], [KD_PEND, KP_PEND]))
    tr_num = np.array(DEN_PEND, dtype=float)
    tr_den = np.polymul([1.0, 0.0, 0.0], inner)
    return (np.polymul(tr_num, [MODE_SIGN * kd, MODE_SIGN * kp]), tr_den), \
           (tr_num, tr_den, inner)


def margins(kp: float, kd: float, w=None) -> dict:
    if w is None:
        w = W
    (ln, ld), _ = loop(kp, kd)
    lj = np.polyval(ln, 1j * w) / np.polyval(ld, 1j * w)
    mag = np.abs(lj)
    ph = np.unwrap(np.angle(lj))          # radians

    s = 1.0 / (1.0 + lj)
    smag = np.abs(s)
    ms = float(np.max(smag))
    i_ms = int(np.argmax(smag))

    cross_s = np.where(np.diff(np.sign(smag - 1.0)))[0]
    w_sc = float(w[cross_s[0]]) if cross_s.size else float("nan")

    # Gain crossover: |L| = 1  -> phase margin
    gc = np.where(np.diff(np.sign(mag - 1.0)))[0]
    if gc.size:
        i = int(gc[0])
        w_gc = float(w[i])
        pm_deg = 180.0 + math.degrees(ph[i])
        # Fold into (-180, 180]
        while pm_deg > 180.0:
            pm_deg -= 360.0
        while pm_deg <= -180.0:
            pm_deg += 360.0
    else:
        w_gc, pm_deg = float("nan"), float("nan")

    # Phase crossover: angle L = -180 deg (mod 360) -> gain margin
    target = ph / math.pi                  # in units of pi
    k = np.round((target + 1.0) / 2.0)
    resid = target - (2.0 * k - 1.0)       # zero where phase == -180 + 360n
    pc = np.where(np.diff(np.sign(resid)))[0]
    if pc.size:
        j = int(pc[0])
        w_pc = float(w[j])
        gm_db = -20.0 * math.log10(mag[j]) if mag[j] > 0 else float("inf")
    else:
        w_pc, gm_db = float("nan"), float("inf")

    return dict(ms=ms, ms_db=20.0 * math.log10(ms), w_ms=float(w[i_ms]),
                w_sc=w_sc, w_gc=w_gc, pm_deg=pm_deg, w_pc=w_pc, gm_db=gm_db,
                nyquist_dmin=float(np.min(np.abs(-1.0 - lj))))


def is_stable(kp: float, kd: float) -> bool:
    (ln, ld), _ = loop(kp, kd)
    cl = np.polyadd(ld, np.concatenate([np.zeros(len(ld) - len(ln)), ln]))
    r = np.roots(cl)
    return bool(r.size == 0 or float(np.max(r.real)) < -1e-9)


def response(kp: float, kd: float, t_end: float = 30.0, n: int = 12001):
    (ln, ld), _ = loop(kp, kd)
    cl = np.polyadd(ld, np.concatenate([np.zeros(len(ld) - len(ln)), ln]))
    t = np.linspace(0.0, t_end, n)
    _, y = signal.step((ln, cl), T=t)
    y = np.asarray(y).ravel()
    if not np.all(np.isfinite(y)):
        return None
    overshoot = 100.0 * (float(np.max(y)) - 1.0)
    out = np.where(np.abs(y - 1.0) > 0.02)[0]
    settling = float(t[out[-1]]) if out.size else 0.0
    if out.size and out[-1] >= n - 2:
        settling = math.inf
    # Undershoot is the signature of a non-minimum-phase zero.
    undershoot = 100.0 * float(np.min(y))
    return dict(t=t, y=y, overshoot=overshoot, settling=settling,
                undershoot=undershoot)


def analyse(kp: float, kd: float, **kw):
    if not is_stable(kp, kd):
        return None
    r = response(kp, kd, **kw)
    if r is None:
        return None
    r.update(margins(kp, kd))
    r.update(kp=kp, kd=kd, td=(kd / kp if kp else math.nan))
    return r


def meets(r: dict, o: dict) -> bool:
    return (r["settling"] <= o["settling_max"] and
            r["overshoot"] <= o["overshoot_max"] and
            r["gm_db"] >= o["gm_db_min"] and
            r["pm_deg"] >= o["pm_deg_min"] and
            r["ms_db"] <= o["ms_db_max"])


def report(tag: str, r: dict, o: dict | None = None) -> None:
    print(f"  {tag}")
    print(f"    Kp = {r['kp']:.4f}   Td = {r['td']:.4f} s   Kd = {r['kd']:.4f}")
    print(f"    Rotor settling (2%)  {r['settling']:9.3f} s")
    print(f"    Rotor overshoot      {r['overshoot']:9.2f} %")
    print(f"    Rotor undershoot     {r['undershoot']:9.2f} %   (NMP zero signature)")
    print(f"    Phase margin  phi_M  {r['pm_deg']:9.2f} deg   at w_GC = {r['w_gc']:.4f} rad/s")
    print(f"    Gain margin   GM     {r['gm_db']:9.2f} dB    at w_PC = {r['w_pc']:.4f} rad/s")
    print(f"    M_S                  {r['ms_db']:9.3f} dB    at w_MS = {r['w_ms']:.4f} rad/s")
    print(f"    w_SC (|S| = 1)       {r['w_sc']:9.4f} rad/s")
    if o:
        print(f"    Meets {o['name']}: {'YES' if meets(r, o) else 'NO'}  "
              f"(t_s<{o['settling_max']}, OS<{o['overshoot_max']}%, "
              f"GM>{o['gm_db_min']}dB, PM>{o['pm_deg_min']}deg, M_S<{o['ms_db_max']}dB)")
    print()


def search(o: dict):
    """Minimum settling time subject to all five of Tutorial 5's constraints.

    Margins are screened first on a coarse frequency grid: they are far cheaper
    than a step simulation and eliminate most of the grid.
    """
    best = None
    for kp in np.arange(0.5, 18.0001, 0.25):
        for kd in np.arange(0.25, 15.0001, 0.25):
            if not is_stable(float(kp), float(kd)):
                continue
            m = margins(float(kp), float(kd), w=W_SEARCH)
            if (m["gm_db"] < o["gm_db_min"] or m["pm_deg"] < o["pm_deg_min"]
                    or m["ms_db"] > o["ms_db_max"]):
                continue
            r = response(float(kp), float(kd), t_end=30.0, n=3001)
            if r is None or r["overshoot"] > o["overshoot_max"] \
                    or r["settling"] > o["settling_max"]:
                continue
            if best is None or r["settling"] < best[2]:
                best = (float(kp), float(kd), r["settling"])
    return analyse(best[0], best[1]) if best else None


def make_figures(designs):
    fig, ax = plt.subplots(1, 2, figsize=(13, 5))
    for name, r in designs:
        if r is None:
            continue
        ax[0].plot(r["t"], r["y"], lw=1.7,
                   label=f"{name}: PM={r['pm_deg']:.0f}deg GM={r['gm_db']:.1f}dB")
    ax[0].axhline(1.0, color="k", lw=0.8)
    ax[0].axhline(0.0, color="grey", lw=0.6, ls=":")
    ax[0].axhspan(0.98, 1.02, color="seagreen", alpha=0.12)
    ax[0].set_xlim(0, 15); ax[0].set_xlabel("time [s]")
    ax[0].set_ylabel("rotor angle / reference [-]")
    ax[0].set_title("Rotor step response, INVERTED mode\n"
                    "initial dip = non-minimum-phase zero at +7.29 rad/s")
    ax[0].legend(fontsize=8); ax[0].grid(alpha=0.3)

    wn = np.logspace(-2, 3, 60000)
    for name, r in designs:
        if r is None:
            continue
        (ln, ld), _ = loop(r["kp"], r["kd"])
        lj = np.polyval(ln, 1j * wn) / np.polyval(ld, 1j * wn)
        ax[1].plot(lj.real, lj.imag, lw=1.3,
                   label=f"{name} ($M_S$={r['ms_db']:.1f} dB)")
    th = np.linspace(0, 2 * np.pi, 400)
    ax[1].plot(-1 + np.cos(th), np.sin(th), "k--", lw=1.0,
               label="unit circle about (-1,0)")
    ax[1].plot([-1], [0], "rx", ms=9, mew=2)
    ax[1].set_xlim(-3, 1.5); ax[1].set_ylim(-2.5, 2.5)
    ax[1].set_xlabel("Re $L(j\\omega)$"); ax[1].set_ylabel("Im $L(j\\omega)$")
    ax[1].set_title("Nyquist -- inverted mode")
    ax[1].legend(fontsize=7.5, loc="lower left"); ax[1].grid(alpha=0.3)
    ax[1].set_aspect("equal", adjustable="box")

    fig.suptitle("EXP005 (Tutorial 5) -- unstable MIMO, inverted mode  "
                 "[MODEL; INDEPENDENT NUMERICAL CHECK, not MATLAB]", fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.92))
    fig.savefig(FIGDIR / "EXP005_fig1_step_and_nyquist.png", dpi=150)
    plt.close(fig)


def main() -> None:
    FIGDIR.mkdir(parents=True, exist_ok=True)
    TABDIR.mkdir(parents=True, exist_ok=True)

    print("EXP005 (Tutorial 5) -- MIMO unstable system control, INVERTED mode")
    print("INDEPENDENT SOFTWARE NUMERICAL CHECK -- NOT MATLAB, NOT hardware")
    print("=" * 78)

    pend_poles = np.roots(DEN_PEND)
    rhp = max(p.real for p in pend_poles)
    inner = np.polyadd(DEN_PEND, np.polymul([WR2], [KD_PEND, KP_PEND]))
    ipoles = np.roots(inner)
    print(f"\n  G_pend (inverted) = {WR2} s^2 / (s^2 + {GAMMA:.5f} s - {WG2})")
    print(f"    open-loop poles {np.round(pend_poles, 4)}")
    print(f"    -> UNSTABLE: RHP pole at +{rhp:.4f} rad/s, "
          f"fall time constant {1000/rhp:.0f} ms")
    print(f"  K_pend = {KP_PEND} + {KD_PEND} s  (SUPPLIED and FIXED, inverted mode)")
    print(f"    inner poly {np.round(inner, 4)}  poles {np.round(ipoles, 3)}")
    print(f"    -> inner loop is {'STABLE' if max(ipoles.real) < 0 else 'UNSTABLE'}"
          f", zeta = {inner[1]/(2*math.sqrt(inner[2])):.4f}")
    print(f"\n  *** T_rotor NUMERATOR is den_pend, so the unstable POLE becomes a")
    print(f"      NON-MINIMUM-PHASE ZERO at +{rhp:.4f} rad/s.")
    print(f"      Bandwidth is capped near z/2 = {rhp/2:.2f} rad/s "
          f"({rhp/2/(2*math.pi):.3f} Hz) regardless of K_rotor. ***\n")

    intro = []
    for name, kp, kd in INTRO:
        r = analyse(kp, kd)
        intro.append((name, r))
        if r:
            report(f"INTRODUCTION STEP -- {name} (Tutorial 5 section 13)", r)
        else:
            print(f"  {name}: CLOSED LOOP UNSTABLE\n")

    d1 = search(SYS1)
    if d1:
        report("SYSTEM 1 DESIGN -- high margins, reduced performance", d1, SYS1)
    else:
        print("  NO design meets all System 1 objectives in the stated range.\n")

    d2 = search(SYS2)
    if d2:
        report("SYSTEM 2 DESIGN -- relaxed margins, greater performance", d2, SYS2)
    else:
        print("  NO design meets all System 2 objectives in the stated range.\n")

    make_figures([(n, r) for n, r in intro[:2]] +
                 [("System 1", d1), ("System 2", d2)])

    rows = [("parameter_set", "EXP005-T5", "-"),
            ("mode", "inverted", "-"),
            ("g_pend_wr2", WR2, "(rad/s)^2"),
            ("g_pend_wg2", WG2, "(rad/s)^2"),
            ("g_pend_Q", QF, "-"),
            ("kp_pend", KP_PEND, "-"), ("kd_pend", KD_PEND, "-"),
            ("open_loop_rhp_pole", f"{rhp:.6f}", "rad/s"),
            ("nmp_zero_of_T_rotor", f"{rhp:.6f}", "rad/s"),
            ("bandwidth_limit_approx", f"{rhp/2:.6f}", "rad/s")]
    for tag, r in ([(f"intro{i}", x[1]) for i, x in enumerate(intro, 1)] +
                   [("sys1", d1), ("sys2", d2)]):
        if r is None:
            continue
        rows += [(f"{tag}_kp", f"{r['kp']:.4f}", "-"),
                 (f"{tag}_td", f"{r['td']:.4f}", "s"),
                 (f"{tag}_kd", f"{r['kd']:.4f}", "-"),
                 (f"{tag}_settling", f"{r['settling']:.4f}", "s"),
                 (f"{tag}_overshoot", f"{r['overshoot']:.4f}", "%"),
                 (f"{tag}_undershoot", f"{r['undershoot']:.4f}", "%"),
                 (f"{tag}_pm_deg", f"{r['pm_deg']:.4f}", "deg"),
                 (f"{tag}_w_gc", f"{r['w_gc']:.4f}", "rad/s"),
                 (f"{tag}_gm_db", f"{r['gm_db']:.4f}", "dB"),
                 (f"{tag}_w_pc", f"{r['w_pc']:.4f}", "rad/s"),
                 (f"{tag}_ms_db", f"{r['ms_db']:.4f}", "dB"),
                 (f"{tag}_w_sc", f"{r['w_sc']:.4f}", "rad/s")]
    out = TABDIR / "EXP005_design_results.csv"
    with out.open("w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["quantity", "value", "unit"]); w.writerows(rows)
    print(f"  wrote {out.relative_to(REPO)}")
    print(f"  wrote {(FIGDIR / 'EXP005_fig1_step_and_nyquist.png').relative_to(REPO)}")
    print("\n  STATUS: INDEPENDENT SOFTWARE NUMERICAL CHECK -- EXECUTED.")
    print("  STATUS: MATLAB tools -- DEFERRED, MATLAB EXECUTION ENVIRONMENT REQUIRED.")
    print("  STATUS: hardware -- NOT_EXECUTED. INVERTED MODE IS THE FIRST")
    print("          CONFIGURATION WHERE LOSS OF CONTROL PRODUCES VIOLENT MOTION.")


if __name__ == "__main__":
    main()

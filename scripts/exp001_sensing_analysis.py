#!/usr/bin/env python3
"""
EXP001 sensing- and actuation-chain numerical analysis.

WHAT THIS IS
------------
This script evaluates and independently cross-checks the ANALYTIC results of
experiments/EXP001/FIRST_PRINCIPLES.md. Everything it computes is a property of
the *measurement and command algorithms* -- quantisation, differentiation noise,
timer arithmetic -- and is therefore fully determined by the parameter set. None
of it depends on the physical rig.

WHAT THIS IS NOT
----------------
This is NOT a substitute for the MATLAB control-model work, which is DEFERRED
(no MATLAB or Octave on this machine). It contains no plant model, no dynamics,
and no controller. It produces no experimental measurements. Every figure it
draws is a statement about arithmetic, and each figure legend says so.

Run:  python3 scripts/exp001_sensing_analysis.py
Out:  results/figures/EXP001_*.png, results/tables/EXP001_sensing_analysis.csv
"""

from __future__ import annotations

import csv
import math
from pathlib import Path

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

# --- Repository-relative paths. Never absolute; the repo must be portable. ---
REPO = Path(__file__).resolve().parent.parent
FIGDIR = REPO / "results" / "figures"
TABDIR = REPO / "results" / "tables"

# --- Parameter set PS-EDUKIT01-v1 -------------------------------------------
PARAM_SET = "PS-EDUKIT01-v1"
ENCODER_PPR = 600
DECODE_X = 4
COUNTS_PER_REV = ENCODER_PPR * DECODE_X          # 2400
Q_RAD = 2.0 * math.pi / COUNTS_PER_REV           # 2.617994e-3 rad
TS = 0.002                                       # s
FS = 1.0 / TS                                    # 500 Hz

MICROSTEPS_PER_REV = 200 * 16                    # 3200
RAD_PER_USTEP = 2.0 * math.pi / MICROSTEPS_PER_REV

SYSCLK = 84_000_000.0
STEP_PRESCALER = 1024.0
TICK_HZ = SYSCLK / STEP_PRESCALER                # 82031.25 Hz exactly

RNG = np.random.default_rng(20260819)


# ---------------------------------------------------------------------------
# Analytic results (equations 11-14)
# ---------------------------------------------------------------------------
def analytic_results() -> dict:
    sigma_theta = Q_RAD / math.sqrt(12.0)
    return {
        "q_rad": Q_RAD,
        "q_deg": 360.0 / COUNTS_PER_REV,
        "sigma_theta_rad": sigma_theta,
        "sigma_theta_deg": math.degrees(sigma_theta),
        "vel_granularity_rad_s": Q_RAD / TS,
        "vel_granularity_deg_s": (360.0 / COUNTS_PER_REV) / TS,
        "sigma_omega_rad_s": sigma_theta * math.sqrt(2.0) / TS,
        "sigma_omega_deg_s": math.degrees(sigma_theta * math.sqrt(2.0) / TS),
        "alias_limit_rev_s": (2 ** 15) / COUNTS_PER_REV / TS,
    }


def monte_carlo_check(n: int = 4_000_000) -> dict:
    """Independent numerical confirmation of equations (11) and (14).

    The analytic sigma values assume the quantisation residual is uniform on
    [-q/2, q/2] and that consecutive residuals are independent. Both assumptions
    are worth checking rather than asserting: simulate a genuinely random angle
    trajectory, quantise it, difference it, and measure the resulting spread.
    """
    # A random-walk angle whose per-sample increment is large compared with q,
    # so successive quantisation residuals really are near-independent.
    steps = RNG.normal(0.0, 50.0 * Q_RAD, size=n)
    theta = np.cumsum(steps)

    counts = np.round(theta / Q_RAD)
    theta_q = counts * Q_RAD
    resid = theta_q - theta

    omega_true = np.diff(theta) / TS
    omega_est = np.diff(theta_q) / TS
    omega_err = omega_est - omega_true

    return {
        "mc_sigma_theta_rad": float(np.std(resid)),
        "mc_sigma_omega_rad_s": float(np.std(omega_err)),
        "mc_mean_resid_rad": float(np.mean(resid)),
    }


# ---------------------------------------------------------------------------
# Figure 1 -- what quantisation does to a slow signal
# ---------------------------------------------------------------------------
def fig_quantisation_effect() -> None:
    """Question: at a pendulum speed typical of near-equilibrium operation, how
    does the raw backward-difference velocity estimate compare with the truth?"""
    t = np.arange(0.0, 2.0, TS)
    amp, f0 = math.radians(5.0), 0.5           # +/-5 deg at 0.5 Hz: slow, small
    theta = amp * np.sin(2 * math.pi * f0 * t)
    omega_true = amp * 2 * math.pi * f0 * np.cos(2 * math.pi * f0 * t)

    theta_q = np.round(theta / Q_RAD) * Q_RAD
    omega_est = np.concatenate(([0.0], np.diff(theta_q) / TS))

    fig, ax = plt.subplots(2, 1, figsize=(10, 7), sharex=True)

    ax[0].plot(t, np.degrees(theta), lw=1.6, label="true angle")
    ax[0].step(t, np.degrees(theta_q), where="post", lw=1.0, alpha=0.85,
               label=f"quantised ({360/COUNTS_PER_REV:.3f} deg/count)")
    ax[0].set_ylabel("pendulum angle [deg]")
    ax[0].legend(loc="upper right")
    ax[0].grid(alpha=0.3)
    ax[0].set_title("EXP001 Fig.1 -- Quantisation of a slow, small-amplitude motion\n"
                    "5 deg amplitude, 0.5 Hz, 2400 counts/rev, Ts = 2 ms "
                    "(ALGORITHMIC, not measured)")

    ax[1].plot(t, omega_true, lw=1.8, label="true angular velocity")
    ax[1].step(t, omega_est, where="post", lw=0.9, alpha=0.8,
               label="raw backward difference")
    gran = Q_RAD / TS
    for k in (-2, -1, 0, 1, 2):
        ax[1].axhline(k * gran, color="grey", ls=":", lw=0.7)
    ax[1].set_ylabel("angular velocity [rad/s]")
    ax[1].set_xlabel("time [s]")
    ax[1].legend(loc="upper right")
    ax[1].grid(alpha=0.3)
    ax[1].text(0.02, 0.04,
               f"dotted lines: integer multiples of q/Ts = {gran:.3f} rad/s\n"
               "the estimate can take no other value",
               transform=ax[1].transAxes, fontsize=9,
               bbox=dict(fc="white", alpha=0.75, ec="grey"))

    fig.tight_layout()
    fig.savefig(FIGDIR / "EXP001_fig1_quantisation_effect.png", dpi=150)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Figure 2 -- the design trade-off
# ---------------------------------------------------------------------------
def fig_velocity_noise_tradeoff() -> None:
    """Question: which lever actually reduces differentiation noise -- sampling
    faster, or resolving finer? Equation (14) says sigma ~ q/Ts, so the answer
    is counter-intuitive and worth drawing."""
    rates = np.array([100, 200, 250, 333, 500, 1000, 2000], dtype=float)
    fig, ax = plt.subplots(1, 2, figsize=(12, 5))

    for decode, label in ((1, "X1 (600 c/rev)"),
                          (2, "X2 (1200 c/rev)"),
                          (4, "X4 (2400 c/rev)")):
        q = 2 * math.pi / (ENCODER_PPR * decode)
        sigma = (q / math.sqrt(12)) * math.sqrt(2) * rates
        ax[0].plot(rates, sigma, "o-", label=label)

    ax[0].axvline(FS, color="crimson", ls="--", lw=1.2)
    ax[0].text(FS * 1.05, ax[0].get_ylim()[1] * 0.5, "this rig\n500 Hz",
               color="crimson", fontsize=9)
    ax[0].set_xscale("log")
    ax[0].set_yscale("log")
    ax[0].set_xlabel("sample rate [Hz]")
    ax[0].set_ylabel(r"$\sigma_\omega$  [rad/s]")
    ax[0].set_title("Differentiation noise rises linearly with sample rate")
    ax[0].legend()
    ax[0].grid(alpha=0.3, which="both")

    # Effect of a first-order low-pass on the derivative.
    fcs = np.logspace(0, 2.4, 60)                    # 1 .. 250 Hz
    sigma_raw = (Q_RAD / math.sqrt(12)) * math.sqrt(2) / TS
    alpha = 1.0 - np.exp(-2 * math.pi * fcs * TS)
    # Steady-state noise gain of y[k] = y[k-1] + a*(u[k]-y[k-1]) is sqrt(a/(2-a)).
    sigma_filt = sigma_raw * np.sqrt(alpha / (2.0 - alpha))

    ax[1].plot(fcs, sigma_filt, lw=2, label="after 1st-order low-pass")
    ax[1].axhline(sigma_raw, color="crimson", ls="--", lw=1.2,
                  label=f"unfiltered = {sigma_raw:.3f} rad/s")
    ax[1].axvline(10.0, color="seagreen", ls=":", lw=1.5)
    idx = int(np.argmin(np.abs(fcs - 10.0)))
    ax[1].plot([10.0], [sigma_filt[idx]], "o", color="seagreen", ms=8)
    ax[1].annotate(f"reference project's 10 Hz\n-> {sigma_filt[idx]:.3f} rad/s",
                   xy=(10.0, sigma_filt[idx]), xytext=(14, sigma_raw * 0.55),
                   color="seagreen", fontsize=9,
                   arrowprops=dict(arrowstyle="->", color="seagreen"))
    ax[1].set_xscale("log")
    ax[1].set_xlabel("derivative low-pass corner frequency [Hz]")
    ax[1].set_ylabel(r"$\sigma_\omega$  [rad/s]")
    ax[1].set_title("Why the derivative filter is not optional")
    ax[1].legend(loc="upper left")
    ax[1].grid(alpha=0.3, which="both")

    fig.suptitle("EXP001 Fig.2 -- Velocity-estimation noise: design trade-offs "
                 "(ALGORITHMIC, not measured)", fontsize=12)
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    fig.savefig(FIGDIR / "EXP001_fig2_velocity_noise_tradeoff.png", dpi=150)
    plt.close(fig)


# ---------------------------------------------------------------------------
# Figure 3 -- actuator step-rate quantisation (prediction P5)
# ---------------------------------------------------------------------------
def fig_step_rate_quantisation() -> tuple[np.ndarray, np.ndarray]:
    """Question: over what range of commanded step rates is the achieved rate
    trustworthy? Equations (2)-(3)."""
    f_cmd = np.arange(50, 20001, 1, dtype=float)
    divisor = np.maximum(np.round(TICK_HZ / f_cmd), 1.0)
    f_act = TICK_HZ / divisor
    err_pct = 100.0 * (f_act - f_cmd) / f_cmd

    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.plot(f_cmd, err_pct, lw=1.0)
    ax.axhline(0, color="k", lw=0.8)
    ax.axhspan(-0.1, 0.1, color="seagreen", alpha=0.15,
               label="+/-0.1 % acceptance band")
    ax.axvline(1000, color="crimson", ls="--", lw=1.4,
               label="EXP001 rate cap = 1000 steps/s")
    ax.set_xscale("log")
    ax.set_xlabel("commanded step rate [steps/s]")
    ax.set_ylabel("achieved - commanded  [%]")
    ax.set_ylim(-4, 4)
    ax.set_title("EXP001 Fig.3 -- Step-rate quantisation from integer timer reload\n"
                 f"tick rate = {TICK_HZ:.2f} Hz, ARR = round(tick/f) - 1 "
                 "(ALGORITHMIC, not measured)")
    ax.legend()
    ax.grid(alpha=0.3, which="both")

    for f in (200, 1000, 2000, 10000):
        i = int(np.argmin(np.abs(f_cmd - f)))
        ax.annotate(f"{err_pct[i]:+.2f} %", xy=(f_cmd[i], err_pct[i]),
                    xytext=(0, 12 if err_pct[i] >= 0 else -18),
                    textcoords="offset points", ha="center", fontsize=9,
                    arrowprops=dict(arrowstyle="->", lw=0.8))

    fig.tight_layout()
    fig.savefig(FIGDIR / "EXP001_fig3_step_rate_quantisation.png", dpi=150)
    plt.close(fig)
    return f_cmd, err_pct


# ---------------------------------------------------------------------------
# Figure 4 -- wrap-safe decoding (hypothesis H4)
# ---------------------------------------------------------------------------
def fig_wrap_safety() -> None:
    """Question: does the modular-difference accumulator reconstruct the angle
    across 16-bit counter wraps, and what would the naive version do instead?"""
    n = 1200
    counts_per_sample = 120.0            # 18 deg/sample: absurdly fast, for effect
    truth = np.arange(n) * counts_per_sample
    raw = (truth.astype(np.int64) % 65536).astype(np.int64)

    # Naive: subtract raw origin. Breaks at every wrap.
    naive = raw - raw[0]

    # Wrap-safe: equation (8) then (9).
    d = np.diff(raw)
    d = ((d + 32768) % 65536) - 32768
    safe = np.concatenate(([0], np.cumsum(d)))

    t = np.arange(n) * TS
    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.plot(t, truth * 360.0 / COUNTS_PER_REV, lw=2.4, alpha=0.6,
            label="true angle")
    ax.plot(t, safe * 360.0 / COUNTS_PER_REV, lw=1.2, ls="--",
            label="wrap-safe accumulator (eq. 8-9)")
    ax.plot(t, naive * 360.0 / COUNTS_PER_REV, lw=1.0, alpha=0.8,
            label="naive raw difference")
    ax.set_xlabel("time [s]")
    ax.set_ylabel("pendulum angle [deg]")
    ax.set_title("EXP001 Fig.4 -- 16-bit counter wrap handling\n"
                 "wrap-safe curve overlies the truth exactly; naive curve "
                 "sawtooths (ALGORITHMIC, not measured)")
    ax.legend()
    ax.grid(alpha=0.3)

    max_err = float(np.max(np.abs(safe - truth)))
    ax.text(0.02, 0.95, f"max |wrap-safe - truth| = {max_err:.1f} counts",
            transform=ax.transAxes, va="top", fontsize=10,
            bbox=dict(fc="white", alpha=0.8, ec="grey"))

    fig.tight_layout()
    fig.savefig(FIGDIR / "EXP001_fig4_wrap_safety.png", dpi=150)
    plt.close(fig)
    assert max_err == 0.0, "wrap-safe accumulator must be exact"


# ---------------------------------------------------------------------------
def main() -> None:
    FIGDIR.mkdir(parents=True, exist_ok=True)
    TABDIR.mkdir(parents=True, exist_ok=True)

    res = analytic_results()
    mc = monte_carlo_check()

    print(f"EXP001 sensing/actuation analysis -- parameter set {PARAM_SET}")
    print("-" * 68)
    print(f"  encoder resolution q          = {res['q_rad']:.9e} rad "
          f"({res['q_deg']:.4f} deg/count)")
    print(f"  angle noise      sigma_theta  = {res['sigma_theta_rad']:.6e} rad "
          f"({res['sigma_theta_deg']:.5f} deg)      [eq. 11]")
    print(f"  velocity granularity  q/Ts    = {res['vel_granularity_rad_s']:.6f} rad/s "
          f"({res['vel_granularity_deg_s']:.1f} deg/s)  [eq. 13]")
    print(f"  velocity noise   sigma_omega  = {res['sigma_omega_rad_s']:.6f} rad/s "
          f"({res['sigma_omega_deg_s']:.2f} deg/s)   [eq. 14]")
    print(f"  aliasing threshold            = {res['alias_limit_rev_s']:.1f} rev/s "
          f"[eq. 10]")
    print()
    print("  Monte-Carlo cross-check (4e6 samples):")
    print(f"    sigma_theta  analytic {res['sigma_theta_rad']:.6e}  "
          f"simulated {mc['mc_sigma_theta_rad']:.6e}  "
          f"ratio {mc['mc_sigma_theta_rad']/res['sigma_theta_rad']:.4f}")
    print(f"    sigma_omega  analytic {res['sigma_omega_rad_s']:.6f}      "
          f"simulated {mc['mc_sigma_omega_rad_s']:.6f}      "
          f"ratio {mc['mc_sigma_omega_rad_s']/res['sigma_omega_rad_s']:.4f}")
    print(f"    mean residual (should be ~0) {mc['mc_mean_resid_rad']:.3e} rad")

    # The Monte-Carlo result must confirm the analytic one, or the derivation is
    # wrong. Tolerance is loose enough for sampling error, tight enough to catch
    # a factor-of-sqrt(2) or factor-of-2 mistake -- the errors that actually happen.
    assert abs(mc["mc_sigma_theta_rad"] / res["sigma_theta_rad"] - 1) < 0.02
    assert abs(mc["mc_sigma_omega_rad_s"] / res["sigma_omega_rad_s"] - 1) < 0.02

    fig_quantisation_effect()
    fig_velocity_noise_tradeoff()
    f_cmd, err = fig_step_rate_quantisation()
    fig_wrap_safety()

    rows = [
        ("parameter_set", PARAM_SET, "-"),
        ("encoder_counts_per_rev", COUNTS_PER_REV, "counts/rev"),
        ("q_rad_per_count", f"{res['q_rad']:.12e}", "rad"),
        ("q_deg_per_count", f"{res['q_deg']:.6f}", "deg"),
        ("sample_period", TS, "s"),
        ("sigma_theta", f"{res['sigma_theta_rad']:.6e}", "rad"),
        ("sigma_theta_mc", f"{mc['mc_sigma_theta_rad']:.6e}", "rad"),
        ("velocity_granularity", f"{res['vel_granularity_rad_s']:.6f}", "rad/s"),
        ("sigma_omega", f"{res['sigma_omega_rad_s']:.6f}", "rad/s"),
        ("sigma_omega_mc", f"{mc['mc_sigma_omega_rad_s']:.6f}", "rad/s"),
        ("aliasing_threshold", f"{res['alias_limit_rev_s']:.3f}", "rev/s"),
        ("microsteps_per_rev", MICROSTEPS_PER_REV, "microsteps/rev"),
        ("rad_per_microstep", f"{RAD_PER_USTEP:.12e}", "rad"),
        ("step_tick_rate", f"{TICK_HZ:.4f}", "Hz"),
    ]
    for f in (200, 500, 1000, 2000, 10000):
        i = int(np.argmin(np.abs(f_cmd - f)))
        rows.append((f"step_rate_error_at_{f}Hz", f"{err[i]:+.4f}", "%"))

    out = TABDIR / "EXP001_sensing_analysis.csv"
    with out.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["quantity", "value", "unit"])
        w.writerows(rows)

    print()
    print(f"  wrote {out.relative_to(REPO)}")
    # List only the figures THIS script produced. A glob over the directory
    # would also pick up telemetry plots written by the measurement pipeline
    # and report them as if this run had created them.
    for name in ("EXP001_fig1_quantisation_effect.png",
                 "EXP001_fig2_velocity_noise_tradeoff.png",
                 "EXP001_fig3_step_rate_quantisation.png",
                 "EXP001_fig4_wrap_safety.png"):
        print(f"  wrote {(FIGDIR / name).relative_to(REPO)}")
    print()
    print("  STATUS: numerical/algorithmic analysis EXECUTED.")
    print("  STATUS: MATLAB control-model simulation DEFERRED "
          "-- MATLAB EXECUTION ENVIRONMENT REQUIRED.")


if __name__ == "__main__":
    main()

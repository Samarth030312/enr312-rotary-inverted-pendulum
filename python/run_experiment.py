#!/usr/bin/env python3
"""Run one ENR312 experiment from the command line and save the data.

  python3 run_experiment.py --port /dev/ttyACM0 --exp 9 --set k1=1 --set k2=2 --csv t9.csv
  python3 run_experiment.py --port /dev/ttyACM0 --exp 21 --seconds 15 --ref 20@8
  python3 run_experiment.py --port /dev/ttyACM0 --free-swing 15

The human must ARM and START (this script asks before each, unless --yes), and
can abort at any moment with Ctrl-C (sends ABORT). Upright experiments
(5, 6, 7, 8, 23) need the pendulum held upright before the run, as in the app.
"""
import argparse
import sys
import time

from enr312_rig import Rig, UPRIGHT, free_swing


def ask(msg, yes):
    if yes:
        return True
    return input(msg + " [y/N] ").strip().lower() == "y"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--port", required=True)
    p.add_argument("--exp", type=int)
    p.add_argument("--set", action="append", default=[], metavar="KEY=VALUE", help="gain override, repeatable")
    p.add_argument("--seconds", type=float, default=60, help="stop the run after this long")
    p.add_argument("--ref", action="append", default=[], metavar="DEG@T", help="live set-point DEG at T s, repeatable")
    p.add_argument("--csv", default="run.csv")
    p.add_argument("--log", default=None, help="raw serial log file")
    p.add_argument("--free-swing", type=float, metavar="SECONDS", help="record a free swing (motor SAFE) and analyse it")
    p.add_argument("--yes", action="store_true", help="do not ask before ARM / START")
    a = p.parse_args()

    with Rig(a.port, log_path=a.log) as rig:
        print("connected: protocol %d, state %s" % (rig.protocol, rig.state))
        try:
            if a.free_swing:
                input("Motor SAFE. Displace the hanging pendulum 10-20 deg, press Enter and release it...")
                i0 = len(rig.samples)
                time.sleep(a.free_swing)
                s = rig.samples[i0:]
                rig.save_csv(a.csv, s)
                r = free_swing([x.t for x in s], [x.psi for x in s])
                print("T = %.4f s over %d swings, L = %.4f m (ruler ~%.3f m), zeta = %.4f, Q = %.1f, wg2 = %.2f"
                      % (r["T"], r["n_osc"], r["L_simple"], r["L_rod_predicted"], r["zeta"], r["Q"], r["wg2"]))
                return 0
            if a.exp is None:
                p.error("--exp or --free-swing")
            gains = {}
            for kv in a.set:
                k, v = kv.split("=")
                gains[k] = float(v)
            cfg = rig.configure(a.exp, **gains)
            print("board configuration:", cfg)
            if rig.state == "SAFE":
                if not ask("ARM (energise the stepper; swing path clear)?", a.yes):
                    return 1
                rig.arm()
            if rig.state == "ARMED":
                if not ask("START (permit motion)?", a.yes):
                    return 1
                rig.start()
            if a.exp in UPRIGHT:
                input("Upright experiment: hold the pendulum UPRIGHT and still, press Enter; let go when it captures.")
            refs = sorted((float(x.split("@")[1]), float(x.split("@")[0])) for x in a.ref)
            rig.go()
            t0 = time.monotonic()
            while rig.running and time.monotonic() - t0 < a.seconds:
                while refs and time.monotonic() - t0 >= refs[0][0]:
                    _, deg = refs.pop(0)
                    try:
                        print("REF", rig.set_ref(deg))
                    except RuntimeError as e:
                        print(e)
                s = rig.samples[-1]
                print("\rt %6.1f  phase %2d  arm %+8.2f  pendulum %+8.2f  u %+7.0f  "
                      % (time.monotonic() - t0, s.phase, s.rotor, s.alpha if a.exp in UPRIGHT else s.psi, s.u), end="")
                time.sleep(0.2)
            if rig.running:
                rig.stop()
            print("\n" + rig.run_event)
            rig.save_csv(a.csv)
            print("saved", a.csv)
        except KeyboardInterrupt:
            rig.abort()
            print("\nABORTED by operator")
            return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())

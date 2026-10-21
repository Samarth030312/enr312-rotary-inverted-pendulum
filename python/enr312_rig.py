"""enr312_rig: an OPTIONAL Python client for the ENR312 pendulum firmware.

The firmware (C, firmware/enr312/) and the MATLAB lab app (matlab/apps/enr312_lab.m)
are the primary tools. This module is a thin client that speaks the same serial
protocol, for students who prefer Python (the PEND handout uses Python). It does
not replace or duplicate any controller: every control law runs on the STM32.

Protocol (firmware/enr312/target/src/enr312_main.c, 115200 baud):
  single bytes   ? help  t status  a ARM  s START  x ABORT  c clear fault
                 z zero datums  r stream on/off  . host watchdog keep-alive
  '$' lines      $exp=N  $kp=..  ...  $cfg  $go  $stop  $ref=deg
  stream (50 Hz) D,ticks,rotor_mdeg,pend_mdeg,raw,faults,state,exp,phase,u,ref_mdeg,isr_us
  config echo    C,exp,kp,kd,kpp,kdp,step,dist,ulim,vmax[,ki,fdr,fdp,k1,k2,k3,k4,bv,imp,uon,db,rrate,div,ma]

Safety, as in the MATLAB app: close() and Ctrl-C send ABORT ('x'); while a run
is active the client sends '.' at least every 0.2 s, so if Python stops, the
firmware's 1 s watchdog stops the motor. The human ARMs and STARTs; this module
never does it implicitly.

Requires pyserial (pip install pyserial). Python 3.8+.
"""

import csv
import math
import threading
import time

try:
    import serial  # pyserial
except ImportError:  # pragma: no cover
    serial = None

TICK_S = 0.002
KEYS2 = ["kp", "kd", "kpp", "kdp", "step", "dist", "ulim", "vmax"]
KEYS3 = ["ki", "fdr", "fdp", "k1", "k2", "k3", "k4", "bv", "imp", "uon", "db", "rrate", "div", "ma"]
STATES = ("SAFE", "ARMED", "RUNNING", "FAULT")
UPRIGHT = (5, 6, 7, 8, 23)


class Sample:
    """One 50 Hz stream sample. Angles in degrees, u in deg/s^2, t in s (MCU clock)."""

    __slots__ = ("t", "rotor", "psi", "raw", "faults", "state", "exp", "phase", "u", "ref")

    def __init__(self, f):
        self.t = int(f[1]) * TICK_S
        self.rotor = int(f[2]) / 1000.0
        self.psi = int(f[3]) / 1000.0
        self.raw = int(f[4])
        self.faults = int(f[5])
        self.state = f[6]
        self.exp = int(f[7]) if len(f) == 12 else 0
        self.phase = int(f[8]) if len(f) == 12 else -1
        self.u = float(f[9]) if len(f) == 12 else 0.0
        self.ref = int(f[10]) / 1000.0 if len(f) == 12 else 0.0

    @property
    def alpha(self):
        """Angle from upright [deg] (alpha = wrap180(180 - psi))."""
        return (180.0 - self.psi + 180.0) % 360.0 - 180.0


class Rig:
    """Serial link to the board (or to the emulator's pty).

    rig = Rig("/dev/ttyACM0")      # opens, asks status and help, streams
    rig.arm(); rig.start()         # the human decides; both are explicit
    rig.configure(exp=9, k1=1, k2=2)
    rig.go(); rig.wait_finished(40)
    rig.save_csv("run.csv"); rig.close()
    """

    def __init__(self, port, baud=115200, log_path=None):
        if serial is None:
            raise RuntimeError("pyserial is not installed: pip install pyserial")
        self.ser = serial.Serial(port, baud, timeout=0.05)
        self.lock = threading.Lock()
        self.samples = []
        self.lines = []
        self.cfg = {}
        self.protocol = 1
        self.state = "UNKNOWN"
        self.last_error = ""
        self.last_ref = math.nan
        self.run_event = ""
        self.running = False
        self.go_seen = False          # 'GO' arrived (RUN lines follow at once)
        self.invalid = 0
        self._partial = b""
        self._log = open(log_path, "w") if log_path else None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._reader, daemon=True)
        self._thread.start()
        self.key("t")
        self.key("?")          # help repeats the version line: learn the protocol
        self.key("r")          # stream on
        self.wait(lambda: self.samples and self.protocol >= 2, 3.0)

    # ---------------------------------------------------------------- transport
    def key(self, c):
        with self.lock:
            self.ser.write(c.encode())
        self._logline(">> " + c)

    def send(self, line):
        """Send one '$' command line, e.g. rig.send('kp=9')."""
        with self.lock:
            self.ser.write(("$" + line + "\n").encode())
        self._logline(">> $" + line)

    def _reader(self):
        last_keep = 0.0
        while not self._stop.is_set():
            try:
                b = self.ser.read(4096)
            except Exception:  # port gone
                break
            if b:
                self._partial += b
                *done, self._partial = self._partial.split(b"\n")
                for raw in done:
                    try:
                        self._parse(raw.decode(errors="replace").strip())
                    except Exception:      # a damaged line must never stop the keep-alive
                        self.invalid += 1
            now = time.monotonic()
            if self.running and now - last_keep > 0.2:      # feed the 1 s host watchdog
                last_keep = now
                try:
                    with self.lock:
                        self.ser.write(b".")
                except Exception:
                    break

    def _parse(self, s):
        if not s:
            return
        self._logline(s)
        if s.startswith("D,"):
            f = s.split(",")
            if len(f) not in (7, 12) or f[6] not in STATES:
                self.invalid += 1
                return
            try:
                smp = Sample(f)
            except ValueError:
                self.invalid += 1
                return
            self.samples.append(smp)
            self.state = smp.state
            if len(f) == 12:
                self.protocol = max(self.protocol, 2)
            return
        self.lines = (self.lines + [s])[-200:]
        if "protocol 3" in s:
            self.protocol = 3
        elif "protocol 2" in s:
            self.protocol = max(self.protocol, 2)
        if s.startswith("C,"):
            v = [float(x) for x in s[2:].split(",")]
            if len(v) in (9, 23):
                c = {"exp": int(v[0])}
                c.update(zip(KEYS2, v[1:9]))
                if len(v) == 23:
                    c.update(zip(KEYS3, v[9:]))
                self.cfg = c
        elif s.startswith("ERR"):
            self.last_error = s
        elif s.startswith("REF "):
            self.last_ref = float(s[4:])
        elif s.startswith(("GO ", "RUN ", "STOPPING")):
            self.run_event = s
            if s.startswith("GO "):
                self.go_seen = True
            if "FINISHED" in s or "ABORTED" in s:
                self.running = False

    def _logline(self, s):
        if self._log:
            self._log.write(s + "\n")

    # ---------------------------------------------------------------- helpers
    @staticmethod
    def wait(cond, tmax):
        t0 = time.monotonic()
        while not cond() and time.monotonic() - t0 < tmax:
            time.sleep(0.02)
        return bool(cond())

    def arm(self):
        """ARM energises the stepper (it holds, it does not move). Human decision."""
        self.key("a")
        return self.wait(lambda: self.state == "ARMED", 3)

    def start(self):
        """START permits motion. Human decision."""
        self.key("s")
        return self.wait(lambda: self.state == "RUNNING", 3)

    def abort(self):
        self.running = False
        self.key("x")

    def zero(self):
        """Zero both datums HERE: the pendulum must hang still."""
        self.key("z")

    # ---------------------------------------------------------------- experiments
    def configure(self, exp, **gains):
        """Load the firmware defaults of exp, override gains, and check the echo.

        Returns the board's configuration (dict). Raises on ERR or a mismatch:
        a lost byte must never change a gain silently.
        """
        if exp >= 6 and self.protocol < 3:
            raise RuntimeError("experiment %d needs firmware protocol 3 (2.1.0); board speaks %d"
                               % (exp, self.protocol))
        allowed = KEYS2 + (KEYS3 if exp >= 6 else [])
        for k in gains:
            if k not in allowed:
                raise ValueError("%s is not a parameter of experiment %d" % (k, exp))
        self.cfg = {}
        self.last_error = ""
        self.send("exp=%d" % exp)
        for k, v in gains.items():
            self.send("%s=%.6g" % (k, v))
        self.send("cfg")
        ok = self.wait(lambda: self.last_error or (self.cfg.get("exp") == exp and all(
            abs(self.cfg.get(k, math.nan) - v) <= 1e-3 * max(1.0, abs(v)) for k, v in gains.items())), 1.5)
        if self.last_error:
            raise RuntimeError("rejected: " + self.last_error)
        if not ok:
            raise RuntimeError("the board did not confirm the configuration")
        return dict(self.cfg)

    def go(self):
        """Start the configured experiment (requires RUNNING state)."""
        if self.state != "RUNNING":
            raise RuntimeError("ARM and START first (state %s)" % self.state)
        self.run_event = ""
        self.go_seen = False
        self.last_error = ""
        self.running = True           # feed the watchdog from now on
        self.run_start = len(self.samples)
        self.send("go")
        if not self.wait(lambda: self.go_seen or self.last_error, 2) or not self.go_seen:
            self.running = False
            raise RuntimeError("no GO from the board " + self.last_error)

    def stop(self):
        self.send("stop")
        self.wait(lambda: "FINISHED" in self.run_event or "ABORTED" in self.run_event, 5)
        self.running = False

    def wait_finished(self, tmax):
        """Block until the run finishes or aborts (True = finished)."""
        self.wait(lambda: not self.running, tmax)
        return "FINISHED" in self.run_event

    def set_ref(self, deg):
        """Live arm set-point [deg]: P21 while regulating, T6/T7/T8/P23 in HOLD."""
        self.last_error = ""
        self.last_ref = math.nan
        self.send("ref=%.6g" % deg)
        self.wait(lambda: not math.isnan(self.last_ref) or self.last_error, 1)
        if self.last_error or math.isnan(self.last_ref):
            raise RuntimeError("set-point not accepted " + self.last_error)
        return self.last_ref

    def set_live(self, **gains):
        """Change gains during a run (experiments 6-10, 21-23)."""
        for k, v in gains.items():
            self.send("%s=%.6g" % (k, v))
        return self.wait(lambda: all(abs(self.cfg.get(k, math.nan) - v) <= 1e-3 * max(1.0, abs(v))
                                     for k, v in gains.items()), 1)

    def run_samples(self):
        return self.samples[getattr(self, "run_start", 0):]

    def save_csv(self, path, samples=None):
        """Write t, rotor, psi, alpha, u, ref, phase (degrees, seconds from the first sample)."""
        s = samples if samples is not None else self.run_samples()
        if not s:
            return
        t0 = s[0].t
        with open(path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["t", "rotor", "psi", "alpha", "u", "ref", "phase"])
            for x in s:
                w.writerow(["%.3f" % (x.t - t0), "%.3f" % x.rotor, "%.3f" % x.psi, "%.3f" % x.alpha,
                            "%.0f" % x.u, "%.3f" % x.ref, x.phase])

    def close(self):
        try:
            self.abort()
            time.sleep(0.1)
        finally:
            self._stop.set()
            self._thread.join(1)
            self.ser.close()
            if self._log:
                self._log.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


# -------------------------------------------------------------------- analysis
def free_swing(t, psi, n_osc=10):
    """PEND A4 from a hanging free swing: period, simple-pendulum length, damping.

    Same method as matlab/+odyssix/+pend/freeSwing.m: peaks of the de-meaned
    encoder angle (runs of equal values collapsed), period over n_osc swings,
    small-amplitude correction, L = g (T0/2 pi)^2, log decrement.
    """
    g = 9.81
    tail = sorted(psi[3 * len(psi) // 4:])
    off = tail[len(tail) // 2]
    y = [p - off for p in psi]
    st = [0] + [i for i in range(1, len(y)) if y[i] != y[i - 1]]
    en = st[1:] + [len(y)]
    v = [y[i] for i in st]
    pk = [(st[j] + en[j] - 1) // 2 for j in range(1, len(v) - 1)
          if v[j] > v[j - 1] and v[j] > v[j + 1] and v[j] > 0.5]
    if len(pk) < 3:
        raise ValueError("fewer than 3 swing peaks")
    n = min(n_osc, len(pk) - 1)
    T = (t[pk[n]] - t[pk[0]]) / n
    # the swing decays over the n periods: correct with the mean peak amplitude
    A = math.radians(sum(abs(y[k]) for k in pk[:n + 1]) / (n + 1))
    T0 = T / (1 + A * A / 16 + 11 * A ** 4 / 3072)
    L = g * (T0 / (2 * math.pi)) ** 2
    delta = math.log(abs(y[pk[0]]) / abs(y[pk[n]])) / n
    zeta = delta / math.sqrt(4 * math.pi ** 2 + delta ** 2)
    return {"T": T, "T0": T0, "n_osc": n, "L_simple": L, "L_rod_predicted": L / 0.6805,
            "delta": delta, "zeta": zeta, "Q": 1 / (2 * zeta), "wg2": (2 * math.pi / T0) ** 2}


def recovery(t, ang, t0, band, t_end=None):
    """Time after t0 until |ang| stays within band (PEND A5, A7). None = never."""
    w = [(ti, abs(a)) for ti, a in zip(t, ang) if ti >= t0 and (t_end is None or ti <= t_end)]
    if not w:
        return None
    out = [i for i, (_, a) in enumerate(w) if a > band]
    if not out:
        return 0.0
    if out[-1] == len(w) - 1:
        return None
    return w[out[-1] + 1][0] - t0

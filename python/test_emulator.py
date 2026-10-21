#!/usr/bin/env python3
"""Test enr312_rig against the rig EMULATOR (the firmware's C control code on the PC).

  make -C firmware/enr312 host-rig && python3 python/test_emulator.py

SYNTHETIC: no hardware. About 40 s. Linux/macOS (the emulator uses a pty).
"""
import os
import subprocess
import sys
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from enr312_rig import Rig, free_swing, recovery  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMU = os.path.join(ROOT, "firmware", "enr312", "build", "enr312_host_rig")


class EmulatorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.path.exists(EMU):
            raise unittest.SkipTest("build the emulator: make -C firmware/enr312 host-rig")
        cls.proc = subprocess.Popen([EMU, "--pty", "--parent", str(os.getpid())],
                                    stdout=subprocess.PIPE, text=True)
        port = cls.proc.stdout.readline().strip()
        cls.rig = Rig(port)

    @classmethod
    def tearDownClass(cls):
        cls.rig.close()
        cls.proc.terminate()

    def test_1_protocol_3(self):
        self.assertEqual(self.rig.protocol, 3)
        self.assertEqual(self.rig.state, "SAFE")

    def test_2_free_swing_pend_a4(self):
        r = self.rig
        r.key("!")                                    # emulator: pluck 30 deg
        i0 = len(r.samples)
        time.sleep(12)
        s = r.samples[i0:]
        f = free_swing([x.t for x in s], [x.psi for x in s])
        # emulator truth: wg2 56.4, Q 24
        self.assertAlmostEqual(f["wg2"], 56.4, delta=0.6)
        self.assertAlmostEqual(f["Q"], 24, delta=2.5)

    def test_3_rejects_unknown_and_wrong_protocol_keys(self):
        with self.assertRaises(ValueError):
            self.rig.configure(5, ki=1)               # Tutorial 5 has no Ki

    def test_4_p21_stop_swing_then_hold_angle(self):
        r = self.rig
        r.wait(lambda: abs(r.samples[-1].psi) < 3, 20)
        self.assertTrue(r.arm())
        self.assertTrue(r.start())
        cfg = r.configure(21, kdp=5)
        self.assertEqual(cfg["exp"], 21)
        self.assertIn("ma", cfg)                      # protocol 3 C line
        r.key("!")
        time.sleep(0.3)
        r.go()
        time.sleep(8)
        s = r.run_samples()
        t = [x.t - s[0].t for x in s]
        stop = recovery(t, [x.psi for x in s], 0.0, 1.0)
        self.assertIsNotNone(stop)
        self.assertEqual(r.set_ref(15), 15)
        time.sleep(6)
        self.assertAlmostEqual(r.samples[-1].rotor, 15, delta=0.5)
        self.assertTrue(r.set_live(kdp=8))
        r.stop()
        self.assertIn("FINISHED", r.run_event)
        r.abort()


if __name__ == "__main__":
    unittest.main(verbosity=2)

# Hanging experiments (EXP009, EXP010, EXP021, EXP022): hardware procedure

**Status: NOT_EXECUTED.** Same workflow as Tutorials 2–4, which ran on the rig on
2026-10-12. One person is enough. The pendulum hangs throughout.

## Expected behaviour
EXP009/010/022: 1 s idle, then step 20° (15 s), back (15 s), DONE. EXP021 regulates
the arm at its reference and damps the pendulum until **Stop run**; **Go to angle**
moves the arm (slewed at 90 deg/s) and holds it.

## Limits
|ψ| > 120°, |θ| > 240°, input saturation 200 ms, velocity limit, 1 s host watchdog:
all de-energise the stepper.

## Steps
1. Flash 2.1.0 (protocol 3). Connect. Pendulum hanging still: **Zero datums**.
2. ARM, START. Select the experiment and preset; Simulate.
3. EXP021 only: pluck the pendulum 10–30° and let go, then press Run.
   For the others the pendulum must hang still (the app refuses otherwise).
4. Run on rig; watch; Save rig run. EXP021: time the stop, then Go to angle, Stop run.
5. EXP010/EXP023: use the LQR designer (Q, R → k) and compare designs.

## Stop conditions and rollback
Growing oscillation, the arm running away, missed steps: ABORT (Esc / Space) or pull
12 V. ABORT → SAFE; clear fault; re-zero.

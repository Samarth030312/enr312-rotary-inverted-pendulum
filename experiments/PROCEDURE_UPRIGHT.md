# Upright experiments (EXP006, EXP007, EXP008, EXP023): hardware procedure

**Status: NOT_EXECUTED.** This is the EXP005 procedure that balanced on the rig on
2026-10-12 (firmware 2.0.8, 4 of 4 balanced), applied to the general controller of
firmware 2.1.0. Two people: one at the app (ABORT under the hand), one holding the
pendulum, clear of the arm's path.

## Expected behaviour
Capture after 1 s within ±2° of upright; the motor waits while it is held; it starts
balancing the moment the hand lets go (1.5° of free motion). After 5 s of balance comes
the sequence (EXP006/023: step and back; EXP007: 8 impulses; EXP008: step, back, load
disturbance on and off). The run then stays in **HOLD**, balancing, until Stop run.

## Limits (firmware, not adjustable from the app)
|α| > 15° (or > 10° for 100 ms): PENDULUM_LOST; |θ| > 240°: ROTOR_LIMIT; u at its limit
for 200 ms: SATURATION; arm speed at its ceiling too long: VELOCITY_LIMIT; 1 s without the host keep-alive: HOST_WATCHDOG. All of these
de-energise the stepper.

## Steps
1. Flash **2.1.0** (the app's Flash firmware; check the banner says protocol 3).
2. Connect. The pendulum hangs still: **Zero datums**.
3. ARM (confirm the dialog), START.
4. Select the experiment and preset. Simulate first, and read the predicted overshoot and arm excursion.
5. Lift the pendulum upright and hold it still. **Run on rig.**
6. On **LET GO NOW**, release without pushing.
7. Watch the arm's first motion at the step: it should move the wrong way (RHP zero).
8. In HOLD: try **Go to angle**, e.g. 30° (the arm must hold it, ±1.5°). Try
   **Apply gains live** (one gain at a time; record what changed).
9. Stop run, then **Save rig run**. Fill in the operator in the YAML.

## Stop conditions
Growing oscillation; the arm running toward ±240°; harsh motor noise or missed steps;
anything unexpected. Press ABORT (or Esc / Space); pulling 12 V always works.

## Rollback
ABORT → SAFE (motor off). Clear fault. Re-zero hanging. Reflash 2.0.8 if 2.1.0 misbehaves
(Tutorials 1–5 are unchanged in 2.1.0).

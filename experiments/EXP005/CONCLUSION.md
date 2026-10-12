> **Pre-registration.** Written before the hardware runs and kept unchanged as the
> record of what was predicted. Status fields below are those of that time.
> Hardware results (2026-10-12): [`results/reports/2026-10-12_rig_tutorials_1-5.md`](../../results/reports/2026-10-12_rig_tutorials_1-5.md); raw data in `data/raw/EXP005/`.

# EXP005 — Conclusion

**Date:** 2026-08-19 · **Source:** Tutorial 5 · **Safety class: HIGH**

## Verdict
**Complete to the limit of this environment; not complete as an experiment.** The unstable
plant, its stabilisation and its fundamental limitation are derived, implemented and
verified in software. **Nothing has been measured, and this is the experiment where that
matters most.**

## What is established

1. The open-loop inverted plant is unstable — RHP pole at +7.2888 rad/s, 137 ms — and the
   simulation is **verified to diverge** before any stabilisation claim is made.
2. Tutorial 5's supplied `K_pend = 300 + 30s` stabilises it (`ζ = 0.899`).
3. The outer loop **must be sign-inverted**, established from Tutorial 5's own designs.
4. Stabilising the unstable pole **converts it into a non-minimum-phase zero**, capping
   bandwidth near 3.64 rad/s.
5. Designs meeting all five of System 1's and System 2's objectives simultaneously.
6. 36 EXP005 host checks; **276 across the core**; zero warnings; 7347 B flash; **0 B
   static RAM**.

## The result worth carrying furthest

**Stabilising an unstable pole does not remove it from the problem — it converts it into a
right-half-plane zero of the loop the next controller must work with.**

That single sentence explains why Tutorial 5's targets are so much looser than Tutorial
3's, why gain and phase margins rather than speed become binding, and why the arm must
move the *wrong way first*. It is not a tuning difficulty that a better controller could
overcome; it is a conservation law of the problem. Every later experiment in this
laboratory that touches the inverted configuration inherits it.

And it is **directly observable**: the arm visibly moves away from the commanded direction
before reversing. Of everything in EXP001–EXP005, that is the prediction most worth going
to the rig to see.

## What EXP005 has *not* shown

Nothing measured. The pendulum has never balanced. And the assumption that most threatens
it — **that the loop timing is what everyone assumes** — has never been checked, which is
why OI-10 was opened here rather than treated as an EXP003 leftover.

## Three source conflicts, none papered over

1. `K_d_pend`: `300 × 0.5 = 150 ≠ 30`. Resolved to 30 on two independent sources.
2. System 2 `K_d`: 3.33 (table) vs 3.00 (transcript). 3.33 used; both evaluated.
3. **"Improved performance"** for System 2 — the model says the opposite by a factor of
   four in settling time. **Left unresolved and flagged**, because guessing which reading
   is right would be exactly the kind of silent choice docs/ENGINEERING_STANDARDS.md §7 forbids.

## Engineering decisions recorded

- **No state feedback, LQR, Kalman filter, observer or integral action.** Tutorial 5
  requires none, and the boundary was held deliberately.
- **Safety bounds tightened eightfold** (120° → 15°) with a layered warning band and a
  capture gate, because inverted mode has no benign failure.
- **The capture gate commands nothing while waiting** — the loop must not close on a
  pendulum that is already falling.

## Gate
**EXP006+ is outside the scope of this release.**

## Reproducibility
```bash
cd firmware/enr312 && make test && make arm && cd ../..
python3 scripts/exp005_unstable_mimo.py     # ~4 min
```

# Roadmap

What comes next, why, and how we will know it worked. Nothing on this page is built
yet. When a step is done it moves to the [changelog](CHANGELOG.md) together with its
rig data.

The order matters. Each step stands on something we measured, and none of them may
break what already works: the 500 Hz loop, the safety stops, and the rule that the
simulation equals the firmware.

## 0. Finish what the rig told us (now)

Open items from the rig sessions of 2026-10-21
([evening](results/reports/2026-10-21b_rig_session.md#what-is-still-open),
[last](results/reports/2026-10-21d_rig_session.md#6-what-this-settles)):

1. Measure the push limit more finely. The first push test bracketed it between 83 and
   115 deg/s, against a simulated 100. Repeat with pushes of growing size, each marked
   with PUSH MARK, so that every push has a 500 Hz record
   ([report](results/reports/2026-10-21d_rig_session.md#4-the-push-test-15-of-17-pushes-recovered)).
2. ~~Swing-ups with the measured ωg².~~ Done: 4 of 4 caught (3.9–5.8 s), and the push
   test (15 of 17 recovered) ([report](results/reports/2026-10-21d_rig_session.md)).
3. Run EXP021 with a real pluck.
4. Explain why T3's control effort is 22 on the rig and 48 in simulation.
5. Subtract the resting arm offset from the T3/T4 step metrics.

The measured pendulum (ωg² = 48.0 ± 0.5, dry pivot friction) is the starting point for everything below.

## 1. Model predictive control

**Why.** Every hard moment on this rig so far has been a constraint, not a gain:

- T6's 40° step saturates the arm's 1500 deg/s² limit. The simulation predicts 34 %
  overshoot instead of the linear model's 52 %, so the saturation, not the gains,
  sets the response.
- The swing-up catch failed because a fast-moving arm cannot be stopped in time. The
  2.3.1 fix asks "is the LQR's first command within twice the limit?". That is a crude,
  one-step version of the question MPC asks properly over a whole horizon.
- The arm has a hard travel limit of ±240°, and LQR knows nothing about it.

LQR is optimal only while nothing saturates. MPC solves the same kind of quadratic
cost, but subject to the limits, every sample.

**Plan.**

1. *Model.* The same 4-state linear model as the LQR, x = [θ, θ̇, α, α̇], with input u
   the arm acceleration, discretised at the MPC rate. The constants come from the free
   swing.
2. *Offline, in MATLAB.*
   - Write a condensed QP with box constraints on u (±1500 deg/s²) and on θ.
   - Solve it with our own solver (projected fast gradient or ADMM), so that base MATLAB
     is enough and the same code can be ported to C.
   - Compare it with the LQR on the T6 step and on catches from the rig's real catch
     states (the four points in the evening report).
3. *Rate and horizon.*
   - At the 500 Hz loop rate a useful horizon (about 0.3 s) would be 150 steps. That is
     too many for an 84 MHz Cortex-M4.
   - Plan: run MPC at 100 Hz with N = 30 and keep the 500 Hz loop for the stepper and
     the safety supervisor, holding u between MPC updates.
   - The solve time is measured on the board, not guessed. If it does not fit in 10 ms,
     the fallback is explicit MPC (a precomputed piecewise-affine law) for the
     balancing region only.
4. *Parity.* Like every controller here, the C version gets a MATLAB twin and a test
   that they agree to rounding.
5. *Rig.*
   - T6 step and the swing-up catch with MPC instead of the LQR.
   - Pass: overshoot within the prediction, and catches held from states where 2.3.1
     refuses to catch.

**What could go wrong.** The stepper is not a perfect acceleration source near its
pull-out torque, and friction is not in the linear model. If MPC does not beat a
well-tuned LQR on the rig, we will report that too.

## 2. micro-ROS on Zephyr

**Why.** The rig talks a small text protocol to MATLAB. That works for one rig and one
app. A ROS 2 interface would let any ROS tool do the same job: record (rosbag), plot,
command, or run the rig in a larger system. Zephyr gives a maintained RTOS with a
proper driver model on this exact board (`nucleo_f401re` is an upstream Zephyr board).

**The constraint.** The F401RE has 96 KB of RAM. On another project with this same
MCU, FreeRTOS plus micro-ROS used 97 % of the RAM for a single publisher. The control
loop cannot share the CPU with a middleware stack unless the scheduling is designed
first.

**Plan.**

1. Port the board layer to Zephyr: timer interrupt at 500 Hz, the L6474 over SPI, the
   encoder on TIM3, and the UART. The control cores in `firmware/enr312/src/` are plain
   C with no HAL calls, so they move unchanged. The host tests and the MATLAB parity
   test keep guarding them.
2. Timing first, before ROS:
   - The 500 Hz control runs from the timer interrupt or the highest-priority thread.
   - Measure the jitter with a GPIO and a logic analyser against the bare-metal build.
   - Pass: worst-case jitter within 20 µs, and no change in the T2 and T5 results.
3. Then micro-ROS (the `micro_ros_zephyr_module`, over the ST-LINK serial port) in a
   low-priority thread:
   - publishes: `sensor_msgs/JointState` for the arm and the pendulum at 50 Hz, and the
     run state;
   - subscribes: set-points and gains.
   - The safety stops stay in the firmware. If the ROS link dies, the rig stops exactly
     as it does today when MATLAB goes silent.
4. Recording: a rosbag of a run must give the same CSV as the app's recorder, column
   for column.

The bare-metal firmware stays the reference. The Zephyr build becomes a third target
next to it, and it has to pass the same host tests and rig checks.

## 3. More SDKs, one control core

The control law lives in `firmware/enr312/src/`, which knows nothing about the
hardware. The aim is to show that this separation holds by running the same core on
other stacks:

| Stack | What it adds | What it has to show |
|---|---|---|
| STM32Cube **LL** drivers instead of HAL | a smaller, faster board layer | same results, measured ISR time |
| **Zephyr** (section 2) | RTOS, device tree, micro-ROS | loop jitter as good as bare metal |
| **ROS 2** on the PC | rosbag, rviz, any client | the same experiments run from ROS |
| **Python** client (exists, optional) | scripting runs without MATLAB | same protocol, same recorded data |
| **Rust**, embassy-stm32 (exploratory) | memory safety in the board layer | the C core called through FFI, parity kept |

MATLAB and C remain the main tools. The others are added only where they bring
something measurable, and each one gets the same tests before it counts.

## 4. Later, only after the above

- Identify the stepper's real torque limit and the friction model from data, and add
  them to the model only if they change a prediction.
- Swing-up and catch fully under MPC.
- A second pendulum (double inverted pendulum): needs a second encoder and a new
  derivation, so it is a new project rather than a step.

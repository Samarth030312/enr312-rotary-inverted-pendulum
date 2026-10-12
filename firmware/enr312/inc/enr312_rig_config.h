/**
 * @file    enr312_rig_config.h
 * @brief   Single source of truth for ENR312 rotary inverted pendulum rig constants.
 *
 * Parameter set: PS-EDUKIT01-v1  (shared/parameters/edukit01_rig.yaml)
 *
 * ---------------------------------------------------------------------------
 * PROVENANCE. Every constant below is tagged. The tags are not decoration --
 * they record how much the value may be trusted:
 *
 *   [COURSE]     Stated by an ENR312 course document.
 *   [DATASHEET]  Manufacturer nominal for the named part.
 *   [DERIVED]    Computed from other constants here. Exact.
 *   [REF]        From the UCLA reference project. A strong prior (identical
 *                shield, identical MCU) but NOT verified on this rig.
 *   [MEASURED]   Obtained from this rig. NONE EXIST YET.
 *
 * No constant in this file is [MEASURED]. Until EXP001 and EXP002 execute on
 * hardware, this file describes a PREDICTION of the rig, not the rig.
 * ---------------------------------------------------------------------------
 *
 * This header is deliberately free of any STM32 HAL or CMSIS dependency so the
 * EXP001 core can be compiled and unit-tested on the host.
 */

#ifndef ENR312_RIG_CONFIG_H
#define ENR312_RIG_CONFIG_H

#ifdef __cplusplus
extern "C" {
#endif

#define ENR312_PARAMETER_SET_ID   "PS-EDUKIT01-v1"

/* --- Mathematical constant -------------------------------------------------
 * Defined locally rather than relying on M_PI, which is not in ISO C and is
 * absent under -std=c11 without _GNU_SOURCE / __USE_MISC.
 */
#define ENR312_TWO_PI             6.283185307179586476925286766559

/* ===========================================================================
 * SENSING CHAIN -- pendulum angle, incremental quadrature encoder
 * ===========================================================================
 */

/** Encoder pulses per revolution, one channel.  [DATASHEET] LPD3806-600BM. */
#define ENR312_ENCODER_PPR                600

/** Quadrature decode multiplier. 4 = X4 (both edges, both channels).  [REF]
 *
 *  THIS IS A FIRMWARE DECISION, NOT AN ENCODER PROPERTY. The same encoder
 *  yields 600, 1200 or 2400 counts/rev depending on how the timer is
 *  configured. EXP001 prediction P2 exists to confirm this value; if the
 *  measured counts/rev is 600 or 1200, change THIS constant -- do not patch
 *  a correction factor downstream.
 */
#define ENR312_ENCODER_DECODE_X           4

/** Counts per mechanical revolution of the pendulum shaft.  [DERIVED] = 2400 */
#define ENR312_ENCODER_COUNTS_PER_REV     (ENR312_ENCODER_PPR * ENR312_ENCODER_DECODE_X)

/** Angular resolution.  [DERIVED] 2*pi/2400 = 2.617994e-3 rad = 0.15 deg. */
#define ENR312_ENCODER_RAD_PER_COUNT      (ENR312_TWO_PI / (double)ENR312_ENCODER_COUNTS_PER_REV)
#define ENR312_ENCODER_DEG_PER_COUNT      (360.0 / (double)ENR312_ENCODER_COUNTS_PER_REV)

/** Width of the hardware counter, in bits. TIM3 on STM32F401 is 16-bit.  [REF] */
#define ENR312_ENCODER_COUNTER_BITS       16
#define ENR312_ENCODER_COUNTER_MODULUS    (1L << ENR312_ENCODER_COUNTER_BITS)
#define ENR312_ENCODER_COUNTER_HALF       (1L << (ENR312_ENCODER_COUNTER_BITS - 1))

/** Sign convention for the sensing chain.  [MEASURED 2026-10-12, EXP001 P2b]
 *
 *  Convention (docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md section 2):
 *  +psi is the sense in which the HANGING pendulum first swings when the arm
 *  accelerates in +theta (psi'' = +wr^2 theta'' near hanging).
 *
 *  Evidence: results/evidence/logs/rig_20261012-160027.log, board 2, with the
 *  raw (+1) setting: in 8 of 8 arm moves (+-5, +-20, +-34.74 deg) the first
 *  pendulum excursion had the OPPOSITE sign to the move (-0.15..-0.45 deg on
 *  + moves, +0.15..+0.60 deg on - moves). The physics requires the SAME sign,
 *  so this rig's A/B wiring needs -1. (It happens to match the UCLA rig; it
 *  was measured, not copied.)
 *
 *  A wrong sign here converts negative feedback into positive feedback.
 */
#define ENR312_ENCODER_POLARITY           (-1)

/* ===========================================================================
 * ACTUATION CHAIN -- rotor arm, NEMA-17 stepper via L6474
 * ===========================================================================
 */

/** Full steps per motor revolution. 1.8 deg/step.  [DATASHEET] */
#define ENR312_MOTOR_FULL_STEPS_PER_REV   200

/** L6474 microstep divisor (STEP_SEL_1_16).  [REF] */
#define ENR312_MOTOR_MICROSTEP_DIVISOR    16

/** Microsteps per revolution.  [DERIVED] = 3200 */
#define ENR312_ROTOR_MICROSTEPS_PER_REV \
    (ENR312_MOTOR_FULL_STEPS_PER_REV * ENR312_MOTOR_MICROSTEP_DIVISOR)

/** Nominal command increment.  [DERIVED] 2*pi/3200 = 1.963495e-3 rad = 0.1125 deg.
 *
 *  "Nominal" is load-bearing: microstep increments are not uniform under load.
 *  See FIRST_PRINCIPLES.md section 2.2 and limitation L2.
 */
#define ENR312_ROTOR_RAD_PER_MICROSTEP    (ENR312_TWO_PI / (double)ENR312_ROTOR_MICROSTEPS_PER_REV)
#define ENR312_ROTOR_DEG_PER_MICROSTEP    (360.0 / (double)ENR312_ROTOR_MICROSTEPS_PER_REV)

/** Sign convention for the actuation chain.  [MEASURED 2026-10-12, EXP001 P1]
 *  A +5 deg command turned the arm the way the app's green line points, and a
 *  protractor read 5 deg (rig_20261012-160027.log): +1, and 8.889 microsteps/deg
 *  (conflict C-1 resolved). */
#define ENR312_ROTOR_POLARITY             (+1)

/* --- Step clock generation -------------------------------------------------
 * The STCK pin is a plain GPIO output toggled from a timer update ISR; it is
 * NOT driven by timer alternate-function hardware. See parameter set note
 * actuator.step_clock.
 */
#define ENR312_SYSCLK_HZ                  84000000UL   /* [LOCAL FIRMWARE] verified */
#define ENR312_STEP_TIMER_PRESCALER       1024UL       /* [REF] */

/** Step-timer tick rate, Hz.  [DERIVED] 84e6/1024 = 82031.25 Hz -- NOT an integer.
 *
 *  Deliberately a double. Truncating this to 82031 introduces a systematic
 *  -3 ppm bias into every predicted step rate, which then disagrees with the
 *  hand-derived numbers in FIRST_PRINCIPLES.md section 2.3. The prescaler
 *  divides the clock exactly; the fractional tick rate is physically real and
 *  must not be rounded away in the model.
 */
#define ENR312_STEP_TICK_HZ               (84000000.0 / 1024.0)

/* ===========================================================================
 * TIMING
 * ===========================================================================
 */

/** Control period.  [COURSE] "a control loop 500 times per second (every 2 ms)". */
#define ENR312_CONTROL_PERIOD_S           0.002
#define ENR312_CONTROL_RATE_HZ            500

/* ===========================================================================
 * SAFETY LIMITS
 * ===========================================================================
 * These bound COMMANDED motion. They are travel limits, not control tuning.
 * Both are [REF] and must be confirmed against this rig's cabling before any
 * powered move (EXP001 procedure step 0).
 */
#define ENR312_ROTOR_LIMIT_DEG            240.0
#define ENR312_PENDULUM_ABORT_DEG         120.0

/** Maximum step rate EXP001 is permitted to command.
 *
 *  Chosen, not inherited. The reference initialises profiles up to 10000
 *  steps/s; at that rate the step-rate quantisation error is +2.54 % and the
 *  step ISR runs at 10 kHz against a 500 Hz control loop. EXP001 needs neither
 *  speed nor that risk -- it needs trustworthy, slow, observable motion. 1000
 *  steps/s = 112.5 deg/s keeps rate error at 0.038 % and the ISR load modest.
 */
#define ENR312_EXP001_MAX_STEP_RATE_HZ    1000

#ifdef __cplusplus
}
#endif
#endif /* ENR312_RIG_CONFIG_H */

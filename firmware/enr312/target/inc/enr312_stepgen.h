/**
 * @file    enr312_stepgen.h
 * @brief   TIM2-paced step-pulse generator for the L6474 STCK pin.
 *
 * One TIM2 update event produces exactly one rising edge on PC7, and the L6474
 * advances one microstep per rising edge. So the commanded step rate is the
 * TIM2 update rate, and the ARR returned by ENR312_Rotor_ComputeStepTimerARR()
 * can be loaded here unmodified. That equality is the point: the position model
 * in enr312_rotor.c counts pulses requested, and this module is what makes
 * "pulses requested" and "pulses emitted" the same number.
 *
 * The generator counts down a finite pulse budget and stops itself. There is no
 * free-running mode -- a commanded move always terminates, even if the caller
 * never speaks to it again.
 */

#ifndef ENR312_STEPGEN_H
#define ENR312_STEPGEN_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENR312_STEP_DIR_NEGATIVE = 0,
    ENR312_STEP_DIR_POSITIVE = 1
} ENR312_StepDir_t;

/** @brief Initialise TIM2 and the STCK pin. Leaves the timer stopped. */
void ENR312_StepGen_Init(void);

/**
 * @brief Emit exactly @p count pulses at the rate implied by @p arr.
 *
 * Rejected unless ENR312_Safety_MotionPermitted(). Setting the DIR pin is done
 * here, before the first pulse, with a settling delay -- the L6474 samples DIR
 * on the STCK rising edge, so changing it late loses a step in the wrong
 * direction.
 *
 * @return false if motion is not permitted or a burst is already running.
 */
bool ENR312_StepGen_Start(ENR312_StepDir_t dir, uint32_t count, uint32_t arr);

/** @brief Stop immediately. ISR-safe. Any unemitted pulses are abandoned. */
void ENR312_StepGen_Stop(void);

/** @brief Pulses not yet emitted from the current burst. */
uint32_t ENR312_StepGen_Remaining(void);

/** @brief True while a burst is in progress. */
bool ENR312_StepGen_Busy(void);

/** @brief Total rising edges emitted since reset. The ground truth for A2. */
uint64_t ENR312_StepGen_TotalPulses(void);

/** @brief Called from TIM2_IRQHandler. */
void ENR312_StepGen_IrqHandler(void);

/**
 * Velocity mode, for closed-loop control (enr312_runner). Signed rate in
 * microsteps/s, positive = DIR pin high. |rate| below 2 stops pulsing but stays
 * in velocity mode. Refused while a counted move is in progress or motion is
 * not permitted. Called from the 500 Hz control ISR.
 */
bool ENR312_StepGen_SetVelocity(double usteps_per_s);

/** Signed microsteps emitted since the last SetOrigin (both modes). */
int32_t ENR312_StepGen_Position(void);
void    ENR312_StepGen_SetOrigin(void);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_STEPGEN_H */

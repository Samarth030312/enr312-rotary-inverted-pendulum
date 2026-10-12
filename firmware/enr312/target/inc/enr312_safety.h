/**
 * @file    enr312_safety.h
 * @brief   ENR312 hardware state machine.  SAFE is the only boot state.
 *
 * The rig can throw a 240 mm arm at a bench. Every path that energises the
 * motor bridges passes through here, and the default at reset is motionless.
 *
 *      SAFE  --arm--> ARMED  --start--> RUNNING
 *        ^              |                  |
 *        |              +-- disarm --------+
 *        |                                 |
 *        +---------- fault/abort ----- FAULT
 *
 * SAFE    L6474 held in reset (bridges high-Z), step clock stopped, no
 *         motion possible. Entered at power-on and on any abort.
 * ARMED   L6474 configured over SPI and ENABLED, step clock stopped.
 *         The motor holds position with torque. Nothing moves.
 * RUNNING step clock permitted; the control law may command motion.
 * FAULT   latched. Bridges disabled and reset asserted. Requires an explicit
 *         clear, which drops to SAFE -- never straight back to RUNNING.
 */

#ifndef ENR312_SAFETY_H
#define ENR312_SAFETY_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ENR312_STATE_SAFE = 0,
    ENR312_STATE_ARMED,
    ENR312_STATE_RUNNING,
    ENR312_STATE_FAULT
} ENR312_State_t;

typedef enum {
    ENR312_FAULT_NONE            = 0,
    ENR312_FAULT_L6474_FLAG      = 1u << 0, /**< FLAG asserted: OC/thermal/UVLO */
    ENR312_FAULT_SPI_TIMEOUT     = 1u << 1, /**< L6474 did not answer           */
    ENR312_FAULT_L6474_ID        = 1u << 2, /**< readback mismatch at init      */
    ENR312_FAULT_ROTOR_LIMIT     = 1u << 3, /**< rotor travel limit exceeded    */
    ENR312_FAULT_PENDULUM_ABORT  = 1u << 4, /**< pendulum past abort angle      */
    ENR312_FAULT_ENCODER_STUCK   = 1u << 5, /**< no counts while commanding     */
    ENR312_FAULT_OPERATOR_ABORT  = 1u << 6, /**< host sent abort                */
    ENR312_FAULT_CTRL_OVERRUN    = 1u << 7  /**< control ISR missed its slot    */
} ENR312_Fault_t;

/** @brief Force SAFE. Asserts L6474 reset, stops the step clock. Idempotent.
 *  Safe to call from an ISR and from a fault path. */
void ENR312_Safety_EnterSafe(void);

/** @brief SAFE -> ARMED. Configures and enables the L6474 over SPI.
 *  @return false if the driver did not respond; state becomes FAULT. */
bool ENR312_Safety_Arm(void);

/** @brief ARMED -> RUNNING. Rejected from any other state. */
bool ENR312_Safety_Start(void);

/** @brief Latch a fault and enter SAFE hardware state immediately.
 *  ISR-safe. Multiple faults OR together. */
void ENR312_Safety_RaiseFault(ENR312_Fault_t f);

/** @brief FAULT -> SAFE. Clears the latch. Never goes straight to RUNNING. */
void ENR312_Safety_ClearFault(void);

ENR312_State_t ENR312_Safety_GetState(void);
uint32_t       ENR312_Safety_GetFaults(void);
const char    *ENR312_Safety_StateName(ENR312_State_t s);

/** @brief True only in RUNNING with no latched fault. The step ISR gates on this. */
bool ENR312_Safety_MotionPermitted(void);

/** True while the L6474 FLAG line is being watched (ARMED/RUNNING only). */
bool ENR312_Safety_FlagWatchActive(void);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_SAFETY_H */

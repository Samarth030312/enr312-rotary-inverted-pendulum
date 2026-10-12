/**
 * @file    enr312_safety.c
 * @brief   The gate every motion path passes through.
 */

#include "enr312_board.h"
#include "enr312_safety.h"
#include "enr312_l6474.h"
#include "enr312_stepgen.h"

static volatile ENR312_State_t s_state  = ENR312_STATE_SAFE;
static volatile uint32_t       s_faults = ENR312_FAULT_NONE;

/* FLAG is watched only while the bridges can be energised (ARMED/RUNNING).
 * FIX 2026-10-12 (first hardware run): the L6474 holds FLAG low after it
 * leaves reset until STATUS is read. Watching FLAG unconditionally made the
 * EXTI handler re-assert reset microseconds after every release, so the driver
 * never answered SPI and ARM failed with faults 0x05. */
static volatile bool s_flag_watch = false;

bool ENR312_Safety_FlagWatchActive(void) { return s_flag_watch; }

void ENR312_Safety_EnterSafe(void)
{
    s_flag_watch = false;              /* reset will move FLAG: not a fault */
    /* Order matters: stop commanding steps, then remove the drive, then assert
     * reset. Reversing this can leave a pulse train arriving at a driver that
     * is mid-reset, which is how phase state gets lost silently. */
    ENR312_StepGen_Stop();
    ENR312_L6474_Disable();
    HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(ENR312_STCK_PORT, ENR312_STCK_PIN, GPIO_PIN_RESET);

    if (s_state != ENR312_STATE_FAULT) {
        s_state = ENR312_STATE_SAFE;
    }
}

bool ENR312_Safety_Arm(void)
{
    if (s_state != ENR312_STATE_SAFE) {
        return false;
    }
    s_flag_watch = false;
    if (!ENR312_L6474_Configure()) {
        ENR312_Safety_RaiseFault(ENR312_FAULT_L6474_ID);
        return false;
    }
    (void)ENR312_L6474_GetStatus();    /* clears the power-up / config flags */
    if (ENR312_L6474_FlagAsserted()) {
        ENR312_Safety_RaiseFault(ENR312_FAULT_L6474_FLAG);
        return false;
    }
    __HAL_GPIO_EXTI_CLEAR_IT(ENR312_FLAG_PIN);   /* forget edges from power-up */
    s_flag_watch = true;               /* from here a FLAG edge is a real fault */
    ENR312_L6474_Enable();
    s_state = ENR312_STATE_ARMED;
    return true;
}

bool ENR312_Safety_Start(void)
{
    if (s_state != ENR312_STATE_ARMED) {
        return false;
    }
    s_state = ENR312_STATE_RUNNING;
    return true;
}

void ENR312_Safety_RaiseFault(ENR312_Fault_t f)
{
    s_flag_watch = false;
    s_faults |= (uint32_t)f;
    s_state   = ENR312_STATE_FAULT;

    /* Inline, not via EnterSafe(): this runs from ISRs and must not depend on
     * the state check there. Hardware goes quiet unconditionally. */
    ENR312_StepGen_Stop();
    ENR312_L6474_Disable();
    HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_RESET);
}

void ENR312_Safety_ClearFault(void)
{
    s_faults = ENR312_FAULT_NONE;
    s_state  = ENR312_STATE_SAFE;
    ENR312_Safety_EnterSafe();
}

ENR312_State_t ENR312_Safety_GetState(void)  { return s_state; }
uint32_t       ENR312_Safety_GetFaults(void) { return s_faults; }

bool ENR312_Safety_MotionPermitted(void)
{
    return (s_state == ENR312_STATE_RUNNING) && (s_faults == ENR312_FAULT_NONE);
}

const char *ENR312_Safety_StateName(ENR312_State_t s)
{
    switch (s) {
    case ENR312_STATE_SAFE:    return "SAFE";
    case ENR312_STATE_ARMED:   return "ARMED";
    case ENR312_STATE_RUNNING: return "RUNNING";
    case ENR312_STATE_FAULT:   return "FAULT";
    default:                   return "?";
    }
}

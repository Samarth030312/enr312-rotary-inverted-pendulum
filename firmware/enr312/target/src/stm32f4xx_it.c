/**
 * @file    stm32f4xx_it.c
 * @brief   ENR312 interrupt vectors.
 *
 * TARGET: ENR312 pendulum. Separate from Core/Src/stm32f4xx_it.c, which belongs
 * to the vehicle and is not compiled into this image.
 *
 * Priorities, most urgent first:
 *   2  EXTI15_10  L6474 FLAG -- overcurrent / thermal / UVLO
 *   4  TIM2       step clock
 *   6  TIM4       control loop
 *  15  SysTick    HAL timebase
 */

#include "enr312_board.h"
#include "enr312_safety.h"
#include "enr312_stepgen.h"
#include "enr312_telemetry.h"

extern void ENR312_ControlTick(void);

void NMI_Handler(void)          { while (1) { } }
void HardFault_Handler(void)    { ENR312_Safety_EnterSafe(); while (1) { } }
void MemManage_Handler(void)    { ENR312_Safety_EnterSafe(); while (1) { } }
void BusFault_Handler(void)     { ENR312_Safety_EnterSafe(); while (1) { } }
void UsageFault_Handler(void)   { ENR312_Safety_EnterSafe(); while (1) { } }
void SVC_Handler(void)          { }
void DebugMon_Handler(void)     { }
void PendSV_Handler(void)       { }
void SysTick_Handler(void)      { HAL_IncTick(); }

/** L6474 FLAG went low: overcurrent, thermal shutdown or undervoltage.
 *  Latch a fault immediately -- this path must not wait for the control loop. */
void EXTI15_10_IRQHandler(void)
{
    if (__HAL_GPIO_EXTI_GET_IT(ENR312_FLAG_PIN) != 0u) {
        __HAL_GPIO_EXTI_CLEAR_IT(ENR312_FLAG_PIN);
        /* Only a fault while the bridges can be on; during reset release and
         * configuration the L6474 holds FLAG low by design. */
        if (ENR312_Safety_FlagWatchActive()) {
            ENR312_Safety_RaiseFault(ENR312_FAULT_L6474_FLAG);
        }
    }
}

void USART2_IRQHandler(void)
{
    ENR312_Telemetry_IrqHandler();
}

void TIM2_IRQHandler(void)
{
    ENR312_StepGen_IrqHandler();
}

void TIM4_IRQHandler(void)
{
    if ((ENR312_CTRL_TIM->SR & TIM_SR_UIF) != 0u) {
        ENR312_CTRL_TIM->SR = (uint16_t)~TIM_SR_UIF;
        ENR312_ControlTick();
    }
}

/**
 * @file    enr312_board.h
 * @brief   ENR312 rotary inverted pendulum -- NUCLEO-F401RE board definition.
 *
 * TARGET: ENR312 pendulum.  This is NOT the vehicle target.
 * See docs/ARCHITECTURE.md.
 *
 * PIN MAP AUTHORITY
 * -----------------
 * Every pin below is transcribed from the UCLA Edukit reference sources in
 * <UCLA Edukit project>/, which the operator has stated is the wiring the
 * physical rig actually follows. Citations are file:line into that tree, rooted
 * at <UCLA Edukit project>/.
 *
 *   Drivers/BSP/X-NUCLEO-IHMxx/x_nucleo_ihm01a1_stm32f4xx.h   (shield pin map)
 *   Projects/.../IHM01A1_ExampleFor1Motor/Src/stm32f4xx_hal_msp.c  (pin modes)
 *   Projects/.../IHM01A1_ExampleFor1Motor/Src/main.c          (TIM3 encoder cfg)
 *
 * These are REFERENCE-DOCUMENTED, not PHYSICALLY-VERIFIED. No continuity
 * measurement has been performed on this rig. See
 * docs/hardware/PRE_POWER_CHECKLIST.md.
 */

#ifndef ENR312_BOARD_H
#define ENR312_BOARD_H

#include "stm32f4xx_hal.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------ */
/* L6474 stepper driver -- X-NUCLEO-IHM01A1                                  */
/* ------------------------------------------------------------------------ */

/** STCK / PWM1 step clock.  Nucleo D9, shield CN5 pin 2.
 *  ihm01a1_stm32f4xx.h:170-172 (PWM_1_PIN = GPIO_PIN_7, PORT = GPIOC).
 *
 *  Driven as GPIO_MODE_OUTPUT_PP and pulsed from the TIM2 update ISR, NOT as a
 *  timer alternate function. This is forced by the hardware: PC7 has no TIM2
 *  alternate function on STM32F401, so the pin physically cannot be driven by
 *  TIM2 in AF mode. The UCLA MSP reaches the same conclusion explicitly --
 *  stm32f4xx_hal_msp.c:149-153 sets GPIO_MODE_OUTPUT_PP with the
 *  `GPIO_InitStruct.Alternate` line commented out, and enables the TIM2
 *  interrupt instead. docs/hardware/WIRING_MAP.md:52 already records this. */
#define ENR312_STCK_PORT        GPIOC
#define ENR312_STCK_PIN         GPIO_PIN_7

/** DIR1 direction.  Nucleo D7, shield CN9 pin 8.  ihm01a1_stm32f4xx.h:185-187 */
#define ENR312_DIR_PORT         GPIOA
#define ENR312_DIR_PIN          GPIO_PIN_8

/** STBY/RESET, ACTIVE LOW.  Nucleo D8, shield CN5 pin 1.
 *  ihm01a1_stm32f4xx.h:200-202.  LOW = L6474 held in reset = bridges off. */
#define ENR312_L6474_RESET_PORT GPIOA
#define ENR312_L6474_RESET_PIN  GPIO_PIN_9

/** FLAG fault output, ACTIVE LOW, open drain.  Nucleo D2, shield CN9 pin 3.
 *  ihm01a1_stm32f4xx.h:165-167.  Whether the shield fits a pull-up is not
 *  documented (docs/hardware/SOURCE_RECONCILIATION.md:211 -- UNKNOWN), so the
 *  internal pull-up is enabled here. That is correct either way. */
#define ENR312_FLAG_PORT        GPIOA
#define ENR312_FLAG_PIN         GPIO_PIN_10
#define ENR312_FLAG_EXTI_IRQn   EXTI15_10_IRQn

/** SPI1 chip select, ACTIVE LOW.  Nucleo D10, shield CN5 pin 3.
 *  ihm01a1_stm32f4xx.h:205-207.
 *  NOTE: CS routing is resistor-selectable on the IHM01A1 (R15/R25).  PB6 is
 *  the FACTORY DEFAULT population. See SOURCE_RECONCILIATION.md:120-141. */
#define ENR312_CS_PORT          GPIOB
#define ENR312_CS_PIN           GPIO_PIN_6

/** SPI1: SCK PA5 (D13), MISO PA6 (D12), MOSI PA7 (D11).  AF5.
 *  ihm01a1_stm32f4xx.h:218-252.
 *  NOTE: SCK routing is also resistor-selectable (R23/R24); PA5 is the FACTORY
 *  DEFAULT.  PA5 is additionally the Nucleo LD2 green LED, so LD2 will flicker
 *  with SPI traffic. That is expected and is not a fault. It also means this
 *  target has NO heartbeat LED -- liveness is reported over USART2 instead. */
#define ENR312_SPI_PORT         GPIOA
#define ENR312_SPI_SCK_PIN      GPIO_PIN_5
#define ENR312_SPI_MISO_PIN     GPIO_PIN_6
#define ENR312_SPI_MOSI_PIN     GPIO_PIN_7
#define ENR312_SPI_AF           GPIO_AF5_SPI1

/* ------------------------------------------------------------------------ */
/* LPD3806-600BM-G5-24C quadrature encoder -- pendulum angle                  */
/* ------------------------------------------------------------------------ */

/** Encoder A/B on TIM3_CH1/CH2, AF2, with INTERNAL PULL-UPS.
 *  stm32f4xx_hal_msp.c:214-227.  The UCLA source carries an explicit comment at
 *  :221-223 -- "Pull Up Set for Encoder with Open Collector Output".
 *
 *  ELECTRICAL SAFETY, UNRESOLVED: the encoder is a 5 V open-collector device.
 *  With an internal pull-up to VDD the pin is pulled to 3.3 V and the encoder
 *  only sinks -- so no 5 V is presented to the pin PROVIDED no external pull-up
 *  to +5 V is fitted anywhere in the harness. That proviso has NOT been
 *  measured on this rig. See docs/hardware/PRE_POWER_CHECKLIST.md check E2. */
#define ENR312_ENC_PORT         GPIOB
#define ENR312_ENC_A_PIN        GPIO_PIN_4
#define ENR312_ENC_B_PIN        GPIO_PIN_5
#define ENR312_ENC_AF           GPIO_AF2_TIM3
#define ENR312_ENC_TIM          TIM3

/* ------------------------------------------------------------------------ */
/* Telemetry -- USART2 to the on-board ST-LINK virtual COM port               */
/* ------------------------------------------------------------------------ */
#define ENR312_UART_PORT        GPIOA
#define ENR312_UART_TX_PIN      GPIO_PIN_2
#define ENR312_UART_RX_PIN      GPIO_PIN_3
#define ENR312_UART_AF          GPIO_AF7_USART2
#define ENR312_UART_BAUD        115200u   /* UM2717 rate; byte loss once blamed on 460800 was two programs sharing the port */

/* ------------------------------------------------------------------------ */
/* Timing                                                                     */
/* ------------------------------------------------------------------------ */

/** Step-clock timer. TIM2, PSC = 1024, matching the UCLA TIMER_PRESCALER
 *  (ihm01a1_stm32f4xx.h:143).  84 MHz / 1024 = 82031.25 Hz, which is exactly
 *  ENR312_STEP_TICK_HZ in ../inc/enr312_rig_config.h. One update event = one
 *  step pulse, so ARR from ENR312_Rotor_ComputeStepTimerARR() applies directly. */
#define ENR312_STEP_TIM         TIM2
#define ENR312_STEP_TIM_PSC     1024u
#define ENR312_STEP_TIM_IRQn    TIM2_IRQn

/** Control-loop timer. TIM4, 84 MHz / 8400 = 10 kHz, ARR 20 -> 500 Hz,
 *  i.e. Ts = 2 ms = CONTROL_PERIOD_S in ../inc/enr312_rig_config.h. */
#define ENR312_CTRL_TIM         TIM4
#define ENR312_CTRL_TIM_PSC     8400u
#define ENR312_CTRL_TIM_ARR     20u
#define ENR312_CTRL_TIM_IRQn    TIM4_IRQn

/** STCK pulse width, in CPU cycles at 84 MHz. The L6474 datasheet minimum
 *  high time is well under 1 us; 84 cycles = 1.0 us is a generous margin and
 *  still only 8 % of the shortest step period this firmware will command. */
#define ENR312_STCK_PULSE_CYCLES 84u

/** Firmware identity. Deliberately NOT __DATE__/__TIME__: those make the image
 *  non-reproducible, so a rebuild would change the ELF hash and the operator
 *  could no longer verify by SHA which image they are about to flash. Bump this
 *  string when the target changes. */
#define ENR312_FW_VERSION "enr312-target-2.3.0 (protocol 5: Tutorials 2-10, PEND, lab, swing-up, pendulum target; 115200 baud)"

void ENR312_Board_Init(void);
void ENR312_Board_SystemClockConfig(void);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_BOARD_H */

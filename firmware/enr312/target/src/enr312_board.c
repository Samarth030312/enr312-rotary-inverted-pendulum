/**
 * @file    enr312_board.c
 * @brief   ENR312 target: clock tree and peripheral bring-up.
 *
 * Pin modes and peripheral settings here mirror firmware/enr312/target/enr312.ioc
 * line for line. That IOC is a design record for CubeMX; this file is what
 * actually builds. If you change one, change the other -- the Makefile's
 * `make ioc-check` target diffs the two.
 */

#include "enr312_board.h"
#include "enr312_safety.h"

TIM_HandleTypeDef henc_tim3;
UART_HandleTypeDef huart2_enr312;

/**
 * @brief 84 MHz from HSI.
 *
 * HSI, not HSE. The Nucleo-F401RE ships with no crystal fitted; HSE would mean
 * the 8 MHz MCO from the ST-LINK, which requires solder-bridge work not done on
 * this board. The vehicle target already runs 84 MHz from HSI on this exact
 * hardware, so this path is known to start.
 *
 * CONSEQUENCE, and it matters for EXP001: HSI is factory-trimmed to +/-1 % at
 * 25 C and drifts further over temperature. Every step RATE and every sample
 * INTERVAL in this firmware inherits that error. Step COUNTS are unaffected --
 * a pulse is a pulse -- so commanded rotor ANGLE is not affected, but any
 * measured frequency, velocity or time constant carries a systematic scale
 * error of up to 1 %. Recorded in docs/hardware/PRE_POWER_CHECKLIST.md as a
 * calibration item, not silently absorbed.
 */
void ENR312_Board_SystemClockConfig(void)
{
    RCC_OscInitTypeDef osc = {0};
    RCC_ClkInitTypeDef clk = {0};

    __HAL_RCC_PWR_CLK_ENABLE();
    __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE2);

    osc.OscillatorType      = RCC_OSCILLATORTYPE_HSI;
    osc.HSIState            = RCC_HSI_ON;
    osc.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
    osc.PLL.PLLState        = RCC_PLL_ON;
    osc.PLL.PLLSource       = RCC_PLLSOURCE_HSI;
    osc.PLL.PLLM            = 8;
    osc.PLL.PLLN            = 84;
    osc.PLL.PLLP            = RCC_PLLP_DIV2;
    osc.PLL.PLLQ            = 4;
    if (HAL_RCC_OscConfig(&osc) != HAL_OK) {
        ENR312_Safety_EnterSafe();
        while (1) { }
    }

    clk.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK |
                         RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clk.SYSCLKSource   = RCC_SYSCLKSOURCE_PLLCLK;
    clk.AHBCLKDivider  = RCC_SYSCLK_DIV1;
    clk.APB1CLKDivider = RCC_HCLK_DIV2;   /* PCLK1 42 MHz, TIM2/3/4 clk 84 MHz */
    clk.APB2CLKDivider = RCC_HCLK_DIV1;   /* PCLK2 84 MHz, SPI1                */
    if (HAL_RCC_ClockConfig(&clk, FLASH_LATENCY_2) != HAL_OK) {
        ENR312_Safety_EnterSafe();
        while (1) { }
    }
}

/**
 * @brief GPIO, encoder timer and control timer.
 *
 * ORDER IS A SAFETY PROPERTY. The L6474 reset pin is driven LOW (device held in
 * reset, bridges high-Z) in the same statement that makes it an output, before
 * anything else is configured and before any clock reaches the step timer. A
 * stepper that is briefly energised in an unknown direction during boot is how
 * benches get damaged.
 */
void ENR312_Board_Init(void)
{
    GPIO_InitTypeDef g = {0};

    __HAL_RCC_GPIOA_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();
    __HAL_RCC_GPIOC_CLK_ENABLE();

    /* --- L6474 held in reset FIRST, before it can be told to do anything --- */
    HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_RESET);
    g.Pin   = ENR312_L6474_RESET_PIN;
    g.Mode  = GPIO_MODE_OUTPUT_PP;
    g.Pull  = GPIO_NOPULL;
    g.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(ENR312_L6474_RESET_PORT, &g);
    HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_RESET);

    /* --- CS idle high (deselected) before SPI exists --- */
    HAL_GPIO_WritePin(ENR312_CS_PORT, ENR312_CS_PIN, GPIO_PIN_SET);
    g.Pin = ENR312_CS_PIN;
    HAL_GPIO_Init(ENR312_CS_PORT, &g);
    HAL_GPIO_WritePin(ENR312_CS_PORT, ENR312_CS_PIN, GPIO_PIN_SET);

    /* --- STCK low, DIR low: defined, motionless --- */
    HAL_GPIO_WritePin(ENR312_STCK_PORT, ENR312_STCK_PIN, GPIO_PIN_RESET);
    g.Pin   = ENR312_STCK_PIN;
    g.Speed = GPIO_SPEED_FREQ_VERY_HIGH;   /* fast edges for the step clock */
    HAL_GPIO_Init(ENR312_STCK_PORT, &g);

    HAL_GPIO_WritePin(ENR312_DIR_PORT, ENR312_DIR_PIN, GPIO_PIN_RESET);
    g.Pin   = ENR312_DIR_PIN;
    g.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(ENR312_DIR_PORT, &g);

    /* --- FLAG: input, pull-up, falling-edge interrupt (open drain, active low) --- */
    g.Pin  = ENR312_FLAG_PIN;
    g.Mode = GPIO_MODE_IT_FALLING;
    g.Pull = GPIO_PULLUP;
    HAL_GPIO_Init(ENR312_FLAG_PORT, &g);
    HAL_NVIC_SetPriority(ENR312_FLAG_EXTI_IRQn, 2, 0);  /* above the control loop */
    HAL_NVIC_EnableIRQ(ENR312_FLAG_EXTI_IRQn);

    /* --- Encoder A/B: AF2/TIM3, pull-ups for the open-collector encoder --- */
    g.Pin       = ENR312_ENC_A_PIN | ENR312_ENC_B_PIN;
    g.Mode      = GPIO_MODE_AF_PP;
    g.Pull      = GPIO_PULLUP;
    g.Speed     = GPIO_SPEED_FREQ_VERY_HIGH;
    g.Alternate = ENR312_ENC_AF;
    HAL_GPIO_Init(ENR312_ENC_PORT, &g);

    /* --- USART2 to the ST-LINK VCP --- */
    g.Pin       = ENR312_UART_TX_PIN | ENR312_UART_RX_PIN;
    g.Mode      = GPIO_MODE_AF_PP;
    g.Pull      = GPIO_NOPULL;
    g.Alternate = ENR312_UART_AF;
    HAL_GPIO_Init(ENR312_UART_PORT, &g);

    /* --- Control-loop timer: 500 Hz --- */
    __HAL_RCC_TIM4_CLK_ENABLE();
    ENR312_CTRL_TIM->PSC = ENR312_CTRL_TIM_PSC - 1u;
    ENR312_CTRL_TIM->ARR = ENR312_CTRL_TIM_ARR - 1u;
    ENR312_CTRL_TIM->DIER = TIM_DIER_UIE;
    ENR312_CTRL_TIM->SR  = 0;
    HAL_NVIC_SetPriority(ENR312_CTRL_TIM_IRQn, 6, 0);
    HAL_NVIC_EnableIRQ(ENR312_CTRL_TIM_IRQn);
}

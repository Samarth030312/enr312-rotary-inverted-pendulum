/**
 * @file    enr312_encoder_hw.c
 * @brief   TIM3 X4 quadrature decode, configured exactly as the UCLA reference.
 */

#include "enr312_board.h"
#include "enr312_encoder_hw.h"

void ENR312_EncoderHw_Init(ENR312_Encoder_t *e, int32_t polarity)
{
    __HAL_RCC_TIM3_CLK_ENABLE();

    ENR312_ENC_TIM->CR1  = 0;
    ENR312_ENC_TIM->PSC  = 0;        /* no prescale: every edge counts       */
    ENR312_ENC_TIM->ARR  = 0xFFFFu;  /* free-running 16-bit; wraps are handled
                                      * in software by ENR312_Encoder_Update */
    /* CC1 and CC2 as inputs mapped directly to TI1/TI2, no filter, no prescale */
    ENR312_ENC_TIM->CCMR1 = TIM_CCMR1_CC1S_0 | TIM_CCMR1_CC2S_0;
    /* Both edges of both channels -> X4 decode. Non-inverted, per the
     * reference's TIM_ICPOLARITY_RISING on both channels. */
    ENR312_ENC_TIM->CCER  = 0;
    /* SMS = 011: counter clocked on both TI1 and TI2 edges (ENCODERMODE_TI12) */
    ENR312_ENC_TIM->SMCR  = TIM_SMCR_SMS_0 | TIM_SMCR_SMS_1;
    ENR312_ENC_TIM->CNT   = 0;
    ENR312_ENC_TIM->CR1  |= TIM_CR1_CEN;

    ENR312_Encoder_Init(e, ENR312_EncoderHw_ReadRaw(), polarity);
}

uint16_t ENR312_EncoderHw_ReadRaw(void)
{
    return (uint16_t)ENR312_ENC_TIM->CNT;
}

void ENR312_EncoderHw_Sample(ENR312_Encoder_t *e)
{
    ENR312_Encoder_Update(e, ENR312_EncoderHw_ReadRaw());
}

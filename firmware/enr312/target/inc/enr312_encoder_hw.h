/**
 * @file    enr312_encoder_hw.h
 * @brief   TIM3 quadrature front end feeding the HAL-free decoder.
 *
 * The split is deliberate. This file knows what a timer is; enr312_encoder.c
 * does not, which is what keeps 276 host tests possible without hardware.
 * TIM3 is configured exactly as the UCLA reference configures it
 * (main.c MX_TIM3_Init): PSC 0, ARR 65535, TIM_ENCODERMODE_TI12, both inputs
 * DIRECTTI, rising polarity, no filter -- i.e. X4 decode, 2400 counts/rev.
 */

#ifndef ENR312_ENCODER_HW_H
#define ENR312_ENCODER_HW_H

#include <stdint.h>
#include "enr312_encoder.h"

#ifdef __cplusplus
extern "C" {
#endif

/** @brief Start TIM3 in encoder mode and latch the origin at the present count. */
void ENR312_EncoderHw_Init(ENR312_Encoder_t *e, int32_t polarity);

/** @brief Raw 16-bit TIM3 counter. */
uint16_t ENR312_EncoderHw_ReadRaw(void);

/** @brief Sample the counter and advance the decoder. Call at the control rate. */
void ENR312_EncoderHw_Sample(ENR312_Encoder_t *e);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_ENCODER_HW_H */

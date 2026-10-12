/**
 * @file    enr312_telemetry.h
 * @brief   USART2 line telemetry and single-character operator commands.
 *
 * Blocking, polled, ASCII. Deliberately dull: the ST-LINK VCP is the only
 * channel this target has, and a control experiment whose telemetry can itself
 * perturb timing is not measuring what it claims to. Transmission happens from
 * the main loop, never from the control ISR.
 */

#ifndef ENR312_TELEMETRY_H
#define ENR312_TELEMETRY_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void ENR312_Telemetry_Init(void);
void ENR312_Telemetry_Write(const char *s);
void ENR312_Telemetry_Printf(const char *fmt, ...);

/** @brief Non-blocking read of one command character. @return 0 if none. */
char ENR312_Telemetry_ReadChar(void);

/** USART2 interrupt: receive into the ring (called from USART2_IRQHandler). */
void ENR312_Telemetry_IrqHandler(void);

/** Receive overruns, framing/noise errors and ring overflows since boot. */
uint32_t ENR312_Telemetry_RxErrors(void);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_TELEMETRY_H */

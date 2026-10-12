/**
 * @file    enr312_telemetry.c
 * @brief   Polled USART2 ASCII telemetry over the ST-LINK VCP.
 */

#include "enr312_board.h"
#include "enr312_telemetry.h"
#include <stdarg.h>
#include <stdio.h>

extern UART_HandleTypeDef huart2_enr312;

/* Interrupt-driven receive ring. The USART has a one-byte data register; the
 * main loop blocks for ~1.3 ms while it transmits a stream line, and at
 * 115200 baud a byte arrives every 87 us, so polled reception loses most of a
 * '$' command line. The RXNE interrupt (priority 3, above the control loop)
 * moves each byte here within ~1 us. */
#define RX_SIZE 256u
static volatile uint8_t  s_rx[RX_SIZE];
static volatile uint32_t s_rx_head = 0, s_rx_tail = 0;
static volatile uint32_t s_rx_errors = 0;

void ENR312_Telemetry_Init(void)
{
    __HAL_RCC_USART2_CLK_ENABLE();

    huart2_enr312.Instance          = USART2;
    huart2_enr312.Init.BaudRate     = ENR312_UART_BAUD;
    huart2_enr312.Init.WordLength   = UART_WORDLENGTH_8B;
    huart2_enr312.Init.StopBits     = UART_STOPBITS_1;
    huart2_enr312.Init.Parity       = UART_PARITY_NONE;
    huart2_enr312.Init.Mode         = UART_MODE_TX_RX;
    huart2_enr312.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
    huart2_enr312.Init.OverSampling = UART_OVERSAMPLING_16;
    (void)HAL_UART_Init(&huart2_enr312);

    USART2->CR1 |= USART_CR1_RXNEIE;
    HAL_NVIC_SetPriority(USART2_IRQn, 3, 0);
    HAL_NVIC_EnableIRQ(USART2_IRQn);
}

void ENR312_Telemetry_IrqHandler(void)
{
    uint32_t sr = USART2->SR;
    if ((sr & (USART_SR_RXNE | USART_SR_ORE | USART_SR_FE | USART_SR_NE)) != 0u) {
        uint8_t b = (uint8_t)USART2->DR;          /* SR-then-DR read clears the flags */
        if ((sr & (USART_SR_ORE | USART_SR_FE | USART_SR_NE)) != 0u) {
            s_rx_errors++;
        }
        uint32_t next = (s_rx_head + 1u) % RX_SIZE;
        if (next != s_rx_tail) {
            s_rx[s_rx_head] = b;
            s_rx_head = next;
        } else {
            s_rx_errors++;                       /* ring full: byte dropped */
        }
    }
}

uint32_t ENR312_Telemetry_RxErrors(void)
{
    return s_rx_errors;
}

void ENR312_Telemetry_Write(const char *s)
{
    size_t n = 0;
    while (s[n] != '\0') {
        n++;
    }
    (void)HAL_UART_Transmit(&huart2_enr312, (uint8_t *)s, (uint16_t)n, 200u);
}

void ENR312_Telemetry_Printf(const char *fmt, ...)
{
    static char buf[192];
    va_list ap;
    int n;

    va_start(ap, fmt);
    n = vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);

    if (n > 0) {
        if ((size_t)n >= sizeof buf) {
            n = (int)sizeof buf - 1;
        }
        (void)HAL_UART_Transmit(&huart2_enr312, (uint8_t *)buf, (uint16_t)n, 200u);
    }
}

char ENR312_Telemetry_ReadChar(void)
{
    if (s_rx_tail == s_rx_head) {
        return '\0';
    }
    char c = (char)s_rx[s_rx_tail];
    s_rx_tail = (s_rx_tail + 1u) % RX_SIZE;
    return c;
}

/**
 * @file    enr312_l6474.c
 * @brief   Bare-register SPI1 master and minimal L6474 register access.
 *
 * SPI mode 3 (CPOL=1, CPHA=1), MSB first, 8-bit, software NSS, PCLK2/32 =
 * 2.625 MHz -- transcribed from L6474_Board_SpiInit() in the UCLA reference.
 *
 * The L6474 protocol is one byte per CS pulse: CS low, one byte, CS high.
 * Multi-byte register values are therefore several separate CS pulses, not one
 * long burst. Getting this wrong is the classic L6474 bring-up failure -- the
 * device silently misparses and returns plausible-looking garbage.
 */

#include "enr312_board.h"
#include "enr312_l6474.h"

/* Register widths in bytes, indexed by register address. 0 = not a register. */
static uint8_t reg_width(uint8_t reg)
{
    switch (reg) {
    case L6474_REG_ABS_POS:   return 3;
    case L6474_REG_EL_POS:    return 2;
    case L6474_REG_MARK:      return 3;
    case L6474_REG_STATUS:
    case L6474_REG_CONFIG:    return 2;   /* 16-bit; ref l6474.c:322,460 */
    case L6474_REG_TVAL:
    case L6474_REG_T_FAST:
    case L6474_REG_TON_MIN:
    case L6474_REG_TOFF_MIN:
    case L6474_REG_ADC_OUT:
    case L6474_REG_OCD_TH:
    case L6474_REG_STEP_MODE:
    case L6474_REG_ALARM_EN:  return 1;
    default:                  return 0;
    }
}

void ENR312_L6474_SpiInit(void)
{
    GPIO_InitTypeDef g = {0};

    __HAL_RCC_SPI1_CLK_ENABLE();

    g.Pin       = ENR312_SPI_SCK_PIN | ENR312_SPI_MISO_PIN | ENR312_SPI_MOSI_PIN;
    g.Mode      = GPIO_MODE_AF_PP;
    g.Pull      = GPIO_NOPULL;
    g.Speed     = GPIO_SPEED_FREQ_HIGH;
    g.Alternate = ENR312_SPI_AF;
    HAL_GPIO_Init(ENR312_SPI_PORT, &g);

    /* CPOL=1 CPHA=1, master, software NSS, fPCLK/32, MSB first, 8-bit. */
    SPI1->CR1 = 0;
    SPI1->CR1 = SPI_CR1_MSTR | SPI_CR1_SSM | SPI_CR1_SSI |
                SPI_CR1_CPOL | SPI_CR1_CPHA |
                (4u << SPI_CR1_BR_Pos);       /* 100b = fPCLK/32 = 2.625 MHz */
    SPI1->CR2 = 0;
    SPI1->CR1 |= SPI_CR1_SPE;
}

/** @brief One full-duplex byte. Bounded wait -- never spins forever. */
static uint8_t spi_xfer(uint8_t tx)
{
    uint32_t guard = 100000u;

    if (SPI1->SR & SPI_SR_RXNE) {                 /* drop any stale byte */
        (void)*(volatile uint8_t *)&SPI1->DR;
    }
    while (!(SPI1->SR & SPI_SR_TXE) && --guard) { }
    *(volatile uint8_t *)&SPI1->DR = tx;

    guard = 100000u;
    while (!(SPI1->SR & SPI_SR_RXNE) && --guard) { }
    uint8_t rx = *(volatile uint8_t *)&SPI1->DR;

    guard = 100000u;                              /* last clock edge done   */
    while ((SPI1->SR & SPI_SR_BSY) && --guard) { }
    return rx;
}

/* L6474 SPI timing (datasheet): CS low before the first clock >= 350 ns and
 * CS high between bytes >= 800 ns (tdisCS). Two back-to-back GPIO writes give
 * only tens of ns, which can make the device miss bytes -- suspected cause of
 * ARM failing with faults 0x05 on the first hardware run (2026-10-12).
 * ~1 us here (84 MHz, a few cycles per iteration). */
static void cs_wait(void)
{
    for (volatile uint32_t i = 0; i < 25u; i++) { }
}

/** @brief One byte inside its own CS pulse, as the L6474 daisy-chain expects. */
/* Chip-select in use: the factory default (PB6/D10) unless the 'P' scan
 * selects UM1857's alternative (PA4/A2). */
static GPIO_TypeDef *s_cs_port = ENR312_CS_PORT;
static uint16_t      s_cs_pin  = ENR312_CS_PIN;

static uint8_t l6474_byte(uint8_t tx)
{
    uint8_t rx;
    HAL_GPIO_WritePin(s_cs_port, s_cs_pin, GPIO_PIN_RESET);
    cs_wait();
    rx = spi_xfer(tx);
    HAL_GPIO_WritePin(s_cs_port, s_cs_pin, GPIO_PIN_SET);
    cs_wait();
    return rx;
}

/* UM1857 Tables 3/4: CS is R25 (default, CN5-3 = D10 = PB6) or R15
 * (CN8-3 = A2 = PA4); SCK is R23 (default, CN5-6 = D13 = PA5) or R24
 * (CN9-4 = D3 = PB3, also SPI1_SCK on AF5). The unused pin of each pair is
 * left as a high-impedance input. */
void ENR312_L6474_UsePins(bool cs_alt, bool sck_alt)
{
    GPIO_InitTypeDef g = {0};
    __HAL_RCC_GPIOA_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();

    g.Mode = GPIO_MODE_INPUT; g.Pull = GPIO_NOPULL;            /* release both */
    g.Pin = GPIO_PIN_6; HAL_GPIO_Init(GPIOB, &g);
    g.Pin = GPIO_PIN_4; HAL_GPIO_Init(GPIOA, &g);
    g.Pin = GPIO_PIN_5; HAL_GPIO_Init(GPIOA, &g);
    g.Pin = GPIO_PIN_3; HAL_GPIO_Init(GPIOB, &g);

    s_cs_port = cs_alt ? GPIOA : GPIOB;
    s_cs_pin  = cs_alt ? GPIO_PIN_4 : GPIO_PIN_6;
    HAL_GPIO_WritePin(s_cs_port, s_cs_pin, GPIO_PIN_SET);
    g.Mode = GPIO_MODE_OUTPUT_PP; g.Speed = GPIO_SPEED_FREQ_HIGH; g.Pin = s_cs_pin;
    HAL_GPIO_Init(s_cs_port, &g);

    g.Mode = GPIO_MODE_AF_PP; g.Alternate = GPIO_AF5_SPI1;
    if (sck_alt) { g.Pin = GPIO_PIN_3; HAL_GPIO_Init(GPIOB, &g); }
    else         { g.Pin = GPIO_PIN_5; HAL_GPIO_Init(GPIOA, &g); }
}

void ENR312_L6474_SetParam(uint8_t reg, uint32_t value)
{
    uint8_t n = reg_width(reg);
    if (n == 0u) {
        return;
    }
    (void)l6474_byte((uint8_t)(L6474_CMD_SET_PARAM | reg));
    while (n--) {
        (void)l6474_byte((uint8_t)((value >> (8u * n)) & 0xFFu));
    }
}

uint32_t ENR312_L6474_GetParam(uint8_t reg)
{
    uint8_t  n = reg_width(reg);
    uint32_t v = 0;
    if (n == 0u) {
        return 0;
    }
    (void)l6474_byte((uint8_t)(L6474_CMD_GET_PARAM | reg));
    while (n--) {
        v = (v << 8) | l6474_byte(L6474_CMD_NOP);
    }
    return v;
}

void ENR312_L6474_Enable(void)
{
    (void)l6474_byte(L6474_CMD_ENABLE);
}

void ENR312_L6474_Disable(void)
{
    (void)l6474_byte(L6474_CMD_DISABLE);
}

uint16_t ENR312_L6474_GetStatus(void)
{
    uint16_t s;
    (void)l6474_byte(L6474_CMD_GET_STATUS);
    s  = (uint16_t)((uint16_t)l6474_byte(L6474_CMD_NOP) << 8);
    s |= l6474_byte(L6474_CMD_NOP);
    return s;
}

bool ENR312_L6474_FlagAsserted(void)
{
    return HAL_GPIO_ReadPin(ENR312_FLAG_PORT, ENR312_FLAG_PIN) == GPIO_PIN_RESET;
}

/**
 * @brief Release reset, configure, verify, leave DISABLED.
 *
 * Parameter values are the UCLA reference's, from l6474_target_config.h:
 * TVAL 800 mA, OCD_TH 2250 mA, STEP_SEL 1/16. The 1/16 divisor is the same
 * number as MICROSTEP_DIVISOR in ../inc/enr312_rig_config.h -- if these ever
 * disagree the rotor angle model is wrong by exactly that ratio, so the check
 * below is not decoration.
 *
 * Verification is a readback of STEP_MODE. If the SPI wiring is dead, reads
 * return 0x00 or 0xFF and the comparison fails, which is the point: the caller
 * must not proceed to energise a driver it cannot talk to.
 */
bool ENR312_L6474_Configure(void)
{
    uint32_t readback;

    /* Release reset and let the device come up. */
    HAL_GPIO_WritePin(ENR312_L6474_RESET_PORT, ENR312_L6474_RESET_PIN, GPIO_PIN_SET);
    HAL_Delay(10);

    (void)ENR312_L6474_GetStatus();   /* clear any power-on flags */

    /* TVAL: 800 mA. Register LSB is 31.25 mA -> 800/31.25 - 1 = 24. */
    ENR312_L6474_SetParam(L6474_REG_TVAL, 24u);
    /* OCD_TH: 2250 mA -> (2250/375) - 1 = 5. */
    ENR312_L6474_SetParam(L6474_REG_OCD_TH, 5u);
    /* STEP_MODE: keep the upper bits as the device reports them, set only
     * STEP_SEL = 1/16 (0x04): the UCLA reference's read-modify-write
     * (Drivers/BSP/Components/l6474/l6474.c:1004-1007). */
    ENR312_L6474_SetParam(L6474_REG_STEP_MODE,
                          (ENR312_L6474_GetParam(L6474_REG_STEP_MODE) & 0xF8u) | 0x04u);
    /* TON_MIN / TOFF_MIN 3 us, T_FAST as reference default. */
    ENR312_L6474_SetParam(L6474_REG_TON_MIN,  0x29u);
    ENR312_L6474_SetParam(L6474_REG_TOFF_MIN, 0x29u);
    ENR312_L6474_SetParam(L6474_REG_T_FAST,   0x19u);
    /* ALARM_EN: overcurrent, thermal shutdown, UVLO, switch, wrong command. */
    ENR312_L6474_SetParam(L6474_REG_ALARM_EN, 0xFFu);
    /* CONFIG: internal oscillator, TOFF 44 us, OC shutdown enabled. */
    ENR312_L6474_SetParam(L6474_REG_CONFIG,   0x2E88u);

    readback = ENR312_L6474_GetParam(L6474_REG_STEP_MODE);
    if ((readback & 0x07u) != 0x04u) {
        return false;    /* not talking, or not in 1/16 microstepping */
    }
    return true;
}

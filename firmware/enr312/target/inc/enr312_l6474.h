/**
 * @file    enr312_l6474.h
 * @brief   Minimal L6474 driver over bare-register SPI1.
 *
 * WHY NOT THE ST BSP: the full BSP in <UCLA Edukit project>/ carries its
 * own motion planner, speed profile and position counter. ENR312 must not have
 * a second, hidden position model competing with ENR312_Rotor_t -- that module
 * IS the actuation-chain memory and its correctness is the whole of EXP001
 * assumption A2. So this driver does configuration and enable/disable only.
 * Step pulses come from enr312_stepgen.c; position comes from enr312_rotor.c.
 *
 * WHY NOT HAL_SPI: Drivers/STM32F4xx_HAL_Driver/ in this repository contains no
 * stm32f4xx_hal_spi.c -- CubeMX never copied it, because the vehicle has
 * no SPI device. Adding it would mean writing into Drivers/, which is vehicle project
 * territory. A one-device, one-byte-at-a-time SPI master is ~40 lines of
 * register code, so this target uses that instead and leaves Drivers/ alone.
 *
 * SPI mode is taken from the UCLA reference L6474_Board_SpiInit():
 * CPOL=1, CPHA=1 (mode 3), 8-bit, MSB first, software NSS, PCLK2/32.
 * <UCLA Edukit project>/.../x_nucleo_ihm01a1_stm32f4xx.c
 */

#ifndef ENR312_L6474_H
#define ENR312_L6474_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* L6474 register addresses (datasheet Table 5) */
#define L6474_REG_ABS_POS       0x01u
#define L6474_REG_EL_POS        0x02u
#define L6474_REG_MARK          0x03u
#define L6474_REG_TVAL          0x09u
#define L6474_REG_T_FAST        0x0Eu
#define L6474_REG_TON_MIN       0x0Fu
#define L6474_REG_TOFF_MIN      0x10u
#define L6474_REG_ADC_OUT       0x12u
#define L6474_REG_OCD_TH        0x13u
#define L6474_REG_STEP_MODE     0x16u
#define L6474_REG_ALARM_EN      0x17u
#define L6474_REG_CONFIG        0x18u
#define L6474_REG_STATUS        0x19u

/* Commands (datasheet Table 4) */
#define L6474_CMD_NOP           0x00u
#define L6474_CMD_SET_PARAM     0x00u
#define L6474_CMD_GET_PARAM     0x20u
#define L6474_CMD_ENABLE        0xB8u
#define L6474_CMD_DISABLE       0xA8u
#define L6474_CMD_GET_STATUS    0xD0u

/** @brief Bring up SPI1 and the CS pin. Does not touch the L6474. */
void ENR312_L6474_SpiInit(void);

/** @brief Configure the device from reset: TVAL, OCD_TH, STEP_MODE 1/16, etc.
 *  Leaves the bridges DISABLED.
 *  @return false if the device did not respond plausibly. */
bool ENR312_L6474_Configure(void);

/** @brief Energise the bridges. Motor holds position with torque. */
void ENR312_L6474_Enable(void);

/** @brief De-energise the bridges (high-Z). Motor freewheels. */
void ENR312_L6474_Disable(void);

/** @brief Read and clear the STATUS register. */
uint16_t ENR312_L6474_GetStatus(void);

/** @brief True while the FLAG pin is asserted (low). */
bool ENR312_L6474_FlagAsserted(void);

/** Select chip-select / clock routing (UM1857 Tables 3, 4); false = factory default. */
void ENR312_L6474_UsePins(bool cs_alt, bool sck_alt);

uint32_t ENR312_L6474_GetParam(uint8_t reg);
void     ENR312_L6474_SetParam(uint8_t reg, uint32_t value);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_L6474_H */

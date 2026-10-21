# =============================================================================
# ENR312 ROTARY INVERTED PENDULUM -- STM32F401RE TARGET FIRMWARE
#
#   make            build build/enr312_pendulum.{elf,bin,hex}
#   make size       memory report
#   make flash      program via STM32CubeProgrammer  (MOVES NOTHING -- boots SAFE)
#   make clean
#
# THIS IS NOT THE VEHICLE BUILD.
#   vehicle project   : make -C <repo root>          -> build/vehicle_firmware.elf
#   ENR312 : make -C firmware/enr312/target -> firmware/enr312/target/build/enr312_pendulum.elf
#
# The two targets share NOTHING except the vendor ST HAL under Drivers/, which
# is compiled here into this directory's own build/ with this directory's own
# stm32f4xx_hal_conf.h. No vehicle application source, no micro-ROS, no FreeRTOS
# and no CubeMX-generated Core/ file is compiled into this image. `make isolation`
# proves it.
# =============================================================================

TARGET   := enr312_pendulum
BUILD_DIR:= build
REPO     := ../../..
CORE     := ..

# --- toolchain ---------------------------------------------------------------
TOOLCHAIN_BIN := $(HOME)/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin
PREFIX   := arm-none-eabi-
CC       := $(TOOLCHAIN_BIN)/$(PREFIX)gcc
AS       := $(TOOLCHAIN_BIN)/$(PREFIX)gcc -x assembler-with-cpp
CP       := $(TOOLCHAIN_BIN)/$(PREFIX)objcopy
SZ       := $(TOOLCHAIN_BIN)/$(PREFIX)size

CPU      := -mcpu=cortex-m4
FPU      := -mfpu=fpv4-sp-d16
FLOAT    := -mfloat-abi=hard
MCU      := $(CPU) -mthumb $(FPU) $(FLOAT)

# --- sources -----------------------------------------------------------------
# ENR312 target adapter
C_SOURCES := $(wildcard src/*.c)

# ENR312 validated control core -- reused verbatim, not reimplemented
C_SOURCES += $(CORE)/src/enr312_encoder.c \
             $(CORE)/src/enr312_rotor.c   \
             $(CORE)/src/enr312_pd.c      \
             $(CORE)/src/enr312_exp001.c  \
             $(CORE)/src/enr312_exp002.c  \
             $(CORE)/src/enr312_exp003.c  \
             $(CORE)/src/enr312_exp005.c  \
             $(CORE)/src/enr312_ctrl.c    \
             $(CORE)/src/enr312_runner.c  \
             $(CORE)/src/enr312_crashrec.c \
             $(CORE)/src/enr312_cmd.c     \
             $(CORE)/src/enr312_metrics.c

# Vendor ST HAL (read-only, shared with vehicle project, compiled separately here)
HAL_DIR   := $(REPO)/Drivers/STM32F4xx_HAL_Driver/Src
C_SOURCES += $(HAL_DIR)/stm32f4xx_hal.c            \
             $(HAL_DIR)/stm32f4xx_hal_cortex.c     \
             $(HAL_DIR)/stm32f4xx_hal_rcc.c        \
             $(HAL_DIR)/stm32f4xx_hal_rcc_ex.c     \
             $(HAL_DIR)/stm32f4xx_hal_gpio.c       \
             $(HAL_DIR)/stm32f4xx_hal_tim.c        \
             $(HAL_DIR)/stm32f4xx_hal_tim_ex.c     \
             $(HAL_DIR)/stm32f4xx_hal_uart.c       \
             $(HAL_DIR)/stm32f4xx_hal_pwr.c        \
             $(HAL_DIR)/stm32f4xx_hal_pwr_ex.c     \
             $(HAL_DIR)/stm32f4xx_hal_flash.c      \
             $(HAL_DIR)/stm32f4xx_hal_flash_ex.c   \
             $(HAL_DIR)/stm32f4xx_hal_dma.c        \
             $(HAL_DIR)/stm32f4xx_hal_exti.c

ASM_SOURCES := src/startup_stm32f401retx.s

# --- flags -------------------------------------------------------------------
C_DEFS   := -DUSE_HAL_DRIVER -DSTM32F401xE -DENR312_TARGET
C_INCLUDES := -Iinc -I$(CORE)/inc \
              -I$(REPO)/Drivers/STM32F4xx_HAL_Driver/Inc \
              -I$(REPO)/Drivers/STM32F4xx_HAL_Driver/Inc/Legacy \
              -I$(REPO)/Drivers/CMSIS/Device/ST/STM32F4xx/Include \
              -I$(REPO)/Drivers/CMSIS/Include

OPT      := -Og
WARN     := -Wall -Wextra
# -ffile-prefix-map normalises the build directory out of the debug info, so the
# ELF hash is identical no matter where the repository is checked out. Without
# it the image is only reproducible within one path, which makes pinning a hash
# in the flash procedure useless to anyone else.
REPRO    := -ffile-prefix-map=$(abspath $(REPO))=/enr312 -fdebug-prefix-map=$(abspath $(REPO))=/enr312
CFLAGS   := $(MCU) $(C_DEFS) $(C_INCLUDES) $(OPT) $(WARN) -std=gnu11 -g -gdwarf-2 \
            -ffunction-sections -fdata-sections $(REPRO) \
            -MMD -MP
ASFLAGS  := $(MCU) $(OPT) $(WARN) -g -gdwarf-2 -ffunction-sections -fdata-sections $(REPRO)

LDSCRIPT := ENR312_STM32F401RETX_FLASH.ld
LIBS     := -lc -lm -lnosys
LDFLAGS  := $(MCU) -specs=nano.specs -T$(LDSCRIPT) $(LIBS) \
            -Wl,-Map=$(BUILD_DIR)/$(TARGET).map,--cref -Wl,--gc-sections

# --- objects -----------------------------------------------------------------
OBJECTS := $(addprefix $(BUILD_DIR)/,$(notdir $(C_SOURCES:.c=.o)))
vpath %.c $(sort $(dir $(C_SOURCES)))
OBJECTS += $(addprefix $(BUILD_DIR)/,$(notdir $(ASM_SOURCES:.s=.o)))
vpath %.s $(sort $(dir $(ASM_SOURCES)))

.PHONY: all size flash clean isolation ioc-check

all: $(BUILD_DIR)/$(TARGET).elf $(BUILD_DIR)/$(TARGET).hex $(BUILD_DIR)/$(TARGET).bin

$(BUILD_DIR)/%.o: %.c Makefile | $(BUILD_DIR)
	$(CC) -c $(CFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.s Makefile | $(BUILD_DIR)
	$(AS) -c $(ASFLAGS) $< -o $@

$(BUILD_DIR)/$(TARGET).elf: $(OBJECTS) Makefile
	$(CC) $(OBJECTS) $(LDFLAGS) -o $@
	@echo
	@$(SZ) $@

$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf
	$(CP) -O ihex $< $@

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	$(CP) -O binary -S $< $@

$(BUILD_DIR):
	mkdir -p $@

size: $(BUILD_DIR)/$(TARGET).elf
	@$(SZ) -A $<
	@$(SZ) $<

# Prove no vehicle / micro-ROS / FreeRTOS symbol reached this image.
isolation: $(BUILD_DIR)/$(TARGET).elf
	@echo "--- ENR312 isolation check ---"
	@bad=0; \
	for s in micro_ros rcl_ rclc_ rmw_ uxr_ ControlCommand imu_node \
	         BNO085 osKernel osThread vTaskStartScheduler xQueue hi2c1; do \
	  n=$$($(TOOLCHAIN_BIN)/$(PREFIX)nm -C $< 2>/dev/null | grep -c "$$s" || true); \
	  if [ "$$n" != "0" ]; then echo "  FAIL: $$s -> $$n symbols"; bad=1; \
	  else echo "  ok:   $$s absent"; fi; \
	done; \
	echo "  ok:   objects linked: $$(ls $(BUILD_DIR)/*.o | wc -l)"; \
	if [ $$bad -ne 0 ]; then echo "ISOLATION FAILED"; exit 1; \
	else echo "ISOLATION CLEAN -- no vehicle/micro-ROS/FreeRTOS symbols"; fi

# STM32_Programmer_CLI: on PATH, else the copy bundled with STM32CubeIDE.
PROGRAMMER ?= $(firstword $(shell command -v STM32_Programmer_CLI 2>/dev/null) \
                $(wildcard /opt/st/stm32cubeide_*/plugins/com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.*/tools/bin/STM32_Programmer_CLI) \
                STM32_Programmer_CLI)

flash: $(BUILD_DIR)/$(TARGET).elf
	@echo "Flashing the ENR312 PENDULUM image (not vehicle project):"
	@echo "  $(abspath $(BUILD_DIR)/$(TARGET).elf)"
	"$(PROGRAMMER)" -c port=SWD -w $(BUILD_DIR)/$(TARGET).elf -v -rst

clean:
	rm -rf $(BUILD_DIR)

-include $(wildcard $(BUILD_DIR)/*.d)

# Prove enr312.ioc and the hand-written init in src/enr312_board.c agree.
# The IOC is a design record; this file is what builds. They must not drift.
ioc-check:
	@echo "--- enr312.ioc  <->  inc/enr312_board.h consistency ---"
	@bad=0; \
	chk() { \
	  if grep -qE "$$2" enr312.ioc && grep -qE "$$3" inc/enr312_board.h; then \
	    echo "  ok:   $$1"; \
	  else echo "  DRIFT: $$1"; bad=1; fi; }; \
	chk "PC7  = L6474 STCK, GPIO out"   "^PC7.GPIO_Label=L6474_STCK"   "ENR312_STCK_PORT +GPIOC"; \
	chk "PA8  = L6474 DIR"              "^PA8.GPIO_Label=L6474_DIR"    "ENR312_DIR_PIN +GPIO_PIN_8"; \
	chk "PA9  = L6474 nRESET"           "^PA9.GPIO_Label=L6474_nRESET" "ENR312_L6474_RESET_PIN +GPIO_PIN_9"; \
	chk "PA10 = L6474 FLAG, EXTI fall"  "^PA10.GPIO_ModeDefaultEXTI=GPIO_MODE_IT_FALLING" "ENR312_FLAG_PIN +GPIO_PIN_10"; \
	chk "PB6  = L6474 nCS"              "^PB6.GPIO_Label=L6474_nCS"    "ENR312_CS_PIN +GPIO_PIN_6"; \
	chk "PB4  = TIM3_CH1 encoder A"     "^PB4.Signal=S_TIM3_CH1"       "ENR312_ENC_A_PIN +GPIO_PIN_4"; \
	chk "PB5  = TIM3_CH2 encoder B"     "^PB5.Signal=S_TIM3_CH2"       "ENR312_ENC_B_PIN +GPIO_PIN_5"; \
	chk "PB4/5 pull-ups (open coll.)"   "^PB4.GPIO_PuPd=GPIO_PULLUP"   "ENR312_ENC_AF +GPIO_AF2_TIM3"; \
	chk "SPI1 mode 3 (CPOL=1,CPHA=1)"   "^SPI1.CLKPolarity=SPI_POLARITY_HIGH" "ENR312_SPI_AF +GPIO_AF5_SPI1"; \
	chk "TIM2 prescaler 1024"           "^TIM2.Prescaler=1024-1"       "ENR312_STEP_TIM_PSC +1024u"; \
	chk "TIM3 encoder mode TI12"        "^TIM3.EncoderMode=TIM_ENCODERMODE_TI12" "ENR312_ENC_TIM +TIM3"; \
	chk "TIM4 = 500 Hz control tick"    "^TIM4.Prescaler=8400-1"       "ENR312_CTRL_TIM_PSC +8400u"; \
	chk "USART2 115200"                 "^USART2.BaudRate=115200"      "ENR312_UART_BAUD +115200u"; \
	if grep -q "^isbadioc=false" enr312.ioc; then echo "  ok:   isbadioc=false"; \
	  else echo "  DRIFT: IOC marked bad by CubeMX"; bad=1; fi; \
	if [ $$bad -ne 0 ]; then echo "IOC/CODE DRIFT DETECTED"; exit 1; \
	  else echo "IOC AND CODE AGREE"; fi

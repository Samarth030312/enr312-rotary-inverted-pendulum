# ============================================================================
# ENR312 EXP001 core -- host unit tests and target cross-compilation check.
#
#   make test    build and run the host unit tests   (default)
#   make arm     cross-compile the core for STM32F401RE (compile/size check)
#   make clean
#
# This Makefile is INDEPENDENT of the top-level firmware Makefile. The EXP001
# core is a separate application from the vehicle firmware in Core/ -- the two
# cannot share a pin map (see the 2026-08-19 bring-up survey (internal notes, not published), §3), so
# they deliberately do not share a build either.
# ============================================================================

INC      := inc
SRC      := src
TEST     := test
OUT      := build

CORE_SRCS := $(SRC)/enr312_encoder.c $(SRC)/enr312_rotor.c $(SRC)/enr312_exp001.c \
             $(SRC)/enr312_pd.c $(SRC)/enr312_exp002.c $(SRC)/enr312_exp003.c \
             $(SRC)/enr312_metrics.c $(SRC)/enr312_exp005.c $(SRC)/enr312_ctrl.c $(SRC)/enr312_runner.c $(SRC)/enr312_cmd.c $(SRC)/enr312_crashrec.c
TESTS     := test_enr312_encoder test_enr312_rotor test_enr312_exp001 \
             test_enr312_pd test_enr312_exp002 test_enr312_exp003 \
             test_enr312_metrics test_enr312_exp005 test_enr312_ctrl test_enr312_runner test_enr312_cmd test_enr312_crashrec

CC       ?= gcc
CSTD     := -std=c11
WARN     := -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion \
            -Wcast-qual -Wstrict-prototypes -Wmissing-prototypes -Wdouble-promotion
CFLAGS   := $(CSTD) $(WARN) -O2 -g -I$(INC)
LDLIBS   := -lm

# --- Target cross-compilation ------------------------------------------------
ARM_CC   ?= arm-none-eabi-gcc
ARM_MCU  := -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard
ARM_FLAGS := $(ARM_MCU) $(CSTD) $(WARN) -Og -g -ffunction-sections -fdata-sections -I$(INC)

.PHONY: all test arm clean host-rig
all: test

$(OUT):
	@mkdir -p $(OUT)

HOST_SRCS := host/enr312_plant.c

define TEST_RULE
$(OUT)/$(1): $(TEST)/$(1).c $$(CORE_SRCS) $$(HOST_SRCS) $$(wildcard $(INC)/*.h host/*.h $(TEST)/*.h) | $(OUT)
	$$(CC) $$(CFLAGS) -I$(TEST) -Ihost $$(filter %.c,$$^) -o $$@ $$(LDLIBS)
endef
$(foreach t,$(TESTS),$(eval $(call TEST_RULE,$(t))))

test: $(addprefix $(OUT)/,$(TESTS))
	@echo "======================= ENR312 host unit tests ======================="
	@fail=0; for t in $(TESTS); do \
	    ./$(OUT)/$$t || fail=1; \
	done; \
	echo "==============================================================="; \
	if [ $$fail -eq 0 ]; then echo "ALL ENR312 HOST TESTS PASSED"; \
	else echo "ENR312 HOST TESTS FAILED"; exit 1; fi

arm: | $(OUT)
	@echo "Cross-compiling EXP001 core for STM32F401RE ..."
	@for f in $(CORE_SRCS); do \
	    $(ARM_CC) $(ARM_FLAGS) -c $$f -o $(OUT)/arm_$$(basename $$f .c).o || exit 1; \
	done
	@arm-none-eabi-size -t $(OUT)/arm_*.o
	@echo "EXP001 core cross-compiles clean for the target."

# The rig EMULATOR: the real control code (runner, cores, command parser)
# against the nonlinear plant, behind the firmware's console protocol.
host-rig: $(OUT)/enr312_host_rig
$(OUT)/enr312_host_rig: host/enr312_host_rig.c host/enr312_plant.c $(CORE_SRCS) $(wildcard inc/*.h host/*.h) | $(OUT)
	$(CC) -std=gnu11 -Wall -Wextra -O2 -g -Iinc -Ihost $(filter %.c,$^) -o $@ -lm

clean:
	rm -rf $(OUT)

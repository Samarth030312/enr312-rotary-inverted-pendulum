# ENR312 — CubeMX / STM32CubeIDE path

`target/enr312.ioc` is the pendulum's pin and peripheral configuration. Until
2026-10-09 nobody had run CubeMX on it. Now someone has.

## What has been verified (2026-10-09, on the development machine)

| Check | Result |
|---|---|
| CubeMX 6.13.0 (the copy bundled in STM32CubeIDE 1.17.0) loads `enr312.ioc` headless | **OK**, no errors |
| Generates init code (`generated/`) | **OK**: SPI1, TIM2, TIM3 (encoder), TIM4 (500 Hz), USART2, GPIO |
| Generated values equal the IOC | PLL 8/84/2 = 84 MHz, SPI mode 3 ÷32, TIM3 TI12, TIM4 8400×20 = 500 Hz, UART 460800 (at the time) |
| Generated code compiles and links (GCC 13.2.1, with CubeMX's own HAL copy) | **OK**, 0 errors; the only warnings are newlib's `_close/_lseek/_read/_write` stub notices |
| The hand-written target agrees with the same IOC | `make -C ../target ioc-check` → 14/14 |

Not verified: the generated code has never run on a board.

**2026-10-12:** the UART was changed to 115200 in `enr312.ioc` (the
kit manual UM2717 uses 115200). Headless regeneration with `generate.sh`
did not finish on the development machine (CubeMX hung, killed after 10 min), so
the single line `huart2.Init.BaudRate` in `generated/Src/main.c` was updated by
hand to match the IOC. Regenerate from the GUI if you need a clean copy.

## Two firmwares, one IOC. Which one do you flash?

* **`../target/` (Makefile, hand-written init)**: the lab firmware. It has the
  safety state machine, L6474 driver, step generator, telemetry and the `r`
  stream for MATLAB. **Flash this one.** See `docs/experiments/EXP001/FIRST_FLASH.md`.
* **`generated/` (CubeMX)**: proof that the IOC is valid, and the starting
  point for students who build their own firmware in STM32CubeIDE. It
  configures the peripherals and does nothing else.

## Making a CubeIDE project for students (GUI, about 1 minute)

The CubeMX copy inside CubeIDE does not emit CubeIDE project files from the
command line: it always falls back to IAR/EWARM, which we observed in three
attempts. CubeIDE creates the project itself:

1. STM32CubeIDE → *File → New → STM32 Project from an Existing STM32CubeMX
   Configuration File (.ioc)*.
2. Pick a **copy** of `firmware/enr312/target/enr312.ioc`, for example in a fresh
   workspace such as `~/STM32CubeIDE/enr312_ws/`. Do **not** pick the vehicle's
   `odyssix_stm32_core.ioc`.
3. Generate, then *Project → Build*. The result should match `generated/` here.
4. Put student code only inside `/* USER CODE BEGIN */ … END` blocks; CubeMX
   preserves those on regeneration.

## Regenerate / re-verify from the command line

```bash
firmware/enr312/cubemx/generate.sh
```

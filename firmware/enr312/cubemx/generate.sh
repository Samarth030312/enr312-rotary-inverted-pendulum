#!/usr/bin/env bash
# Regenerate the CubeMX init code for the ENR312 pendulum from target/enr312.ioc,
# headless, with the CubeMX bundled inside STM32CubeIDE, then prove it compiles.
#
#   firmware/enr312/cubemx/generate.sh            # regenerate + compile check
#
# Writes ONLY firmware/enr312/cubemx/generated/{Src,Inc}. Never touches the
# vehicle IOC, Core/, or the hand-written target. Works in a temp directory.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
IOC="$REPO/firmware/enr312/target/enr312.ioc"
IDE="${CUBEIDE:-/opt/st/stm32cubeide_1.17.0}"
MXJAR="$(ls "$IDE"/plugins/com.st.stm32cube.common.mx_*/STM32CubeMX.jar | head -1)"
JAVA="$(ls "$IDE"/plugins/com.st.stm32cube.ide.jre.*/jre/bin/java | head -1)"
GCC="${ARM_GCC:-$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin}/arm-none-eabi-gcc"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$IOC" "$TMP/enr312_cubeide.ioc"
cat > "$TMP/script.txt" <<EOS
config load $TMP/enr312_cubeide.ioc
project name enr312_cubeide
project path $TMP/out
project generate
exit
EOS
echo "CubeMX: $MXJAR"
(cd "$TMP" && "$JAVA" -jar "$MXJAR" -q "$TMP/script.txt" > "$TMP/mx.log" 2>&1)
OUT="$TMP/out/enr312_cubeide"
grep -q "^OK" "$TMP/mx.log" || { tail -30 "$TMP/mx.log"; echo "CubeMX generation FAILED"; exit 1; }

rm -rf "$HERE/generated"; mkdir -p "$HERE/generated/Src" "$HERE/generated/Inc"
cp "$OUT"/Src/*.c "$HERE/generated/Src/"; cp "$OUT"/Inc/*.h "$HERE/generated/Inc/"

# Compile check: generated init + the HAL CubeMX copied + the target's GCC startup/linker.
B="$TMP/build"; mkdir -p "$B"
F="-mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard"
INC="-I$OUT/Inc -I$OUT/Drivers/STM32F4xx_HAL_Driver/Inc -I$OUT/Drivers/CMSIS/Device/ST/STM32F4xx/Include -I$OUT/Drivers/CMSIS/Include"
for f in "$OUT"/Src/*.c $(ls "$OUT"/Drivers/STM32F4xx_HAL_Driver/Src/*.c | grep -v template); do
    "$GCC" -c $F -DUSE_HAL_DRIVER -DSTM32F401xE $INC -Os -Wall -ffunction-sections -fdata-sections \
           "$f" -o "$B/$(basename "$f" .c).o"
done
"$GCC" -c $F "$REPO/firmware/enr312/target/src/startup_stm32f401retx.s" -o "$B/startup.o"
"$GCC" $F "$B"/*.o -specs=nano.specs -specs=nosys.specs \
       -T"$REPO/firmware/enr312/target/ENR312_STM32F401RETX_FLASH.ld" -Wl,--gc-sections -o "$B/enr312_cubemx.elf"
"${GCC%gcc}size" "$B/enr312_cubemx.elf"
echo "CUBEMX GENERATION AND COMPILE: OK"

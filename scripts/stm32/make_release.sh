#!/usr/bin/env bash
# Publish the ENR312 pendulum firmware as a committed, hash-pinned release so
# MATLAB (odyssix.stm32.flash) can program a board WITHOUT the ARM toolchain.
#
#   scripts/stm32/make_release.sh
#
# Refuses a dirty tree: a release must name the exact commit it was built from.
set -euo pipefail
root="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
tgt="$root/firmware/enr312/target"; rel="$root/firmware/enr312/release"
export PATH="${ARM_GCC_BIN:-$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin}:$PATH"

if [ -n "$(git -C "$root" status --porcelain -- firmware/enr312 ':!firmware/enr312/release')" ]; then
  echo "firmware/enr312 has uncommitted changes; commit first so the release names its source."; exit 1
fi
make -C "$tgt" clean >/dev/null
make -C "$tgt" >/dev/null
make -C "$tgt" isolation | grep ISOLATION
make -C "$tgt" ioc-check | grep -E "AGREE|DRIFT"
grep -aq "THIS IS NOT THE VEHICLE FIRMWARE" "$tgt/build/enr312_pendulum.elf" \
  || { echo "banner missing: not the pendulum image"; exit 1; }

mkdir -p "$rel"
cp "$tgt/build/enr312_pendulum.elf" "$tgt/build/enr312_pendulum.bin" "$tgt/build/enr312_pendulum.hex" "$rel/"
rev="$(git -C "$root" rev-parse --short HEAD)"
{
  echo "target:      ENR312 rotary inverted pendulum (STM32F401RE, NUCLEO-F401RE + X-NUCLEO-IHM01A1)"
  echo "NOT:         the vehicle firmware -- never flash build/odyssix_stm32_core.elf onto the rig"
  echo "source_rev:  $rev"
  echo "built:       $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "compiler:    $(arm-none-eabi-gcc --version | head -1)"
  echo "build_cmd:   make -C firmware/enr312/target   (byte-reproducible)"
  echo "flash_addr:  0x08000000"
  echo "uart:        ST-LINK VCP, 115200 8N1"
  echo "size:        $(arm-none-eabi-size "$rel/enr312_pendulum.elf" | tail -1 | awk '{print "text "$1" data "$2" bss "$3}')"
  echo "sha256:"
  (cd "$rel" && sha256sum enr312_pendulum.elf enr312_pendulum.bin enr312_pendulum.hex | sed 's/^/  /')
} > "$rel/MANIFEST.txt"
cat "$rel/MANIFEST.txt"

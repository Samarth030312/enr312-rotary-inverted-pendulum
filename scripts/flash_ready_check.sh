#!/usr/bin/env bash
# ENR312 flash-readiness check: everything that can be verified WITHOUT the rig.
#
#   scripts/flash_ready_check.sh           # full (about 6 minutes, includes MATLAB e2e)
#   scripts/flash_ready_check.sh --quick   # skip the real-time MATLAB e2e tests
#
# Prints PASS/FAIL per gate and a final verdict. Nothing here touches hardware.
set -uo pipefail
root="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; cd "$root"
export PATH="${ARM_GCC_BIN:-$HOME/.local/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi/bin}:$PATH"
MATLAB="${MATLAB:-$(command -v matlab || echo "$HOME/MATLAB/R2026a/bin/matlab")}"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
pass=0; fail=0; log="$(mktemp)"
gate() {  # gate "name" command...
  local name="$1"; shift
  if "$@" >>"$log" 2>&1; then printf '  PASS  %s\n' "$name"; pass=$((pass+1));
  else printf '  FAIL  %s   (see %s)\n' "$name" "$log"; fail=$((fail+1)); fi
}
tgt=firmware/enr312/target; rel=firmware/enr312/release
echo "ENR312 flash-readiness check  ($(git rev-parse --short HEAD 2>/dev/null || echo no-git)$( [ -n "$(git status --porcelain -- firmware matlab scripts)" ] && echo ', DIRTY'))"
echo "--- firmware ---------------------------------------------------------"
gate "target builds, no project warnings" bash -c "make -C $tgt clean >/dev/null && make -C $tgt 2>&1 | grep -E 'warning|error' | grep -v 'stm32f4xx_hal\|not implemented\|Banks' | (! grep .)"
gate "isolation: no vehicle/micro-ROS/FreeRTOS symbols" bash -c "make -C $tgt isolation | grep -q 'ISOLATION CLEAN'"
gate "enr312.ioc agrees with the hand-written init" bash -c "make -C $tgt ioc-check | grep -q 'IOC AND CODE AGREE'"
gate "build is byte-reproducible" bash -c "a=\$(sha256sum $tgt/build/enr312_pendulum.elf | cut -d' ' -f1); make -C $tgt clean >/dev/null; make -C $tgt >/dev/null 2>&1; [ \"\$a\" = \"\$(sha256sum $tgt/build/enr312_pendulum.elf | cut -d' ' -f1)\" ]"
gate "release image = this source (MANIFEST hash)" bash -c "grep -q \"\$(sha256sum $tgt/build/enr312_pendulum.elf | cut -d' ' -f1)  enr312_pendulum.elf\" $rel/MANIFEST.txt && (cd $rel && sha256sum -c <(grep -E '^  [0-9a-f]{64}' MANIFEST.txt | sed 's/^  //') >/dev/null)"
gate "release carries the ENR312 banner (not vehicle firmware)" grep -aq "THIS IS NOT THE VEHICLE FIRMWARE" $rel/enr312_pendulum.elf
gate "release fits: flash < 512 KB, RAM < 96 KB" bash -c "arm-none-eabi-size $rel/enr312_pendulum.elf | awk 'NR==2{exit !((\$1+\$2)<524288 && (\$2+\$3)<98304)}'"
gate "host unit tests (cores, runner, parser)" bash -c "make -C firmware/enr312 test 2>&1 | grep -q 'ALL ENR312 HOST TESTS PASSED'"
gate "rig emulator builds (firmware code on the PC)" make -C firmware/enr312 host-rig
if [ -d Core ]; then   # only where the co-resident vehicle firmware exists
  gate "vehicle firmware untouched since baseline" git diff --quiet 44bda39 HEAD -- Core odyssix_stm32_core.ioc Middlewares micro_ros_stm32cubemx_utils
fi
echo "--- programmer --------------------------------------------------------"
gate "STM32_Programmer_CLI found (CubeIDE / CubeProgrammer)" bash -c "make -s -C $tgt -n flash | grep -q STM32_Programmer_CLI && test -x \"\$(make -s -C $tgt -n flash | grep -o '\"[^\"]*STM32_Programmer_CLI\"' | tr -d '\"')\""
echo "--- MATLAB (${MATLAB}) ---------------------------------------------------"
m() { "$MATLAB" -batch "addpath(genpath('matlab')); $1" ; }   # statements; any error = FAIL
gate "physics model validation (14 checks)" m "assert(rotary_pendulum_validate_physics())"
gate "MATLAB simulation == firmware code (12 checks)" m "assert(test_sim_matches_firmware())"
gate "Tutorial 3/4/5 model validators (error on any failure)" m "exp003_validate_mimo_model(); exp004_validate_sensitivity(); exp005_validate_inverted();"
if [ $quick -eq 0 ]; then
  gate "rig app end to end on the emulator" m "assert(e2e_rig_app_emulator())"
  gate "five-tutorial lab end to end, sim + emulator" m "assert(e2e_lab_all_tutorials())"
fi
echo "----------------------------------------------------------------------"
echo "  $pass passed, $fail failed"
if [ $fail -eq 0 ]; then
  echo "  SOFTWARE FLASH READY: YES   (software only; the rig itself: docs/hardware/ENR312_WIRING.md section 4)"
else
  echo "  SOFTWARE FLASH READY: NO"; exit 1
fi

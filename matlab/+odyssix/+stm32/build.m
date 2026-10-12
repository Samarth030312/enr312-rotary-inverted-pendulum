function R = build()
%BUILD  Rebuild the ENR312 firmware from source (needs ARM GCC and make).
%
%   R = odyssix.stm32.build()   ->  R.ok, R.log, R.elf, R.sha256
%   Students do not need this: odyssix.stm32.flash() uses the committed
%   release image. Use it after changing firmware/enr312.
    T = odyssix.stm32.tools();
    R = struct('ok', false, 'log', '', 'elf', T.buildElf, 'sha256', '');
    if isempty(T.make) || isempty(T.armGccBin)
        R.log = 'Rebuilding needs make and the ARM GCC toolchain (arm-none-eabi-gcc).'; return;
    end
    old = getenv('PATH'); c = onCleanup(@() setenv('PATH', old));
    setenv('PATH', [T.armGccBin pathsep old]);
    [st, out] = system(sprintf('"%s" -C "%s" 2>&1 && "%s" -C "%s" isolation 2>&1', ...
                               T.make, T.target, T.make, T.target));
    R.log = out;
    R.ok = st == 0 && contains(out, 'ISOLATION CLEAN') && isfile(T.buildElf);
    if R.ok, R.sha256 = odyssix.stm32.sha256(T.buildElf); end
end

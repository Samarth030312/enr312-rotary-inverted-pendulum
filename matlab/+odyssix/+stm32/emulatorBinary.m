function exe = emulatorBinary()
%EMULATORBINARY  Path to the rig emulator (built from firmware/enr312 on demand).
%
%   exe = odyssix.stm32.emulatorBinary()
%   The emulator is the firmware's own control code (runner, tutorial cores,
%   PD, command parser) compiled for the PC against a nonlinear plant model:
%   firmware/enr312/host/enr312_host_rig.c. Needs gcc and make (Linux/macOS).
    T = odyssix.stm32.tools();
    d = fullfile(T.repo, 'firmware', 'enr312');
    exe = fullfile(d, 'build', 'enr312_host_rig');
    srcs = [dir(fullfile(d, 'src', '*.c')); dir(fullfile(d, 'host', '*.c')); dir(fullfile(d, 'inc', '*.h'))];
    stale = ~isfile(exe) || any([srcs.datenum] > dir(exe).datenum);
    if stale
        [st, out] = system(sprintf('make -C "%s" host-rig 2>&1', d));
        if st ~= 0 || ~isfile(exe)
            error('odyssix:emulator', 'Building the emulator failed (needs gcc + make):\n%s', out);
        end
    end
end

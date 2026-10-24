function T = tools()
%TOOLS  Locate everything needed to build, flash and talk to the ENR312 board.
%
%   T = odyssix.stm32.tools()
%
%   Fields (empty when not found):
%     programmer   STM32_Programmer_CLI: env ODYSSIX_STM32_PROGRAMMER, PATH,
%                  then the copy bundled with STM32CubeIDE, then a standalone
%                  STM32CubeProgrammer install. Linux, Windows and macOS paths.
%     stflash      st-flash (open-source stlink tools), fallback only
%     armGccBin    ARM GCC bin directory (only needed to rebuild from source)
%     make         make executable (only needed to rebuild from source)
%     repo, target, release   firmware paths
%     releaseElf   the committed, hash-pinned pendulum image
%     baud         115200 (ST-LINK virtual COM port, the rate UM2717 uses)

    T.repo    = odyssix.repoRoot();
    T.target  = fullfile(T.repo, 'firmware', 'enr312', 'target');
    T.release = fullfile(T.repo, 'firmware', 'enr312', 'release');
    T.releaseElf = fullfile(T.release, 'enr312_pendulum.elf');
    T.buildElf   = fullfile(T.target, 'build', 'enr312_pendulum.elf');
    T.baud = 115200;
    T.logDir = fullfile(T.repo, 'results', 'evidence', 'logs');

    exe = ''; if ispc, exe = '.exe'; end
    T.programmer = firstExisting([ ...
        {getenv('ODYSSIX_STM32_PROGRAMMER')}, onPath(['STM32_Programmer_CLI' exe]), ...
        globAll('/opt/st/stm32cubeide_*/plugins/com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.*/tools/bin/STM32_Programmer_CLI'), ...
        globAll('/opt/st/stm32cubeprogrammer*/bin/STM32_Programmer_CLI'), ...
        globAll(fullfile(getenv('HOME'), 'STMicroelectronics', 'STM32Cube', 'STM32CubeProgrammer', 'bin', 'STM32_Programmer_CLI')), ...
        globAll('C:\ST\STM32CubeIDE_*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.*\tools\bin\STM32_Programmer_CLI.exe'), ...
        globAll('C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe'), ...
        globAll('/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/MacOs/bin/STM32_Programmer_CLI'), ...
        globAll('/Applications/STM32CubeIDE.app/Contents/Eclipse/plugins/com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.*/tools/bin/STM32_Programmer_CLI')]);
    T.stflash = firstExisting(onPath(['st-flash' exe]));
    % the toolchain's bin folder (dir() on a pattern ending in a folder name lists
    % that folder's files, so the folders are globbed first and bin appended)
    home = getenv('HOME'); if isempty(home), home = getenv('USERPROFILE'); end
    tc = [globAll(fullfile(home, '.local', 'arm-gnu-toolchain-*')), ...
          globAll('C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\*'), ...
          globAll('C:\Program Files\Arm GNU Toolchain arm-none-eabi\*'), ...
          globAll('/Applications/ArmGNUToolchain/*/arm-none-eabi')];
    T.armGccBin = firstExisting([{getenv('ARM_GCC_BIN')}, cellfun(@(d) fullfile(d, 'bin'), tc, 'UniformOutput', false)]);
    if isempty(T.armGccBin)
        g = onPath(['arm-none-eabi-gcc' exe]);
        if ~isempty(g), T.armGccBin = fileparts(g{1}); end
    end
    T.make = firstExisting(onPath(['make' exe]));
end

function c = onPath(name)
    if ispc, [st, out] = system(['where ' name]); else, [st, out] = system(['command -v ' name]); end
    if st == 0, c = strtrim(splitlines(strtrim(out)))'; c = c(1); else, c = {}; end
end

function c = globAll(pattern)
    d = dir(pattern);
    c = arrayfun(@(e) fullfile(e.folder, e.name), d, 'UniformOutput', false)';
    c = flip(sort(c));                 % newest version first
end

function p = firstExisting(c)
    p = '';
    for i = 1:numel(c)
        if ~isempty(c{i}) && (isfile(c{i}) || isfolder(c{i}))
            p = c{i}; return;
        end
    end
end

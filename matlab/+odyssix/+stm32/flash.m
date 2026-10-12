function R = flash(opts)
%FLASH  Program the ENR312 pendulum firmware onto the Nucleo from MATLAB.
%
%   R = odyssix.stm32.flash()                     % committed release image
%   R = odyssix.stm32.flash('Image', 'build')     % your local build
%   R = odyssix.stm32.flash('Image', '/path/x.elf')
%   R = odyssix.stm32.flash('GatesOnly', true)    % gates 1-2 only; never touches
%                                                 % the board (used by tests)
%
%   Safety gates, in order; any failure stops before the board is written:
%     1. the image contains the ENR312 banner "THIS IS NOT THE VEHICLE
%        FIRMWARE". The vehicle image (which drives PA9, the L6474 reset
%        line, as a UART) is refused.
%     2. a release image must match the SHA-256 in release/MANIFEST.txt
%     3. the connected MCU must report device ID 0x433 (STM32F401xD/E)
%   Then: write, verify, reset. The firmware boots into SAFE (driver held in
%   reset); flashing cannot make the motor move.
%
%   R.ok, R.message, R.image, R.sha256, R.deviceId, R.log, R.logFile

    arguments
        opts.Image (1,:) char = 'release'
        opts.GatesOnly (1,1) logical = false
    end
    T = odyssix.stm32.tools();
    R = struct('ok', false, 'message', '', 'image', '', 'sha256', '', ...
               'deviceId', '', 'log', '', 'logFile', '');
    log = {};

    switch opts.Image
        case 'release', R.image = T.releaseElf;
        case 'build',   R.image = T.buildElf;
        otherwise,      R.image = opts.Image;
    end
    if ~isfile(R.image), R = fail(R, log, T, ['image not found: ' R.image]); return; end

    % gate 1: the pendulum banner
    fid = fopen(R.image, 'r'); bytes = fread(fid, Inf, '*char')'; fclose(fid);
    if ~contains(bytes, 'THIS IS NOT THE VEHICLE FIRMWARE')
        R = fail(R, log, T, 'REFUSED: image lacks the ENR312 banner (vehicle firmware or unknown image).');
        return;
    end
    R.sha256 = odyssix.stm32.sha256(R.image);
    log{end+1} = sprintf('image  %s\nsha256 %s', R.image, R.sha256);

    % gate 2: release hash
    if strcmp(opts.Image, 'release')
        man = fileread(fullfile(T.release, 'MANIFEST.txt'));
        tok = regexp(man, '(\w{64})\s+enr312_pendulum\.elf', 'tokens', 'once');
        if isempty(tok) || ~strcmpi(tok{1}, R.sha256)
            R = fail(R, log, T, 'REFUSED: release ELF does not match MANIFEST.txt.'); return;
        end
        log{end+1} = 'release hash matches MANIFEST.txt';
    end
    if opts.GatesOnly
        R.ok = true; R.message = 'Image gates passed (GatesOnly: no SWD access, board untouched).';
        R = finish(R, log, T); return;
    end

    if ~isempty(T.programmer)
        % gate 3: identify the target
        [st, out] = system(sprintf('"%s" -c port=SWD mode=UR', T.programmer));
        log{end+1} = out;
        id = regexp(out, 'Device ID\s*:\s*(0x[0-9A-Fa-f]+)', 'tokens', 'once');
        if st ~= 0 || isempty(id)
            R = fail(R, log, T, 'No target answered over SWD. Is the Nucleo plugged in (USB), and CN2 jumpers fitted?');
            return;
        end
        R.deviceId = lower(id{1});
        if ~strcmp(R.deviceId, '0x433')
            R = fail(R, log, T, sprintf('REFUSED: device ID %s is not an STM32F401RE (0x433).', R.deviceId));
            return;
        end
        [st, out] = system(sprintf('"%s" -c port=SWD mode=UR -w "%s" -v -rst', T.programmer, R.image));
        log{end+1} = out;
        verified = contains(out, 'verified successfully', 'IgnoreCase', true) || ...
                   contains(out, 'Verification OK', 'IgnoreCase', true);
        if st ~= 0 || ~verified
            R = fail(R, log, T, 'Programming or verification failed; see the log.'); return;
        end
    elseif ~isempty(T.stflash)
        bin = regexprep(R.image, '\.elf$', '.bin');
        if ~isfile(bin), R = fail(R, log, T, 'st-flash needs the .bin next to the .elf.'); return; end
        [st, out] = system(sprintf('"%s" --reset write "%s" 0x08000000', T.stflash, bin));
        log{end+1} = out;
        R.deviceId = 'unchecked (st-flash)';
        if st ~= 0, R = fail(R, log, T, 'st-flash failed; see the log.'); return; end
    else
        R = fail(R, log, T, 'No programmer: install STM32CubeIDE or STM32CubeProgrammer.'); return;
    end
    R.ok = true;
    R.message = sprintf('Flashed and verified (%s). The board has reset into SAFE.', R.deviceId);
    R = finish(R, log, T);
end

function R = fail(R, log, T, msg)
    R.ok = false; R.message = msg; R = finish(R, log, T);
end

function R = finish(R, log, T)
    log{end+1} = ['RESULT: ' R.message];
    R.log = strjoin(log, newline);
    if ~isfolder(T.logDir), mkdir(T.logDir); end
    R.logFile = fullfile(T.logDir, ['flash_' char(datetime('now', 'Format', 'yyyyMMdd-HHmmss')) '.log']);
    fid = fopen(R.logFile, 'w'); fprintf(fid, '%s\n', R.log); fclose(fid);
end

function B = listBoards()
%LISTBOARDS  ST-LINK probes and their virtual COM ports, without touching the target.
%
%   B = odyssix.stm32.listBoards()
%     B.probes  struct array: serial, description   (from STM32_Programmer_CLI -l st,
%               or st-info --probe as a fallback)
%     B.ports   cellstr of serial ports that belong to an ST-LINK, best first.
%               On Linux these come from /dev/serial/by-id; elsewhere every port
%               from serialportlist is returned (an ST-LINK VCP cannot be told
%               apart there without the USB IDs).
%     B.text    one-line human summary
%     B.usbStuck true if an ST-LINK is on USB but unconfigured (replug needed)
%   Reading the probe list does not reset or halt the MCU.

    T = odyssix.stm32.tools();
    B.probes = struct('serial', {}, 'description', {});
    if ~isempty(T.programmer)
        [~, out] = system(sprintf('"%s" -l st', T.programmer));
        sn = regexp(out, 'ST-?LINK SN\s*:\s*(\w+)', 'tokens', 'ignorecase');
        for i = 1:numel(sn)
            B.probes(end+1) = struct('serial', sn{i}{1}, 'description', 'ST-LINK'); %#ok<AGROW>
        end
    elseif ~isempty(T.stflash)
        [~, out] = system('st-info --probe');
        sn = regexp(out, 'serial:\s*(\w+)', 'tokens');
        for i = 1:numel(sn)
            B.probes(end+1) = struct('serial', sn{i}{1}, 'description', 'ST-LINK (st-info)'); %#ok<AGROW>
        end
    end

    B.ports = {};
    if isunix && isfolder('/dev/serial/by-id')
        d = dir('/dev/serial/by-id');
        for i = 1:numel(d)
            if ~isempty(regexpi(d(i).name, 'STMicroelectronics|STLINK|ST-LINK', 'once'))
                [st, tgt] = system(sprintf('readlink -f "%s"', fullfile(d(i).folder, d(i).name)));
                if st == 0, B.ports{end+1} = strtrim(tgt); end
            end
        end
    end
    if isempty(B.ports)
        try, B.ports = cellstr(serialportlist("available")); catch, B.ports = {}; end
        if isunix, B.ports = B.ports(~startsWith(B.ports, '/dev/ttyS')); end   % legacy UARTs
    end

    % Linux: an ST-LINK that enumerated but never got a USB configuration (seen
    % 2026-10-12, kernel "error -71") has neither SWD nor a serial port, and
    % only a physical replug cures it. Say so instead of "no board".
    B.usbStuck = false;
    if isunix && isfolder('/sys/bus/usb/devices')
        d = dir('/sys/bus/usb/devices/*');
        for i = 1:numel(d)
            f = fullfile(d(i).folder, d(i).name);
            if isfile(fullfile(f, 'idVendor')) && strcmp(strtrim(fileread(fullfile(f, 'idVendor'))), '0483') ...
                    && isfile(fullfile(f, 'bConfigurationValue')) && isempty(strtrim(fileread(fullfile(f, 'bConfigurationValue'))))
                B.usbStuck = true;
            end
        end
    end

    if B.usbStuck && isempty(B.probes)
        B.text = 'ST-LINK is on USB but not configured (no SWD, no serial port). Unplug the Nucleo USB, wait 5 s, plug it back in.';
    elseif isempty(T.programmer) && isempty(T.stflash)
        B.text = 'No STM32 programmer found: install STM32CubeIDE or STM32CubeProgrammer.';
    elseif isempty(B.probes)
        B.text = 'No ST-LINK detected. Plug the Nucleo in by USB.';
    else
        B.text = sprintf('ST-LINK %s found', strjoin({B.probes.serial}, ', '));
        if ~isempty(B.ports), B.text = [B.text ' on ' strjoin(B.ports, ', ')]; end
    end
end

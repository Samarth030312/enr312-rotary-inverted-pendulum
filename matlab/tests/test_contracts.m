function ok = test_contracts()
%TEST_CONTRACTS  shared/experiment_contracts/EXP006-024.yaml = odyssix.sim.defaults = firmware.
%   Three-way check: the contract against the MATLAB defaults, and the MATLAB
%   defaults against the firmware's own '$cfg' echo (the C code in the rig
%   emulator), so a parameter cannot silently differ anywhere.
    txt = fileread(fullfile(odyssix.repoRoot(), 'shared', 'experiment_contracts', 'EXP006-024.yaml'));
    L = splitlines(txt); e = NaN; inDef = false; n = 0; bad = {};
    for i = 1:numel(L)
        s = L{i};
        tok = regexp(s, '^EXP(\d+):', 'tokens', 'once');
        if ~isempty(tok), e = str2double(tok{1}); c = odyssix.sim.defaults(e); inDef = false; continue; end
        if strcmp(strtrim(s), 'defaults:'), inDef = true; continue; end
        tok = regexp(s, '^    (\w+):\s*(\S+)', 'tokens', 'once');
        if inDef && ~isempty(tok)
            v = str2double(tok{2}); n = n + 1;
            if ~isfield(c, tok{1}) || abs(c.(tok{1}) - v) > 1e-9 * max(1, abs(v))
                bad{end+1} = sprintf('EXP%03d %s: contract %g, defaults %g', e, tok{1}, v, getf(c, tok{1})); %#ok<AGROW>
            end
        end
    end
    nC = n;
    % ---- and the firmware itself: its '$cfg' echo after '$exp=N' (the C defaults)
    exe = odyssix.stm32.emulatorBinary();
    f = [tempname '.pty'];
    system(sprintf('"%s" --pty --parent %d > "%s" 2>&1 & echo $! > "%s.pid"', exe, feature('getpid'), f, f));
    for i = 1:50, if isfile(f) && ~isempty(strtrim(fileread(f))), break; end, pause(0.1); end
    pid = strtrim(fileread([f '.pid'])); c0 = onCleanup(@() system(['kill ' pid ' 2>/dev/null']));
    sp = serialport(strtrim(fileread(f)), 115200, 'Timeout', 0.5); configureTerminator(sp, 'CR/LF');
    keys = [odyssix.stm32.RigLink.KEYS2, odyssix.stm32.RigLink.KEYS3, odyssix.stm32.RigLink.KEYS4, odyssix.stm32.RigLink.KEYS5];
    nF = 0;
    for e = [6 7 8 9 10 21 22 23 24]
        flush(sp); write(sp, uint8(sprintf('$exp=%d\n$cfg\n', e)), 'uint8');
        t0 = tic; line = '';
        while toc(t0) < 2 && ~startsWith(line, sprintf('C,%d,', e))
            try, line = char(readline(sp)); catch, line = ''; end
            if isempty(line), line = ''; end
        end
        v = str2double(split(string(line(find(line == ',', 1) + 1:end)), ','));
        c = odyssix.sim.defaults(e);
        if numel(v) ~= 26, bad{end+1} = sprintf('EXP%03d: no protocol-5 C line from the firmware', e); continue; end %#ok<AGROW>
        for i = 1:numel(keys)
            nF = nF + 1;
            if abs(v(i + 1) - c.(keys{i})) > 1e-3     % the C line prints 3 decimals
                bad{end+1} = sprintf('EXP%03d %s: firmware %g, defaults %g', e, keys{i}, v(i + 1), c.(keys{i})); %#ok<AGROW>
            end
        end
    end
    clear sp
    ok = isempty(bad) && nC == 9 * 25 && nF == 9 * 25;
    fprintf('contracts: %d contract values and %d firmware values checked, %d mismatches\n', nC, nF, numel(bad));
    fprintf('  %s\n', bad{:});
end
function v = getf(c, f), if isfield(c, f), v = c.(f); else, v = NaN; end, end

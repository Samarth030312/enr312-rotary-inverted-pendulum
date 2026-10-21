classdef RigLink < handle
%RIGLINK  Serial link to the ENR312 pendulum firmware (ST-LINK virtual COM port).
%
%   L = odyssix.stm32.RigLink();  L.open('/dev/ttyACM0');
%   L.stream(true);  ...  L.poll();  T = L.table();  L.abort();  L.close();
%
%   The firmware protocol is single-byte commands and text lines
%   (firmware/enr312/target/src/enr312_main.c):
%     ? help   t status   a ARM   s START   x ABORT   c clear fault
%     z zero datums   + / -  first-motion +/-5 deg   q L6474 status   r stream on/off
%   '$' lines (protocol 2/3): exp= kp= ... cfg go stop ref=; see configure,
%   setLive, setRef.
%   Stream lines:  D,<ticks>,<rotor mdeg>,<pendulum mdeg>,<encoder raw>,<faults>,<state>
%   at 50 Hz; ticks are the firmware's 500 Hz control ticks, so time stamps
%   come from the MCU, not from the PC.
%
%   SAFETY: close() sends ABORT ('x') first, so the motor is de-energised
%   whenever MATLAB lets go of the port. Every received byte is kept in a raw
%   log file (results/evidence/logs) for provenance.

    properties (SetAccess = private)
        port = ''; baud = 115200
        n = 0                       % samples received since clearData
        state = 'UNKNOWN'; faults = 0; streaming = false
        lines = {}                  % recent non-data lines from the firmware
        invalidCount = 0
        logFile = ''
        banner = false              % saw the ENR312 boot banner
        protocol = 1                % 2 = closed-loop firmware ('$' commands), 3 = + Tutorials 6-10/PEND, 4 = + lab mode, swing-up
        emulator = false            % banner said EMULATOR
        cfg = struct()              % last '$cfg' report
        lastError = ''              % last 'ERR ...' line
        runEvent = ''               % last 'GO' / 'RUN ...' line
        lastRef = NaN               % last live set-point acknowledged ('REF x') [deg]
        firmware = ''               % the board's 'Firmware:' line (version and protocol)
        crashPending = 0            % complete 500 Hz crash records not yet taken (takeCrashes)
    end
    properties (Access = private)
        sp = []; partial = ''; fid = -1
        busy = false                % a serial call is in progress (re-entrancy guard)
        T0 = []; tk; rot; pen; raw; flt; st; rexp; rph; ru; rref
        crashHdr = []; crashBuf = zeros(0, 5); crashDone = {}    % firmware 2.3.3 crash recorder
    end
    properties (Constant)
        TICK_S = 0.002
        % protocol 2 keys (Tutorials 2-5), then the protocol 3 additions (exp >= 6)
        KEYS2 = {'kp', 'kd', 'kpp', 'kdp', 'step', 'dist', 'ulim', 'vmax'}
        KEYS3 = {'ki', 'fdr', 'fdp', 'k1', 'k2', 'k3', 'k4', 'bv', 'imp', 'uon', 'db', 'rrate', 'div', 'ma'}
        KEYS4 = {'seq', 'wg2'}      % protocol 4: lab mode, pendulum constant (swing-up)
        KEYS5 = {'amp'}             % protocol 5: pendulum target (exp 24)
        KEYS = struct('help', '?', 'status', 't', 'arm', 'a', 'start', 's', 'abort', 'x', ...
                      'clear', 'c', 'zero', 'z', 'plus', '+', 'minus', '-', 'driver', 'q', 'stream', 'r')
    end

    methods
        function L = RigLink()
            L.clearData();
        end

        function delete(L)
            L.close();
        end

        function open(L, port, baud)
            if nargin >= 3, L.baud = baud; end
            L.close();
            L.sp = serialport(port, L.baud, 'Timeout', 0.5);
            configureTerminator(L.sp, 'CR/LF');
            flush(L.sp);
            L.port = port; L.partial = ''; L.state = 'UNKNOWN'; L.streaming = false;
            L.protocol = 1; L.banner = false; L.emulator = false; L.firmware = '';   % learnt again from this board
            d = fullfile(odyssix.repoRoot(), 'results', 'evidence', 'logs');
            if ~isfolder(d), mkdir(d); end
            L.logFile = fullfile(d, ['rig_' char(datetime('now', 'Format', 'yyyyMMdd-HHmmss')) '.log']);
            L.fid = fopen(L.logFile, 'w');
            L.key('t');                         % ask for status: proves the link
            L.key('?');                         % help: its 'Firmware:' line names the protocol
                                                % (the boot banner went out before we connected)
        end

        function tf = isOpen(L)
            tf = ~isempty(L.sp) && isvalid(L.sp);
        end

        function close(L)
            if L.isOpen()
                try
                    L.key('x');                 % de-energise before letting go
                    if L.streaming, L.key('r'); end
                    pause(0.05);
                catch
                end
                delete(L.sp);
            end
            L.sp = [];
            if L.fid > 0, fclose(L.fid); L.fid = -1; end
        end

        function key(L, c)
        %KEY  Send one command byte. Accepts the byte or a name from KEYS.
            if numel(c) > 1, c = L.KEYS.(c); end
            assert(L.isOpen(), 'RigLink: port not open');
            L.io(@() write(L.sp, uint8(c), 'uint8'));         % commands are never skipped
            L.logLine(sprintf('>> %s', c));
        end

        function sendLine(L, cmd)
        %SENDLINE  Send a '$' command line, e.g. L.sendLine('kp=9').
            assert(L.isOpen(), 'RigLink: port not open');
            L.io(@() write(L.sp, uint8(['$' cmd newline]), 'uint8'));
            L.logLine(sprintf('>> $%s', cmd));
        end

        function configure(L, cfg)
        %CONFIGURE  Send a tutorial configuration (odyssix.sim.defaults fields).
        %   exp first (it loads the firmware defaults), then every gain.
            L.lastError = ''; L.runEvent = '';      % no stale event from a previous run
            L.cfg = struct();                       % no stale echo either
            if (cfg.exp == 24 || (isfield(cfg, 'seq') && cfg.seq == 0)) && L.protocol < 4
                error('RigLink:protocol', 'swing-up and lab mode need firmware protocol 4 (2.2.0 or later); flash the current firmware');
            end
            if cfg.exp >= 6 && L.protocol < 3
                error('RigLink:protocol', ['experiment %d needs firmware protocol 3 (2.1.0 or later); ' ...
                    'this board speaks protocol %d: flash the current firmware'], cfg.exp, L.protocol);
            end
            L.sendLine(sprintf('exp=%d', cfg.exp));
            f = L.KEYS2;
            if cfg.exp >= 6, f = [f, L.KEYS3]; end      % Tutorials 2-5 reject the new keys
            if cfg.exp >= 6 && L.protocol >= 4, f = [f, L.KEYS4]; end
            if cfg.exp >= 6 && L.protocol >= 5, f = [f, L.KEYS5]; end
            for i = 1:numel(f)
                if isfield(cfg, f{i}), L.sendLine(sprintf('%s=%.6g', f{i}, cfg.(f{i}))); end
            end
            L.sendLine('cfg');
        end

        function setLive(L, key, val)
        %SETLIVE  Change one gain during a run (experiments 6-10, 21-23), e.g.
        %   L.setLive('kpp', 400). The firmware answers with a C line and applies
        %   gains, filters, rate and limits at once; exp, sequence and step only
        %   take effect on the next run.
            assert(L.protocol >= 3, 'RigLink: live gain changes need protocol 3');
            assert(any(strcmp(key, [L.KEYS2, L.KEYS3, L.KEYS4, L.KEYS5])), 'RigLink: unknown key %s', key);
            L.lastError = '';
            L.sendLine(sprintf('%s=%.6g', key, val));
        end

        function setRef(L, deg)
        %SETREF  Live arm set-point [deg] ('$ref='), slewed at rrate deg/s.
        %   Accepted while experiment 21 regulates, or once 6/7/8/23 hold upright;
        %   the firmware answers 'REF x' (L.lastRef) or 'ERR ...' (L.lastError).
            assert(L.protocol >= 3, 'RigLink: set-point needs protocol 3');
            L.lastError = ''; L.lastRef = NaN;
            L.sendLine(sprintf('ref=%.6g', deg));
        end

        function go(L),      L.runEvent = ''; L.sendLine('go');   end
        function stopRun(L), L.sendLine('stop'); end
        function keepAlive(L)
        %KEEPALIVE  '.' feeds the firmware's 1 s host watchdog during a run.
            % skipped if a timer tick interrupted another serial call: two
            % overlapping calls on one port make MATLAB's serial I/O fail
            if L.isOpen() && ~L.busy, L.io(@() write(L.sp, uint8('.'), 'uint8')); end
        end

        function abort(L)
            if L.isOpen(), L.key('x'); end
        end

        function stream(L, on)
        %STREAM  Switch the 50 Hz stream on or off ('r' is a toggle; tracked here).
            if L.streaming ~= on, L.key('r'); L.streaming = on; end
        end

        function k = poll(L)
        %POLL  Read everything waiting; parse lines. Returns new sample count.
            k = 0;
            if ~L.isOpen() || L.busy, return; end          % next tick reads it
            nb = L.sp.NumBytesAvailable;
            if nb == 0, return; end
            txt = [L.partial, char(L.io(@() read(L.sp, nb, 'uint8')))];
            parts = regexp(txt, '\r?\n', 'split');
            L.partial = parts{end};
            for i = 1:numel(parts) - 1
                s = strtrim(parts{i});
                if isempty(s), continue; end
                if L.fid > 0, fprintf(L.fid, '%s\n', s); end
                if startsWith(s, 'D,')
                    k = k + L.parseData(s);
                elseif startsWith(s, 'k,') || startsWith(s, 'K,')
                    L.parseCrash(s);
                else
                    L.parseText(s);
                end
            end
        end

        function C = takeCrashes(L)
        %TAKECRASHES  Complete 500 Hz crash records received since the last call.
        %   Each: reason, triggerTick, received (UTC), and a table D with t_s
        %   (0 = trigger), tick, rotor_deg, psi_deg, alpha_deg, u, phase.
            C = L.crashDone; L.crashDone = {}; L.crashPending = 0;
        end

        function markPush(L)
        %MARKPUSH  'k': the firmware sends the last 1.5 s and the next 0.5 s at 500 Hz.
            L.key('k');
        end

        function clearData(L)
            L.n = 0; L.T0 = [];
            cap = 50 * 600;
            L.tk = zeros(cap, 1); L.rot = L.tk; L.pen = L.tk; L.raw = L.tk; L.flt = L.tk;
            L.rexp = L.tk; L.rph = L.tk; L.ru = L.tk; L.rref = L.tk;
            L.st = strings(cap, 1);
        end

        function T = table(L)
        %TABLE  Samples since clearData: t_s (MCU time), rotor_deg, psi_deg (pendulum,
        %       encoder sense, 0 = datum), enc_raw, faults, state.
            i = 1:L.n;
            T = table((L.tk(i) - L.tk(1)) * L.TICK_S, L.rot(i), L.pen(i), L.raw(i), L.flt(i), L.st(i), ...
                      L.rexp(i), L.rph(i), L.ru(i), L.rref(i), ...
                'VariableNames', {'t_s', 'rotor_deg', 'psi_deg', 'enc_raw', 'faults', 'state', ...
                                  'run_exp', 'phase', 'u', 'ref_deg'});
        end
    end

    methods (Access = private)
        function varargout = io(L, f)
        %IO  Run one serial call with the busy flag set (cleared on error too).
            L.busy = true;
            try
                [varargout{1:nargout}] = f();
            catch err
                L.busy = false; rethrow(err);
            end
            L.busy = false;
        end

        function ok = parseData(L, s)
            ok = 0;
            f = split(string(s), ',');
            % protocol 1 has 7 fields, protocol 2 has 12; anything else is a damaged
            % or merged line (bytes lost on the link) and is rejected, not half-parsed
            if ~(numel(f) == 7 || numel(f) == 12) || ~any(strcmp(f(7), ["SAFE" "ARMED" "RUNNING" "FAULT"]))
                L.invalidCount = L.invalidCount + 1; return;
            end
            v = str2double(f(2:6));
            if any(isnan(v)), L.invalidCount = L.invalidCount + 1; return; end
            L.n = L.n + 1;
            if L.n > numel(L.tk)               % grow
                g = numel(L.tk);
                L.tk(2*g) = 0; L.rot(2*g) = 0; L.pen(2*g) = 0; L.raw(2*g) = 0; L.flt(2*g) = 0;
                L.st(2*g) = ""; L.rexp(2*g) = 0; L.rph(2*g) = 0; L.ru(2*g) = 0; L.rref(2*g) = 0;
            end
            L.tk(L.n) = v(1); L.rot(L.n) = v(2) / 1000; L.pen(L.n) = v(3) / 1000;
            L.raw(L.n) = v(4); L.flt(L.n) = v(5); L.st(L.n) = f(7);
            if numel(f) == 12                        % protocol 2
                w = str2double(f(8:11));
                L.rexp(L.n) = w(1); L.rph(L.n) = w(2); L.ru(L.n) = w(3); L.rref(L.n) = w(4) / 1000;
                L.protocol = max(L.protocol, 2);    % the D line is the same in protocol 3
            end
            L.state = char(f(7)); L.faults = v(5); L.streaming = true;
            ok = 1;
        end

        function parseCrash(L, s)
            if startsWith(s, 'K,BEGIN')
                f = split(string(s), ',');
                L.crashHdr = struct('reason', char(f(3)), 'n', str2double(f(4)), 'triggerTick', str2double(f(5)));
                L.crashBuf = zeros(0, 5);
            elseif startsWith(s, 'k,') && ~isempty(L.crashHdr)
                v = sscanf(s(3:end), '%f,%f,%f,%f,%f')';
                if numel(v) == 5, L.crashBuf(end+1, :) = v; end
            elseif startsWith(s, 'K,END') && ~isempty(L.crashHdr)
                b = L.crashBuf; h = L.crashHdr; L.crashHdr = [];
                if isempty(b), return; end
                psi = b(:, 3) / 1000;
                D = table((b(:, 1) - h.triggerTick) * L.TICK_S, b(:, 1), b(:, 2) / 1000, psi, ...
                          mod(180 - psi + 180, 360) - 180, b(:, 4), b(:, 5), ...
                    'VariableNames', {'t_s', 'tick', 'rotor_deg', 'psi_deg', 'alpha_deg', 'u', 'phase'});
                L.crashDone{end+1} = struct('reason', h.reason, 'triggerTick', h.triggerTick, ...
                    'complete', height(D) == h.n, 'received', datetime('now', 'TimeZone', 'UTC'), 'D', D);
                L.crashPending = numel(L.crashDone);
            end
        end

        function parseText(L, s)
            L.lines{end+1} = s;
            if numel(L.lines) > 200, L.lines = L.lines(end-199:end); end
            if contains(s, 'THIS IS NOT THE VEHICLE FIRMWARE'), L.banner = true; end
            if contains(s, 'Firmware:'), L.firmware = strtrim(extractAfter(s, 'Firmware:')); end
            if contains(s, 'protocol 2'), L.protocol = max(L.protocol, 2); end
            if contains(s, 'protocol 3'), L.protocol = max(L.protocol, 3); end
            if contains(s, 'protocol 4'), L.protocol = max(L.protocol, 4); end
            if contains(s, 'protocol 5'), L.protocol = 5; end
            if contains(s, 'EMULATOR'), L.emulator = true; end
            if startsWith(s, 'C,')
                v = str2double(split(string(s(3:end)), ','));
                if any(numel(v) == [9 23 25 26])         % protocol 2 / 3 / 4 / 5
                    L.cfg = struct('exp', v(1), 'kp', v(2), 'kd', v(3), 'kpp', v(4), 'kdp', v(5), ...
                                   'step', v(6), 'dist', v(7), 'ulim', v(8), 'vmax', v(9));
                    if numel(v) >= 23
                        for i = 1:numel(L.KEYS3), L.cfg.(L.KEYS3{i}) = v(9 + i); end
                    end
                    if numel(v) >= 25
                        for i = 1:numel(L.KEYS4), L.cfg.(L.KEYS4{i}) = v(23 + i); end
                    end
                    if numel(v) == 26, L.cfg.amp = v(26); end
                end
            end
            if startsWith(s, 'ERR'), L.lastError = s; end
            if startsWith(s, 'REF '), L.lastRef = str2double(s(5:end)); end
            if startsWith(s, 'GO ') || startsWith(s, 'RUN ') || startsWith(s, 'STOPPING'), L.runEvent = s; end
            if contains(s, 'STREAM ON'),  L.streaming = true;  end
            if contains(s, 'STREAM OFF'), L.streaming = false; end
            tok = regexp(s, 'state=(\w+)\s+faults=0x([0-9A-Fa-f]+)', 'tokens', 'once');
            if ~isempty(tok), L.state = tok{1}; L.faults = hex2dec(tok{2}); end
            if contains(s, 'ARMED.'), L.state = 'ARMED'; end
            if contains(s, 'RUNNING.'), L.state = 'RUNNING'; end
            if contains(s, 'ABORT -> SAFE') || contains(s, 'State: SAFE'), L.state = 'SAFE'; end
        end

        function logLine(L, s)
            if L.fid > 0, fprintf(L.fid, '%s\n', s); end
        end
    end
end

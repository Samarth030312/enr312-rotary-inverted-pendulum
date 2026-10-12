function data = enr312_live_view(opts)
%ENR312_LIVE_VIEW  Live MATLAB view of the ENR312 rig over the ST-LINK VCP.
%
%   addpath(genpath(fullfile(<repo>,'matlab')));
%   data = enr312_live_view('Port','/dev/ttyACM0');      % Linux
%   data = enr312_live_view('Port','COM5');              % Windows
%
%   Requires the ENR312 target firmware with the 'r' stream command
%   (firmware/enr312/target). Sends 'r' once, parses the 50 Hz lines
%       D,<ticks>,<rotor mdeg>,<pendulum mdeg>,<encoder raw>,<faults>,<state>
%   and plots rotor and pendulum angle against firmware time (ticks x 2 ms).
%
%   READ-ONLY: this viewer never sends a, s, + or -. It cannot energise or move
%   the motor. Typing those on a separate terminal is the operator's decision.
%   Close the figure (or Ctrl+C) to stop; the stream is switched off on exit.
%
%   Returns a table of every sample received -- save it under data/raw/ with a
%   metadata sidecar (docs/DATA_MANAGEMENT.md) if it is an experiment run.
%   Base MATLAB only (serialport, R2019b+).

    arguments
        opts.Port    (1,:) char   = '/dev/ttyACM0'
        opts.Baud    (1,1) double = 115200
        opts.Window  (1,1) double = 10      % s of history on screen
        opts.Seconds (1,1) double = Inf     % stop after this long
    end

    TICK_S = 0.002;                         % ENR312_CONTROL_PERIOD_S, 500 Hz

    sp = serialport(opts.Port, opts.Baud, 'Timeout', 1);
    configureTerminator(sp, 'CR/LF');
    flush(sp);
    cleanup = onCleanup(@() stopStream(sp));

    % 'r' toggles. Send it, and if the first reply says OFF, send it again.
    % Firmware commands are single bytes; writeline would add CR/LF, which the
    % firmware answers with '? unknown'.
    sendKey(sp, 'r');
    if contains(waitFor(sp, 'STREAM'), 'OFF'), sendKey(sp, 'r'); end

    fig = figure('Name', 'ENR312 live rig', 'NumberTitle', 'off', 'Color', 'w', ...
                 'Position', [100 100 1200 700]);
    if exist('theme', 'file'), theme(fig, 'light'); end
    ax1 = subplot(2, 1, 1, 'Parent', fig); grid(ax1, 'on'); hold(ax1, 'on');
    hR = animatedline(ax1, 'Color', [0.10 0.35 0.75], 'LineWidth', 1.5, 'MaximumNumPoints', 5000);
    ylabel(ax1, 'rotor \theta (deg)');
    ax2 = subplot(2, 1, 2, 'Parent', fig); grid(ax2, 'on'); hold(ax2, 'on');
    hP = animatedline(ax2, 'Color', [0.85 0.20 0.15], 'LineWidth', 1.5, 'MaximumNumPoints', 5000);
    ylabel(ax2, 'pendulum \alpha (deg)'); xlabel(ax2, 'firmware time (s)');
    hT = title(ax1, 'waiting for data...');

    n = 0; cap = 50 * 600;
    T = zeros(cap, 1); R = T; P = T; RAW = T; FLT = T; ST = strings(cap, 1);
    t0 = []; wall = tic;

    while isvalid(fig) && toc(wall) < opts.Seconds
        if sp.NumBytesAvailable == 0, pause(0.005); continue; end
        s = parseLine(readline(sp));
        if isempty(s), continue; end
        if isempty(t0), t0 = s.ticks; end
        n = n + 1;
        if n > cap
            cap = 2 * cap;
            [T(cap), R(cap), P(cap), RAW(cap), FLT(cap)] = deal(0); ST(cap) = "";
        end
        T(n) = (s.ticks - t0) * TICK_S; R(n) = s.rotor; P(n) = s.pend;
        RAW(n) = s.raw; FLT(n) = s.faults; ST(n) = s.state;
        addpoints(hR, T(n), R(n)); addpoints(hP, T(n), P(n));
        if mod(n, 5) == 0
            xl = [max(0, T(n) - opts.Window), max(opts.Window, T(n))];
            xlim(ax1, xl); xlim(ax2, xl);
            hT.String = sprintf('state %s   faults 0x%02X   rotor %+8.3f deg   pendulum %+8.3f deg   raw %u', ...
                                s.state, s.faults, s.rotor, s.pend, s.raw);
            drawnow limitrate;
        end
    end

    k = 1:n;
    data = table(T(k), R(k), P(k), RAW(k), FLT(k), ST(k), 'VariableNames', ...
                 {'t_s', 'rotor_deg', 'pend_deg', 'enc_raw', 'faults', 'state'});
end

% -------------------------------------------------------------------------
function s = parseLine(line)
%PARSELINE  'D,ticks,rotor_mdeg,pend_mdeg,raw,faults,state' -> struct, or [].
    s = [];
    f = split(strtrim(string(line)), ',');
    if numel(f) ~= 7 || f(1) ~= "D", return; end
    v = str2double(f(2:6));
    if any(isnan(v)), return; end
    s = struct('ticks', v(1), 'rotor', v(2) / 1000, 'pend', v(3) / 1000, ...
               'raw', v(4), 'faults', v(5), 'state', f(7));
end

function line = waitFor(sp, key)
    line = "";
    for i = 1:50
        l = readline(sp);
        if ~isempty(l) && contains(l, key), line = l; return; end
    end
end

function sendKey(sp, c)
    write(sp, uint8(c), 'uint8');
end

function stopStream(sp)
    try
        sendKey(sp, 'r');                 % stream was on; toggle it off
    catch
    end
end

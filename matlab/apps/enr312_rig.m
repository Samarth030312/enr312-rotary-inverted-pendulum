function app = enr312_rig()
%ENR312_RIG  Flash, connect and run the ENR312 pendulum rig from MATLAB.
%
%   addpath(genpath(fullfile(<repo>,'matlab'))); enr312_rig
%
%   1 Board     detect the ST-LINK, flash the committed firmware release
%               (no compiler needed) or your own build
%   2 Connect   open the ST-LINK virtual COM port, or start the EMULATOR
%   3 Safety    ARM / START / ABORT. ABORT is always on; Esc or Space also abort.
%   4 Motion    EXP001 first motion +/-5 deg (only when RUNNING)
%   5 Identify  free-swing test: record the hanging pendulum, fit the
%               nonlinear model, compare with the Tutorial values
%
%   The firmware is firmware/enr312 (bare metal, boots SAFE). The protocol and
%   its safety rules are in odyssix.stm32.RigLink. Closing this window sends
%   ABORT. Data saved from hardware goes to data/raw/EXP001 with a metadata
%   sidecar; data from the emulator is labelled SYNTHETIC and kept apart.
%   Base MATLAB only.

    T = odyssix.stm32.tools();
    link = odyssix.stm32.RigLink();
    emu = struct('pid', [], 'port', '');
    armConfirmed = false;
    rec = struct('on', false, 'i0', 0, 'tEnd', 0, 'fit', [], 'data', []);
    C = struct('navy', [0.09 0.16 0.29], 'green', [0.13 0.59 0.33], 'red', [0.80 0.13 0.13], ...
               'amber', [0.85 0.55 0.05], 'grey', [0.45 0.47 0.50], 'blue', [0.16 0.38 0.78], ...
               'pend', [0.86 0.22 0.18], 'bg', [0.96 0.97 0.99]);

    fig = uifigure('Name', 'ENR312 Rig', 'Position', [40 30 1720 980], 'Color', C.bg, ...
                   'CloseRequestFcn', @(~, ~) onClose(), 'WindowKeyPressFcn', @(~, e) onKey(e));
    if exist('theme', 'file'), theme(fig, 'light'); end
    g = uigridlayout(fig, [3 3], 'RowHeight', {60, '1x', 170}, 'ColumnWidth', {380, '1x', '1.1x'}, ...
        'Padding', [10 10 10 10], 'RowSpacing', 8, 'ColumnSpacing', 10, 'BackgroundColor', C.bg);
    hdr = uilabel(g, 'BackgroundColor', C.navy, 'FontColor', 'w', 'FontSize', 22, 'FontWeight', 'bold', ...
        'Text', ['   ENR312  ' char(183) '  Pendulum rig  ' char(183) '  flash, connect, measure' ...
                 '      STM32F401RE + IHM01A1 + LPD3806']);
    hdr.Layout.Row = 1; hdr.Layout.Column = [1 3];

    % --------------------------------------------------------------- controls
    cp = uipanel(g, 'BackgroundColor', 'w', 'BorderType', 'none');
    cp.Layout.Row = [2 3]; cp.Layout.Column = 1;
    cg = uigridlayout(cp, [60 2], 'ColumnWidth', {'1x', '1x'}, 'RowSpacing', 4, ...
        'Padding', [10 8 10 8], 'BackgroundColor', 'w', 'Scrollable', 'on');
    cg.RowHeight = repmat({0}, 1, 60);
    row = 0;
    ui = struct();

    section('1  Board');
    ui.probe = note('Press Detect.', 34);
    ui.detect = btn('Detect board', @(~, ~) onDetect(), [], 1);
    ui.image = uidropdown(cg, 'Items', {'Release (recommended)', 'My local build'}, 'Value', 'Release (recommended)');
    ui.image.Layout.Row = row; ui.image.Layout.Column = 2;
    ui.flash = btn([char(9889) '  Flash firmware'], @(~, ~) onFlash(), C.amber, [1 2], 34);
    ui.rebuild = btn('Rebuild from source', @(~, ~) onRebuild(), [], [1 2]);

    section('2  Connect');
    ui.port = uidropdown(cg, 'Items', {'(no ports)'});
    ui.port.Layout.Row = nextRow(28); ui.port.Layout.Column = 1;
    b = uibutton(cg, 'Text', 'Refresh', 'ButtonPushedFcn', @(~, ~) refreshPorts());
    b.Layout.Row = row; b.Layout.Column = 2;
    ui.connect = btn('Connect', @(~, ~) onConnect(), C.blue, 1, 32);
    ui.emu = uibutton(cg, 'Text', 'Use emulator', 'ButtonPushedFcn', @(~, ~) onEmulator());
    ui.emu.Layout.Row = row; ui.emu.Layout.Column = 2;
    ui.link = note('Not connected.', 36);

    section('3  Safety');
    ui.state = uilabel(cg, 'Text', 'NOT CONNECTED', 'FontSize', 18, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'FontColor', 'w', 'BackgroundColor', C.grey);
    ui.state.Layout.Row = nextRow(40); ui.state.Layout.Column = [1 2];
    ui.arm = btn('ARM (energise)', @(~, ~) onArm(), [], 1, 32);
    ui.start = uibutton(cg, 'Text', 'START (allow motion)', 'ButtonPushedFcn', @(~, ~) send('s'));
    ui.start.Layout.Row = row; ui.start.Layout.Column = 2;
    ui.abort = btn([char(9632) '  ABORT   (Esc / Space)'], @(~, ~) doAbort(), C.red, [1 2], 46);
    ui.abort.FontSize = 16;
    ui.clear = btn('Clear fault', @(~, ~) send('c'), [], 1);
    ui.zero = uibutton(cg, 'Text', 'Zero datums here', 'ButtonPushedFcn', @(~, ~) send('z'));
    ui.zero.Layout.Row = row; ui.zero.Layout.Column = 2;

    section('4  First motion (EXP001)');
    ui.plus  = btn('+5 deg', @(~, ~) send('+'), [], 1, 32);
    ui.minus = uibutton(cg, 'Text', '-5 deg', 'ButtonPushedFcn', @(~, ~) send('-'));
    ui.minus.Layout.Row = row; ui.minus.Layout.Column = 2;
    note(['Measure the arm with a protractor: ~5 deg settles conflict C-1 for 8.889 ' ...
          'microsteps/deg, ~10 deg for 17.778. Expect the hanging pendulum to swing ~3 deg.'], 48);

    section('5  Free-swing identification');
    note(['Motor OFF (SAFE). Let the pendulum hang still, Zero datums, then displace it ' ...
          '20-40 deg, press Record and release.'], 48);
    ui.record = btn([char(9679) '  Record 15 s'], @(~, ~) onRecord(), C.green, 1, 32);
    ui.save = uibutton(cg, 'Text', 'Save run', 'ButtonPushedFcn', @(~, ~) onSave(), 'Enable', 'off');
    ui.save.Layout.Row = row; ui.save.Layout.Column = 2;
    ui.fitText = note('', 92);

    % --------------------------------------------------------------- rig + plots
    mid = uigridlayout(g, [2 1], 'RowHeight', {'1x', 70}, 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
    mid.Layout.Row = 2; mid.Layout.Column = 2;
    axR = uiaxes(mid);
    rig = odyssix.ui.rigBuild(axR, 'ShowReference', false);
    odyssix.ui.rigPose(rig, 0, 180, 0);
    ui.readout = uilabel(mid, 'FontSize', 20, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
        'FontColor', C.navy, 'Text', 'arm  --        pendulum  --');

    pg = uigridlayout(g, [3 1], 'Padding', [0 0 0 0], 'RowSpacing', 4, 'BackgroundColor', C.bg);
    pg.Layout.Row = 2; pg.Layout.Column = 3;
    axP = mkAxes(pg, 'Pendulum \psi (deg, encoder; 0 = datum)');
    axT = mkAxes(pg, 'Arm \theta (deg)');
    axF = mkAxes(pg, 'Free swing: measured vs fitted vs Tutorial'); xlabel(axF, 't (s)');
    hP = plot(axP, nan, nan, 'Color', C.pend, 'LineWidth', 1.6);
    hT = plot(axT, nan, nan, 'Color', C.blue, 'LineWidth', 1.6);

    ui.serial = uitextarea(g, 'Editable', 'off', 'FontName', 'monospaced', 'FontSize', 11, ...
        'Value', {'SERIAL MONITOR'});
    ui.serial.Layout.Row = 3; ui.serial.Layout.Column = [2 3];

    tick = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.05, 'BusyMode', 'drop', ...
                 'TimerFcn', @(~, ~) onTick(), 'ErrorFcn', @(~, e) onTimerError(e));
    refreshPorts(); setEnabled(); onDetect();
    start(tick);

    app = struct('fig', fig, 'link', link, 'ui', ui, 'connect', @connectTo, ...
                 'startEmulator', @onEmulator, 'send', @send, 'abort', @doAbort, ...
                 'record', @onRecord, 'fit', @getFit, 'save', @onSave, ...
                 'armNoPrompt', @() armNow());

    % =================================================================== layout
    function r = nextRow(h)
        row = row + 1; cg.RowHeight{row} = h; r = row;
    end
    function section(txt)
        h = uilabel(cg, 'Text', txt, 'FontWeight', 'bold', 'FontSize', 14, 'FontColor', C.navy, ...
                    'VerticalAlignment', 'bottom');
        h.Layout.Row = nextRow(30); h.Layout.Column = [1 2];
    end
    function h = note(txt, ht)
        h = uilabel(cg, 'Text', txt, 'WordWrap', 'on', 'FontSize', 11, 'FontColor', [0.30 0.32 0.36], ...
                    'VerticalAlignment', 'top');
        h.Layout.Row = nextRow(ht); h.Layout.Column = [1 2];
    end
    function h = btn(txt, fcn, col, cols, ht)
        if nargin < 5, ht = 28; end
        h = uibutton(cg, 'Text', txt, 'ButtonPushedFcn', fcn, 'FontWeight', 'bold');
        if ~isempty(col), h.BackgroundColor = col; h.FontColor = 'w'; end
        h.Layout.Row = nextRow(ht); h.Layout.Column = cols;
    end
    function ax = mkAxes(parent, ttl)
        ax = uiaxes(parent); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
        title(ax, ttl); ax.FontSize = 11;
        try, ax.Toolbar.Visible = 'off'; catch, end
    end

    % =================================================================== board
    function onDetect()
        B = odyssix.stm32.listBoards();
        ui.probe.Text = sprintf('%s\nProgrammer: %s', B.text, shortPath(T.programmer));
        if ~isempty(B.ports), refreshPorts(B.ports{1}); end
    end

    function onFlash()
        if link.isOpen()
            uialert(fig, 'Disconnect first: flashing resets the board and its serial port.', 'Flash'); return;
        end
        img = 'release'; if startsWith(ui.image.Value, 'My'), img = 'build'; end
        d = uiprogressdlg(fig, 'Title', 'Flashing the Nucleo', 'Indeterminate', 'on', ...
            'Message', 'Checking image, identifying the MCU, writing and verifying (about 10 s)...');
        R = odyssix.stm32.flash('Image', img);
        close(d);
        if R.ok
            uialert(fig, sprintf('%s\n\nsha256 %s...\nLog: %s', R.message, R.sha256(1:16), R.logFile), ...
                    'Flashed', 'Icon', 'success');
            pause(1.0); onDetect();
        else
            uialert(fig, sprintf('%s\n\nLog: %s', R.message, R.logFile), 'Flash failed', 'Icon', 'error');
        end
    end

    function onRebuild()
        d = uiprogressdlg(fig, 'Title', 'Rebuilding firmware', 'Indeterminate', 'on', ...
            'Message', 'make -C firmware/enr312/target ...');
        R = odyssix.stm32.build(); close(d);
        L = splitlines(strtrim(R.log)); L = L(max(1, end - 8):end);
        if R.ok
            ui.image.Value = 'My local build';
            uialert(fig, sprintf('Build OK, isolation clean.\nsha256 %s...\n\n%s', R.sha256(1:16), strjoin(L, newline)), ...
                    'Rebuild', 'Icon', 'success');
        else
            uialert(fig, strjoin(L, newline), 'Rebuild failed', 'Icon', 'error');
        end
    end

    % =================================================================== link
    function refreshPorts(prefer)
        B = odyssix.stm32.listBoards();
        p = B.ports;
        if ~isempty(emu.port), p = [{emu.port}, p]; end
        if isempty(p), p = {'(no ports)'}; end
        ui.port.Items = p;
        if nargin >= 1 && any(strcmp(p, prefer)), ui.port.Value = prefer; end
    end

    function onConnect()
        if link.isOpen()
            link.close(); ui.connect.Text = 'Connect'; ui.link.Text = 'Disconnected (ABORT sent).';
            setEnabled(); return;
        end
        connectTo(ui.port.Value);
    end

    function connectTo(port)
        if strcmp(port, '(no ports)'), ui.link.Text = 'No serial port. Plug in the Nucleo, press Refresh.'; return; end
        try
            link.open(port, T.baud);
            link.stream(true);
            ui.connect.Text = 'Disconnect';
            ui.link.Text = sprintf('Open %s @ %d. Waiting for data...', port, T.baud);
            armConfirmed = false;
        catch err
            ui.link.Text = ['Connect failed: ' err.message];
        end
        setEnabled();
    end

    function onEmulator()
        if ~isempty(emu.pid), connectTo(emu.port); return; end
        f = [tempname '.pty'];
        try
            exe = odyssix.stm32.emulatorBinary();
        catch err
            uialert(fig, err.message, 'Emulator'); return;
        end
        system(sprintf('"%s" --pty --parent %d > "%s" 2>&1 & echo $! > "%s.pid"', exe, feature('getpid'), f, f));
        for i = 1:50
            if isfile(f) && ~isempty(strtrim(fileread(f))), break; end
            pause(0.1);
        end
        emu.port = strtrim(fileread(f)); emu.pid = strtrim(fileread([f '.pid']));
        refreshPorts(emu.port);
        connectTo(emu.port);
    end

    function send(c)
        if ~link.isOpen(), return; end
        try, link.key(c); catch err, ui.link.Text = ['Send failed: ' err.message]; end
    end

    function doAbort()
        if link.isOpen(), link.abort(); end
    end

    function onArm()
        if ~armConfirmed
            sel = uiconfirm(fig, ['ARM energises the stepper (it will hold, not move). Before you continue:' newline ...
                '  - 12 V supply connected and its switch within reach' newline ...
                '  - pendulum and arm swing path clear of hands and cables' newline ...
                '  - ABORT here, or Esc / Space, stops it; pulling the 12 V plug always works'], ...
                'Arm the motor', 'Options', {'ARM', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(sel, 'ARM'), return; end
            armConfirmed = true;
        end
        send('a');
    end

    function armNow()
        armConfirmed = true; send('a');
    end

    function onKey(e)
        if any(strcmp(e.Key, {'escape', 'space'})), doAbort(); end
    end

    % =================================================================== tick
    function onTick()
        if ~isvalid(fig), return; end
        if link.isOpen()
            try
                link.poll();
            catch err
                ui.link.Text = ['Link lost: ' err.message]; link.close(); ui.connect.Text = 'Connect';
            end
        end
        setEnabled();
        if link.n > 0
            D = link.table();
            k = height(D);
            w = D.t_s >= D.t_s(end) - 20;
            set(hP, 'XData', D.t_s(w), 'YData', D.psi_deg(w));
            set(hT, 'XData', D.t_s(w), 'YData', D.rotor_deg(w));
            xl = [max(0, D.t_s(end) - 20), max(20, D.t_s(end))];
            xlim(axP, xl); xlim(axT, xl);
            odyssix.ui.rigPose(rig, D.rotor_deg(k), 180 - D.psi_deg(k), D.rotor_deg(k));
            ui.readout.Text = sprintf('arm  %+7.2f deg        pendulum  %+8.2f deg', D.rotor_deg(k), D.psi_deg(k));
            src = 'HARDWARE'; if isEmu(), src = 'EMULATOR (synthetic)'; end
            ui.link.Text = sprintf('%s  %s  %d samples @ 50 Hz, %d bad lines', src, link.port, link.n, link.invalidCount);
            if rec.on
                left = rec.tEnd - D.t_s(end);
                ui.fitText.Text = sprintf('Recording... %.0f s left', max(0, left));
                if left <= 0, finishRecord(D); end
            end
            if link.n > 50 * 600, link.clearData(); end           % keep 10 min
        end
        L = link.lines; L = L(max(1, end - 9):end);
        ui.serial.Value = [{sprintf('SERIAL MONITOR  %s  log: %s', link.port, shortPath(link.logFile))}, L];
    end

    function setEnabled()
        on = link.isOpen();
        st = link.state;
        if ~on, st = 'NOT CONNECTED'; end
        cols = struct('SAFE', C.green, 'ARMED', C.amber, 'RUNNING', C.red, 'FAULT', C.red);
        if isfield(cols, st), col = cols.(st); else, col = C.grey; end
        lbl = st;
        if strcmp(st, 'FAULT'), lbl = sprintf('FAULT 0x%02X: %s', link.faults, faultText(link.faults)); end
        if strcmp(st, 'ARMED'), lbl = 'ARMED: motor energised'; end
        if strcmp(st, 'RUNNING'), lbl = 'RUNNING: motion permitted'; end
        if strcmp(st, 'SAFE'), lbl = 'SAFE: motor off'; end
        ui.state.Text = lbl; ui.state.BackgroundColor = col;
        en = @(h, c) set(h, 'Enable', matlab.lang.OnOffSwitchState(c));
        en(ui.flash, ~on); en(ui.rebuild, ~on); en(ui.image, ~on);
        en(ui.abort, on); en(ui.zero, on); en(ui.clear, on && strcmp(st, 'FAULT'));
        en(ui.arm, on && strcmp(st, 'SAFE'));
        en(ui.start, on && strcmp(st, 'ARMED'));
        en(ui.plus, on && strcmp(st, 'RUNNING')); en(ui.minus, on && strcmp(st, 'RUNNING'));
        en(ui.record, on && any(strcmp(st, {'SAFE', 'FAULT'})) && ~rec.on);
        en(ui.save, ~isempty(rec.fit));
        en(ui.emu, ~on && isunix);
    end

    % =================================================================== identification
    function onRecord()
        if ~any(strcmp(link.state, {'SAFE', 'FAULT'}))
            uialert(fig, 'ABORT first: the free-swing test needs the motor de-energised.', 'Record'); return;
        end
        D = link.table();
        if isempty(D), return; end
        rec.on = true; rec.i0 = height(D) + 1; rec.tEnd = D.t_s(end) + 15; rec.fit = [];
        cla(axF); hold(axF, 'on');
    end

    function finishRecord(D)
        rec.on = false;
        d = D(rec.i0:end, :);
        rec.data = d;
        if height(d) < 100 || max(d.psi_deg) - min(d.psi_deg) < 4
            ui.fitText.Text = 'Not enough swing recorded (need > 4 deg peak-to-peak). Try again.'; return;
        end
        ui.fitText.Text = 'Fitting the nonlinear model...'; drawnow;
        f = pendulum_free_swing_fit(d.t_s, d.psi_deg);
        rec.fit = f;
        pT = rotary_pendulum_params('suspended');
        yT = pendulum_free_swing_sim(f.t, pT.wg2, pT.gamma, f.amplitudeDeg * sign(f.yDeg(1) - f.offsetDeg), f.offsetDeg);
        cla(axF); hold(axF, 'on');
        plot(axF, f.t, f.yDeg, '.', 'Color', [0.2 0.2 0.2], 'MarkerSize', 6);
        plot(axF, f.t, f.yFitDeg, 'Color', C.pend, 'LineWidth', 1.6);
        plot(axF, f.t, yT, '--', 'Color', C.blue, 'LineWidth', 1.2);
        cls = 'MEASURED'; if isEmu(), cls = 'SYNTHETIC (emulator)'; end
        legend(axF, {[cls ' data'], 'fitted nonlinear model', 'Tutorial 3/12 prediction'}, 'Location', 'northeast');
        ui.fitText.Text = sprintf([ ...
            '%s\nwg2 = %.2f 1/s^2  (Tutorial 57.01, %+.1f %%)\nQ = %.1f  (Tutorial 27)\n' ...
            'small-angle period %.3f s,  L_eq = %.3f m\nfit rms %.2f deg over %.1f s'], ...
            cls, f.wg2, 100 * (f.wg2 / pT.wg2 - 1), f.Q, f.periodSmallAngle, ...
            9.81 / (f.wg2 * 0.6805), f.rmsDeg, f.t(end));
    end

    function onSave()
        if isempty(rec.fit), return; end
        [~, rev] = system(sprintf('git -C "%s" rev-parse --short HEAD', T.repo)); rev = strtrim(rev);
        [~, full] = system(sprintf('git -C "%s" rev-parse HEAD', T.repo)); full = strtrim(full);
        [~, dirty] = system(sprintf('git -C "%s" status --porcelain', T.repo));
        now_ = datetime('now', 'TimeZone', 'UTC');
        stem = sprintf('EXP001_%s_%s_freeswing', char(now_, 'yyyyMMdd_HHmm'), rev);
        f = rec.fit;
        if isEmu()
            dDir = fullfile(T.repo, 'matlab', 'data', 'synthetic'); stem = [stem '_emulator_synthetic'];
            mDir = dDir; cls = 'SYNTHETIC';
        else
            dDir = fullfile(T.repo, 'data', 'raw', 'EXP001'); mDir = fullfile(T.repo, 'data', 'metadata', 'EXP001');
            cls = 'HARDWARE';
        end
        if ~isfolder(dDir), mkdir(dDir); end
        csv = fullfile(dDir, [stem '.csv']);
        if isfile(csv), uialert(fig, 'A run with this name exists; wait a minute and save again.', 'Save'); return; end
        writetable(rec.data, csv);
        if isunix, system(sprintf('chmod 444 "%s"', csv)); end           % raw data is immutable
        y = {sprintf('experiment_id: EXP001'), sprintf('data_class: %s', cls), ...
             sprintf('raw_data_file: %s', strrep(csv, [T.repo filesep], '')), ...
             sprintf('date: %s', char(now_, 'yyyy-MM-dd')), sprintf('time_utc: %s', char(now_, 'HH:mm')), ...
             'operator: ""          # FILL IN', ...
             'test: free swing, hanging, motor de-energised (SAFE)', ...
             sprintf('repository: {commit: %s, short_commit: %s, dirty: %s}', full, rev, string(~isempty(strtrim(dirty)))), ...
             sprintf('serial_port: %s', link.port), 'sampling_rate_hz: 50', ...
             'units: {t_s: s (MCU ticks x 0.002), rotor_deg: deg, psi_deg: deg (encoder, 0 = datum), enc_raw: counts}', ...
             'processing: none (raw); fit by matlab/identification/pendulum_free_swing_fit.m', ...
             sprintf('fit: {wg2: %.4f, gamma: %.5f, Q: %.3f, offset_deg: %.3f, rms_deg: %.4f}', f.wg2, f.gamma, f.Q, f.offsetDeg, f.rmsDeg), ...
             'hardware: {rig: STEVAL-EDUKIT01, rig_confirmed_by_inspection: null, configuration: suspended}  # FILL IN'};
        if ~isfolder(mDir), mkdir(mDir); end
        fid = fopen(fullfile(mDir, [stem '.yaml']), 'w'); fprintf(fid, '%s\n', y{:}); fclose(fid);
        uialert(fig, sprintf('Saved %s data:\n%s\nMetadata: %s.yaml (complete the FILL IN fields).', ...
                cls, csv, stem), 'Saved', 'Icon', 'success');
    end

    % =================================================================== misc
    function f = getFit()
        f = rec.fit;                 % nested: an anonymous @() rec.fit would freeze rec
    end

    function tf = isEmu()
        tf = ~isempty(emu.port) && strcmp(link.port, emu.port);
    end

    function onTimerError(e)
        try, ui.link.Text = ['Internal error: ' e.Data.message]; catch, end
    end

    function onClose()
        try, stop(tick); delete(tick); catch, end
        try, link.close(); catch, end                       % sends ABORT
        if ~isempty(emu.pid), system(['kill ' emu.pid ' 2>/dev/null']); end
        delete(fig);
    end
end

function s = shortPath(p)
    if isempty(p), s = '(none)'; return; end
    [d, n, e] = fileparts(p); [~, d1] = fileparts(d); s = fullfile('...', d1, [n e]);
end

function s = faultText(f)
    names = {'L6474 FLAG', 'SPI timeout', 'L6474 ID', 'rotor limit', 'pendulum limit', ...
             'encoder stuck', 'operator abort', 'control overrun'};
    s = strjoin(names(logical(bitget(uint32(f), 1:8))), ', ');
    if isempty(s), s = 'none'; end
end

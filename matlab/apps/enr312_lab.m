function app = enr312_lab()
%ENR312_LAB  The ENR312 rotary-pendulum lab: Tutorials 1-10 and PEND, simulation AND rig.
%
%   addpath(genpath(fullfile(<repo>,'matlab'))); enr312_lab
%
%   Pick a tutorial (T1-T10) or a PEND experiment (P21-P23) and a preset, then tinker:
%     Controller  rotor PD/PID (Kp, Ki, Kd), pendulum PD (Kpp, Kdp), state feedback
%                 (k1..k4, LQR designer), on-off, filters, loop rate, step,
%                 disturbance, limit; only the controls an experiment uses are shown
%     Hold        command the arm to an angle ('$ref'), in simulation and live on
%                 the rig; change gains live during a rig run (T6-T10, PEND)
%     Physics     pendulum length (wg2), damping Q, arm radius (wr2),
%                 nonlinear physics, encoder/microstep quantisation
%   SIMULATE runs odyssix.sim.runTutorial, a line-by-line port of the firmware
%   control path, verified identical to the firmware code
%   (matlab/tests/test_sim_matches_firmware.m).
%   RUN ON RIG sends the same configuration to the board ('$' protocol 2/3) and
%   overlays the measurement on the simulation, with the same metrics.
%   No board? "Use emulator": the firmware's own control code on the PC.
%
%   Safety: ARM asks for confirmation; ABORT (button, Esc or Space) is always
%   live; MATLAB feeds the firmware's 1 s host watchdog while a run is active,
%   so a crashed or closed MATLAB stops the rig; closing the window aborts.
%   Base MATLAB only.

    C = struct('navy', [0.09 0.16 0.29], 'green', [0.13 0.59 0.33], 'red', [0.80 0.13 0.13], ...
               'amber', [0.85 0.55 0.05], 'grey', [0.45 0.47 0.50], 'blue', [0.16 0.38 0.78], ...
               'pend', [0.86 0.22 0.18], 'bg', [0.96 0.97 0.99], 'sim', [0.55 0.55 0.60]);
    TUT = tutorials();
    T = odyssix.stm32.tools();
    link = odyssix.stm32.RigLink();
    emu = struct('pid', '', 'port', '');
    armOk = false;
    wrFail = 0;                   % consecutive keep-alive write errors
    lastN = -1; dataT = tic;      % stale-data detector
    tut = 5; cfg = odyssix.sim.defaults(5); pl = odyssix.sim.plant(5);
    S = []; lp = []; H = []; hwRun = struct('on', false, 'i0', 0, 'cfg', [], 'seq', 0, 't0', tic);
    NEW = {'ki', 'fdr', 'fdp', 'k1', 'k2', 'k3', 'k4', 'bv', 'imp', 'uon', 'db', 'div', 'ma'};
    fitRes = []; recording = struct('on', false, 'i0', 0, 'tEnd', 0);

    fig = uifigure('Name', 'ENR312 Lab', 'Position', [30 20 1780 1000], 'Color', C.bg, ...
                   'CloseRequestFcn', @(~, ~) onClose(), 'WindowKeyPressFcn', @(~, e) onKey(e));
    if exist('theme', 'file'), theme(fig, 'light'); end
    g = uigridlayout(fig, [3 3], 'RowHeight', {56, '1x', 230}, 'ColumnWidth', {380, '1x', '1.15x'}, ...
        'Padding', [8 8 8 8], 'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', C.bg);
    hdr = uilabel(g, 'BackgroundColor', C.navy, 'FontColor', 'w', 'FontSize', 21, 'FontWeight', 'bold', ...
        'Text', ['   ENR312  ' char(183) '  Rotary pendulum lab  ' char(183) '  Tutorials 1-10 + PEND' ...
                 '      simulate  ' char(8594) '  run on the rig  ' char(8594) '  compare']);
    hdr.Layout.Row = 1; hdr.Layout.Column = [1 3];

    % ================================================================ controls
    cp = uipanel(g, 'BackgroundColor', 'w', 'BorderType', 'none');
    cp.Layout.Row = [2 3]; cp.Layout.Column = 1;
    cg = uigridlayout(cp, [130 2], 'ColumnWidth', {'1x', '1x'}, 'RowSpacing', 3, ...
        'Padding', [10 6 10 6], 'BackgroundColor', 'w', 'Scrollable', 'on');
    cg.RowHeight = repmat({0}, 1, 130); row = 0; ui = struct();

    section('Tutorial');
    ui.tut = uidropdown(cg, 'Items', {TUT.name}, 'ItemsData', [TUT.exp], 'Value', 5, 'FontSize', 13, ...
        'ValueChangedFcn', @(~, ~) selectTutorial(ui.tut.Value));
    place(ui.tut, nextRow(28), [1 2]);
    tg = uigridlayout(cg, [2 10], 'Padding', [0 0 0 0], 'ColumnSpacing', 2, 'RowSpacing', 2, ...
        'RowHeight', {28, 26}, 'BackgroundColor', 'w');
    place(tg, nextRow(56), [1 2]);
    ui.tb = matlab.ui.control.Button.empty;
    for kk = 1:10
        ui.tb(kk) = uibutton(tg, 'Text', sprintf('T%d', kk), 'FontWeight', 'bold', 'UserData', kk, ...
            'ButtonPushedFcn', @(src, ~) selectTutorial(src.UserData));
        ui.tb(kk).Layout.Row = 1; ui.tb(kk).Layout.Column = kk;
    end
    pend = {21, 'P21 stop swing', [1 3]; 22, 'P22 on-off', [4 6]; 23, 'P23 LQR upright', [7 10]};
    for kk = 1:3
        b = uibutton(tg, 'Text', pend{kk, 2}, 'FontWeight', 'bold', 'FontSize', 11, 'UserData', pend{kk, 1}, ...
            'ButtonPushedFcn', @(src, ~) selectTutorial(src.UserData));
        b.Layout.Row = 2; b.Layout.Column = pend{kk, 3}; ui.tb(end + 1) = b;
    end
    ui.preset = uidropdown(cg, 'Items', {'-'}, 'ValueChangedFcn', @(~, ~) applyPreset());
    place(ui.preset, nextRow(26), [1 2]);

    section('Controller');
    ui.ctrlNote = note('', 44);
    ui.kp   = slider('Kp  rotor (outer)', [0 25], 9, '%.2f');
    ui.ki   = slider('Ki  rotor = Kp/Ti (outer)', [0 20], 0, '%.2f');
    ui.kd   = slider('Kd  rotor (outer)', [0 25], 9, '%.2f');
    ui.kpp  = slider('Kp  pendulum (inner)', [0 600], 300, '%.1f');
    ui.kdp  = slider('Kd  pendulum (inner)', [0 80], 30, '%.2f');
    ui.k1   = slider('k1  state feedback, rotor angle', [-50 50], 1, '%.3f');
    ui.k2   = slider('k2  state feedback, rotor rate', [-50 50], 2, '%.3f');
    ui.k3   = slider('k3  state feedback, pendulum angle', [0 800], 0, '%.2f');
    ui.k4   = slider('k4  state feedback, pendulum rate', [0 150], 0, '%.2f');
    ui.bv   = slider('b  virtual rotor damping (1/s)', [0 5], 0, '%.2f');
    ui.lqrQ = uieditfield(cg, 'text', 'Value', '1 1', 'Tooltip', 'diag(Q), one weight per state');
    place(ui.lqrQ, nextRow(26), 1); ui.lqrRow = row;
    ui.lqrR = uieditfield(cg, 'numeric', 'Value', 1, 'Limits', [1e-6 1e6], 'Tooltip', 'R (input weight)');
    place(ui.lqrR, row, 2);
    ui.lqr = btn('LQR: compute k from Q, R', @(~, ~) onLqr(), [], [1 2]); ui.lqrRow(2) = row;
    ui.uon  = slider('On-off level (deg/s^2)', [0 800], 200, '%.0f');
    ui.db   = slider('On-off dead band (deg)', [0 5], 0.5, '%.2f');
    ui.imp  = slider('Pendulum-reference impulse (deg)', [-20 20], 10, '%.1f');
    ui.step = slider('Rotor step (deg)', [-10 10], 2, '%.2f');
    ui.dist = slider('Load disturbance D (deg/s^2)', [-5 5], 1, '%.2f');
    ui.ulim = slider('Actuator limit (deg/s^2)', [50 1500], 1500, '%.0f');
    ui.fdr  = slider('Rotor D filter corner (Hz)', [0.5 200], 50, '%.1f');
    ui.fdp  = slider('Pendulum D filter corner (Hz)', [0.5 200], 10, '%.1f');
    ui.div  = slider('Loop rate divider (500/div Hz)', [1 50], 1, '%.0f');
    ui.ma   = slider('Pendulum moving average (samples)', [1 32], 1, '%.0f');
    ui.div.ValueChangedFcn = @(s, ~) intSlider(s); ui.ma.ValueChangedFcn = @(s, ~) intSlider(s);

    section('Hold the arm at an angle');
    ui.holdNote = note('', 44);
    ui.target = uieditfield(cg, 'numeric', 'Value', 30, 'Limits', [-90 90], 'ValueDisplayFormat', '%.1f deg', ...
        'ValueChangedFcn', @(~, ~) update());
    place(ui.target, nextRow(26), 1);
    ui.simTarget = uicheckbox(cg, 'Text', 'in simulation', 'Value', false, 'ValueChangedFcn', @(~, ~) update());
    place(ui.simTarget, row, 2);
    ui.goto = btn([char(8635) '  Go to angle (rig, live)'], @(~, ~) onGoto(), C.blue, 1, 30);
    ui.live = uibutton(cg, 'Text', 'Apply gains live', 'ButtonPushedFcn', @(~, ~) onLive());
    place(ui.live, row, 2);

    section('Simulate');
    ui.sim = btn([char(9654) '  Simulate'], @(~, ~) animateSim(), C.green, 1, 36);
    ui.speed = uidropdown(cg, 'Items', {'0.5x', '1x', '2x'}, 'Value', '1x');
    place(ui.speed, row, 2);

    section('Rig');
    ui.probe = note('Detect the board, or use the emulator.', 30);
    ui.detect = btn('Detect board', @(~, ~) onDetect(), [], 1);
    ui.flash = uibutton(cg, 'Text', [char(9889) ' Flash firmware'], 'BackgroundColor', C.amber, ...
        'FontColor', 'w', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onFlash());
    place(ui.flash, row, 2);
    ui.port = uidropdown(cg, 'Items', {'(no ports)'}); place(ui.port, nextRow(26), 1);
    ui.connect = uibutton(cg, 'Text', 'Connect', 'BackgroundColor', C.blue, 'FontColor', 'w', ...
        'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onConnect());
    place(ui.connect, row, 2);
    ui.emu = btn('Use emulator (no board)', @(~, ~) onEmulator(), [], [1 2]);
    ui.state = uilabel(cg, 'Text', 'NOT CONNECTED', 'FontSize', 16, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'FontColor', 'w', 'BackgroundColor', C.grey);
    place(ui.state, nextRow(36), [1 2]);
    ui.arm = btn('ARM (energise)', @(~, ~) onArm(), [], 1, 30);
    ui.start = uibutton(cg, 'Text', 'START (allow motion)', 'ButtonPushedFcn', @(~, ~) send('s'));
    place(ui.start, row, 2);
    ui.run = btn([char(9654) '  Run on rig'], @(~, ~) onRunRig(), C.blue, 1, 36);
    ui.stopRun = uibutton(cg, 'Text', 'Stop run', 'ButtonPushedFcn', @(~, ~) onStopRun());
    place(ui.stopRun, row, 2);
    ui.abort = btn([char(9632) '  ABORT   (Esc / Space)'], @(~, ~) doAbort(), C.red, [1 2], 42);
    ui.abort.FontSize = 15;
    ui.zero = btn('Zero datums (hanging, still)', @(~, ~) send('z'), [], 1);
    ui.clear = uibutton(cg, 'Text', 'Clear fault', 'ButtonPushedFcn', @(~, ~) send('c'));
    place(ui.clear, row, 2);
    ui.hold = btn('Emulator: hold pendulum upright', @(~, ~) send('^'), [], [1 2]);
    ui.pluck = btn('Emulator: pluck 30 deg', @(~, ~) send('!'), [], 1);
    ui.record = uibutton(cg, 'Text', 'Free swing: record 15 s', 'ButtonPushedFcn', @(~, ~) onRecord());
    place(ui.record, row, 2);
    ui.useFit = btn('Use measured wg2, Q in the simulation', @(~, ~) onUseFit(), [], [1 2]);
    ui.save = btn('Save rig run (data + metadata)', @(~, ~) onSave(), [], [1 2]);
    ui.link = note('', 46);

    section('Physics (Tutorial values until you measure your rig)');
    ui.L   = slider('Pendulum equivalent length L (m)', [0.15 0.40], 0.258, '%.3f');
    ui.Q   = slider('Pivot quality factor Q', [3 60], 20, '%.1f');
    ui.r   = slider('Arm radius r (m)', [0.08 0.20], 0.141, '%.3f');
    ui.nonlin = check('Nonlinear physics (sin, cos, centrifugal)', true);
    ui.quant  = check('Encoder (0.15 deg) / microstep (0.1125 deg) quantisation', true);


    % ================================================================ centre
    mid = uigridlayout(g, [4 1], 'RowHeight', {34, 64, '1x', 34}, 'Padding', [0 0 0 0], ...
        'RowSpacing', 3, 'BackgroundColor', 'w');
    mid.Layout.Row = 2; mid.Layout.Column = 2;
    ui.badge = uilabel(mid, 'FontSize', 15, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontColor', 'w');
    ui.caption = uilabel(mid, 'FontSize', 13.5, 'WordWrap', 'on', 'HorizontalAlignment', 'center', ...
        'FontColor', C.navy, 'BackgroundColor', [0.91 0.94 0.99]);
    axR = uiaxes(mid); rig = odyssix.ui.rigBuild(axR);
    ui.readout = uilabel(mid, 'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'FontColor', C.navy);

    % ================================================================ plots
    pg = uigridlayout(g, [3 2], 'RowHeight', {'1x', '1x', '1.1x'}, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 4, 'ColumnSpacing', 6, 'BackgroundColor', C.bg);
    pg.Layout.Row = 2; pg.Layout.Column = 3;
    axT = mkAx(pg, 'Rotor \theta (deg)', 1, [1 2]);
    axP = mkAx(pg, 'Pendulum (deg)', 2, [1 2]);
    axU = mkAx(pg, 'Actuator u (deg/s^2)', 3, 1); xlabel(axU, 't (s)');
    axA = mkAx(pg, 'Analysis', 3, 2);
    tr = struct();
    tr.ref  = plot(axT, nan, nan, '--', 'Color', C.green, 'LineWidth', 1.4);
    tr.thS  = plot(axT, nan, nan, 'Color', C.sim, 'LineWidth', 1.8);
    tr.thH  = plot(axT, nan, nan, 'Color', C.blue, 'LineWidth', 2.0);
    tr.dotT = plot(axT, nan, nan, 'o', 'MarkerFaceColor', C.blue, 'MarkerEdgeColor', 'w', 'MarkerSize', 7);
    legend(axT, {'reference', 'simulation', 'rig'}, 'Location', 'best', 'AutoUpdate', 'off');
    tr.pS   = plot(axP, nan, nan, 'Color', C.sim, 'LineWidth', 1.8);
    tr.pH   = plot(axP, nan, nan, 'Color', C.pend, 'LineWidth', 2.0);
    tr.dotP = plot(axP, nan, nan, 'o', 'MarkerFaceColor', C.pend, 'MarkerEdgeColor', 'w', 'MarkerSize', 7);
    tr.uS   = plot(axU, nan, nan, 'Color', C.sim, 'LineWidth', 1.0);
    tr.uH   = plot(axU, nan, nan, 'Color', [0.45 0.25 0.65], 'LineWidth', 1.2);

    % ================================================================ bottom
    ui.table = uitable(g, 'ColumnName', {'Metric', 'Simulation', 'Rig', 'Tutorial'}, ...
        'RowName', {}, 'ColumnWidth', {250, 110, 110, 150}, 'FontSize', 12);
    ui.table.Layout.Row = 3; ui.table.Layout.Column = 2;
    ui.limits = uilabel(g, 'Interpreter', 'html', 'WordWrap', 'on', 'VerticalAlignment', 'top', ...
        'BackgroundColor', [1.0 0.97 0.88], 'FontSize', 11.5);
    ui.limits.Layout.Row = 3; ui.limits.Layout.Column = 3;

    tick = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, 'BusyMode', 'drop', ...
                 'TimerFcn', @(~, ~) onTick(), 'ErrorFcn', @(~, e) say(['internal: ' e.Data.message]));
    refreshPorts(); selectTutorial(5); setEnabled(); start(tick);

    app = struct('fig', fig, 'ui', ui, 'link', link, 'select', @selectTutorial, 'preset', @setPreset, ...
                 'set', @setParam, 'simulate', @animateSim, 'result', @() getSim(), ...
                 'startEmulator', @onEmulator, 'send', @send, 'armNoPrompt', @() armNow(), ...
                 'runRig', @onRunRig, 'rigData', @() getRig(), 'abort', @doAbort, ...
                 'gotoAngle', @(v) gotoNow(v), 'live', @onLive, 'lqr', @onLqr, 'rigCfg', @() getRigCfg(), ...
                 'record', @onRecord, 'fit', @() getFit(), 'useFit', @onUseFit, 'save', @onSave);

    % =================================================================== tutorial
    function selectTutorial(k)
        tut = k; ui.tut.Value = k; E = TT();
        ui.preset.Items = E.presets(:, 1)';
        ui.preset.Value = ui.preset.Items{1};
        pl = odyssix.sim.plant(max(k, 2));
        setSlider(ui.L, 9.81 / (pl.wg2 * 0.6805)); setSlider(ui.Q, pl.Q); setSlider(ui.r, pl.wr2 * 9.81 / pl.wg2);
        ui.caption.Text = E.caption;
        for j = 1:numel(ui.tb)
            if ui.tb(j).UserData == k, set(ui.tb(j), 'BackgroundColor', C.navy, 'FontColor', 'w');
            else,                      set(ui.tb(j), 'BackgroundColor', [0.93 0.94 0.96], 'FontColor', C.navy); end
        end
        ui.run.Text = sprintf('%s  Run %s on rig', char(9654), E.short);
        ui.ctrlNote.Text = E.note;
        ui.limits.Text = limitsHtml(E.limit);
        if k == 10, ui.lqrQ.Value = '1 1'; ui.lqrR.Value = 1; end
        if k == 23, ui.lqrQ.Value = '1 1 10 1'; ui.lqrR.Value = 0.01; end
        if any(k == [21 6 7 8 23])
            ui.holdNote.Text = sprintf(['%s: type an arm angle. On the rig, Go to angle moves the arm there ' ...
                '(slewed at 90 deg/s) %s. "in simulation" commands it at the end of the sequence.'], ...
                E.short, ternary(k == 21, 'while it regulates', 'once the pendulum balances in HOLD'));
        elseif k >= 6
            ui.holdNote.Text = sprintf(['%s runs a fixed sequence (step and back, then done): set the angle ' ...
                'with the step slider. Live set-points: P21 (hanging) or T6/T7/T8/P23 (upright).'], E.short);
        else
            ui.holdNote.Text = 'Tutorials 1-5 run the original, rig-validated sequences: angle = the step slider.';
        end
        H = []; clearRig();
        applyPreset();
    end

    function applyPreset()
        p = TT().presets(strcmp(TT().presets(:, 1), ui.preset.Value), :);
        cfg = odyssix.sim.defaults(tut);
        v = p{2};
        f = fieldnames(v);
        for i = 1:numel(f), cfg.(f{i}) = v.(f{i}); end
        ui.ulim.Limits = [50, maxUlim(tut)];
        enableFor(tut);                                  % sets limits before values
        setSlider(ui.kp, cfg.kp); setSlider(ui.kd, cfg.kd); setSlider(ui.kpp, cfg.kpp); setSlider(ui.kdp, cfg.kdp);
        setSlider(ui.step, cfg.step); setSlider(ui.dist, cfg.dist); setSlider(ui.ulim, cfg.ulim);
        for i = 1:numel(NEW), if isfield(cfg, NEW{i}), setSlider(ui.(NEW{i}), cfg.(NEW{i})); end, end
        update();
    end

    function setPreset(name), ui.preset.Value = name; applyPreset(); end

    function enableFor(k)
        % Tutorials 1-5: the original controls, greyed when unused. The new
        % controls are shown only for the experiments that use them.
        on = @(h, c) set(h, 'Enable', matlab.lang.OnOffSwitchState(c));
        pid = any(k == [2:8 21]); inner = any(k == [3:8 21]);
        on(ui.kp, pid); on(ui.kd, pid); on(ui.kpp, inner); on(ui.kdp, inner);
        on(ui.dist, any(k == [2 8])); on(ui.ulim, k >= 2);
        on(ui.step, ~any(k == [7 21]));
        ui.step.Limits = [-10 10]; if k == 1 || k >= 6, ui.step.Limits = [-45 45]; end
        ui.dist.Limits = [-5 5]; if k == 8, ui.dist.Limits = [-60 60]; end
        ui.kpp.Limits = [0 600]; ui.kdp.Limits = [0 80]; if k >= 6, ui.kpp.Limits = [0 1000]; ui.kdp.Limits = [0 200]; end
        vis = struct('ki', any(k == [6 8 21]), 'fdr', any(k == [6 7 8 21]), 'fdp', any(k == [6 7 8 21 23]), ...
                     'k1', any(k == [9 10 23]), 'k2', any(k == [9 10 23]), 'k3', k == 23, 'k4', k == 23, ...
                     'bv', any(k == [9 10]), 'imp', k == 7, 'uon', k == 22, 'db', k == 22, ...
                     'div', k >= 6, 'ma', k >= 6);
        for i = 1:numel(NEW), showSlider(ui.(NEW{i}), vis.(NEW{i})); end
        lq = any(k == [10 23]);
        for r = ui.lqrRow, cg.RowHeight{r} = 26 * lq; end
        set([ui.lqrQ ui.lqrR ui.lqr], 'Visible', matlab.lang.OnOffSwitchState(lq));
        hasRef = any(k == [21 6 7 8 23]);
        set([ui.target ui.simTarget], 'Enable', matlab.lang.OnOffSwitchState(hasRef));
    end

    function showSlider(s, v)
        u = s.UserData; ho = matlab.lang.OnOffSwitchState(v);
        cg.RowHeight{u.rows(1)} = 18 * v; cg.RowHeight{u.rows(2)} = 22 * v;
        set([u.name u.label s], 'Visible', ho);
    end

    function intSlider(s)
        setSlider(s, round(s.Value)); update();
    end

    function readControls()
        cfg.kp = ui.kp.Value; cfg.kd = ui.kd.Value; cfg.kpp = ui.kpp.Value; cfg.kdp = ui.kdp.Value;
        cfg.step = ui.step.Value; cfg.dist = ui.dist.Value; cfg.ulim = ui.ulim.Value;
        if tut >= 6                     % Tutorials 1-5 have no such fields (firmware rejects them)
            for i = 1:numel(NEW), cfg.(NEW{i}) = ui.(NEW{i}).Value; end
            cfg.div = round(cfg.div); cfg.ma = round(cfg.ma);
        end
        pl.wg2 = 9.81 / (ui.L.Value * 0.6805); pl.Q = ui.Q.Value; pl.wr2 = ui.r.Value * pl.wg2 / 9.81;
        pl.nonlinear = ui.nonlin.Value; pl.quant = ui.quant.Value;
    end

    function update()
        readControls();
        if tut >= 6
            [o, cfg] = simOpts(cfg);
            S = odyssix.sim.runCtrl(cfg, pl, o);
        else
            S = odyssix.sim.runTutorial(cfg, pl);
        end
        if tut >= 2, lp = odyssix.sim.loop(cfg, pl); else, lp = []; end
        drawSim(height(S));
        drawAnalysis();
        fillTable();
        verdict();
    end

    function [o, c] = simOpts(c)
        % the simulated operator: P21 plucks the pendulum 20 deg before the run;
        % "in simulation" sends '$ref' after the sequence (12 s more)
        o = struct(); c.target = NaN; c.target_t = NaN;
        c.seconds = odyssix.sim.defaults(c.exp).seconds;
        if tut == 21, o.psi0 = 20; end
        if ui.simTarget.Value && any(tut == [21 6 7 8 23])
            c.target = ui.target.Value; c.target_t = c.seconds; c.seconds = c.seconds + 12;
            o.events = struct('t', c.target_t, 'key', 'ref', 'val', c.target);
        end
    end

    % =================================================================== drawing
    function drawSim(k)
        t = S.t(1:k);
        set(tr.ref, 'XData', S.t, 'YData', S.ref);
        set(tr.thS, 'XData', t, 'YData', S.rotor(1:k));
        set(tr.pS, 'XData', t, 'YData', pendView(S.psi(1:k)));
        set(tr.uS, 'XData', t, 'YData', S.u(1:k));
        set(tr.dotT, 'XData', S.t(k), 'YData', S.rotor(k)); set(tr.dotP, 'XData', S.t(k), 'YData', pendView(S.psi(k)));
        for ax = [axT axP axU], xlim(ax, [0 S.t(end)]); end
        ylabel(axP, ternary(isInv(), '\alpha from upright', '\psi from hanging'));
        autoY();
        odyssix.ui.rigPose(rig, S.rotor(k), 180 - S.psi(k), S.ref(k), ui.L.Value / 0.258);
        ui.readout.Text = sprintf('SIM  t %5.2f s    arm %+7.2f deg    pendulum %+7.2f deg', S.t(k), S.rotor(k), pendView(S.psi(k)));
    end

    function autoY()
        y = [S.rotor; S.ref]; if ~isempty(H), y = [y; H.rotor]; end
        ylim(axT, pad([min(y) max(y)], 0.5));
        y = pendView(S.psi); if ~isempty(H), y = [y; pendView(H.psi)]; end
        ylim(axP, pad([min(y) max(y)], 0.5));
        y = S.u; if ~isempty(H), y = [y; H.u]; end
        ylim(axU, pad([min(y) max(y)], 10));
    end

    function animateSim()
        sp = sscanf(ui.speed.Value, '%f'); ui.sim.Enable = 'off';
        c = onCleanup(@() set(ui.sim, 'Enable', 'on'));
        t0 = tic;
        for k = 1:12:height(S)
            while toc(t0) * sp < S.t(k), end
            if ~isvalid(fig), return; end
            drawSim(k); drawnow limitrate;
        end
        drawSim(height(S));
    end

    function drawAnalysis()
        cla(axA, 'reset'); hold(axA, 'on'); grid(axA, 'on'); box(axA, 'on');
        axA.FontSize = 10.5; try, axA.Toolbar.Visible = 'off'; catch, end   % 'reset': no log scale left over
        switch tut
            case 1
                if isempty(fitRes)
                    title(axA, 'Free-swing identification (record on the rig)');
                    text(axA, 0.05, 0.5, {'Motor off (SAFE). Zero while hanging still,', ...
                        'displace 20-40 deg, Record, release.', 'Fits wg2 and Q with the nonlinear model.'}, ...
                        'Units', 'normalized', 'FontSize', 11);
                    axis(axA, 'off');
                else
                    axis(axA, 'on');
                    plot(axA, fitRes.t, fitRes.yDeg, '.', 'Color', [0.2 0.2 0.2]);
                    plot(axA, fitRes.t, fitRes.yFitDeg, 'Color', C.pend, 'LineWidth', 1.5);
                    title(axA, sprintf('Free swing: wg2 = %.2f, Q = %.1f', fitRes.wg2, fitRes.Q));
                end
            case {2, 4}
                axis(axA, 'on');
                w = logspace(-1, 2, 400); s = 1j * w;
                Lj = polyval(lp.L.num, s) ./ polyval(lp.L.den, s);
                if tut == 2
                    semilogx(axA, w, 20*log10(abs(1 ./ (1 + Lj))), 'Color', C.blue, 'LineWidth', 1.6);
                    semilogx(axA, w, 20*log10(abs(Lj ./ (1 + Lj))), 'Color', C.green, 'LineWidth', 1.6);
                    semilogx(axA, w, 20*log10(abs(1 ./ (1 + Lj) ./ s.^2)), 'Color', C.pend, 'LineWidth', 1.2);
                    legend(axA, {'|S|', '|T|', '|S_D|'}, 'Location', 'southwest');
                    xlabel(axA, '\omega (rad/s)'); ylabel(axA, 'dB'); title(axA, 'Sensitivity functions (linear)');
                    set(axA, 'XScale', 'log');
                else
                    plot(axA, real(Lj), imag(Lj), 'Color', C.blue, 'LineWidth', 1.6);
                    plot(axA, real(Lj), -imag(Lj), ':', 'Color', C.blue);
                    th = linspace(0, 2*pi, 100); r0 = 1 / 10^(lp.margins.MsdB / 20);
                    plot(axA, -1 + r0*cos(th), r0*sin(th), '--', 'Color', C.pend);
                    plot(axA, -1, 0, 'r+', 'MarkerSize', 12, 'LineWidth', 2);
                    xlim(axA, [-3 1]); ylim(axA, [-2 2]); axis(axA, 'equal');
                    title(axA, sprintf('Nyquist of L: M_S = %.2f dB', lp.margins.MsdB));
                end
            case 3
                axis(axA, 'on'); m = odyssix.sim.metrics(S, cfg);
                v = [m.ce_total, NaN]; if ~isempty(H), mh = odyssix.sim.metrics(H, hwRun.cfg); v(2) = mh.ce_total; end
                b = bar(axA, categorical({'simulation', 'rig'}), v, 'FaceColor', 'flat');
                b.CData = [C.sim; C.blue];
                title(axA, 'Control effort CE_{total} = \int|u|dt'); ylabel(axA, 'deg/s');
            case 5
                axis(axA, 'on');
                plot(axA, real(lp.olPend), imag(lp.olPend), 'x', 'Color', [0.6 0.6 0.6], 'MarkerSize', 10, 'LineWidth', 2);
                plot(axA, real(lp.cl), imag(lp.cl), 'x', 'Color', C.blue, 'MarkerSize', 11, 'LineWidth', 2.2);
                z = lp.zeros(real(lp.zeros) > 0);
                plot(axA, real(z), imag(z), 'o', 'Color', C.pend, 'MarkerSize', 10, 'LineWidth', 2);
                xline(axA, 0, 'k'); Lm = min(40, 1.2 * max(abs([lp.cl; lp.olPend; 1])));
                xlim(axA, [-Lm 0.7*Lm]); ylim(axA, [-Lm Lm]);
                title(axA, 'Poles x (grey: pendulum alone)   RHP zero o');
            case {6, 8}
                % Tutorial 8: root locus of the closed loop as the rotor PID gains
                % are scaled together by k (k = 1: your design)
                axis(axA, 'on');
                n = lp.L.num; d = lp.L.den; n = [zeros(1, numel(d) - numel(n)), n];
                ks = logspace(-1.5, 1, 160); P = zeros(numel(d) - 1, numel(ks));
                for i = 1:numel(ks), P(:, i) = roots(d + ks(i) * n); end
                plot(axA, real(P(:)), imag(P(:)), '.', 'Color', [0.7 0.75 0.85], 'MarkerSize', 4);
                plot(axA, real(lp.cl), imag(lp.cl), 'x', 'Color', C.blue, 'MarkerSize', 11, 'LineWidth', 2.2);
                plot(axA, real(lp.olPend), imag(lp.olPend), 'x', 'Color', [0.5 0.5 0.5], 'MarkerSize', 9, 'LineWidth', 1.5);
                xline(axA, 0, 'k'); Lm = min(40, 1.3 * max(abs([lp.cl; 1])));
                xlim(axA, [-Lm 0.5 * Lm]); ylim(axA, [-Lm Lm]);
                title(axA, sprintf('Root locus, rotor PID x k (x: k = 1)  %s', ternary(lp.stable, 'stable', 'UNSTABLE')));
            case 7
                axis(axA, 'on');
                r = odyssix.sim.impulseAverage(S.t, pendView(S.psi), S.rotor, S.phase);
                if r.n > 0, plot(axA, r.t, r.alpha - mean(r.alpha(r.t < 0)), 'Color', C.sim, 'LineWidth', 1.6); end
                if ~isempty(H)
                    q = odyssix.sim.impulseAverage(H.t, pendView(H.psi), H.rotor, H.phase);
                    if q.n > 0, plot(axA, q.t, q.alpha - mean(q.alpha(q.t < 0)), 'Color', C.pend, 'LineWidth', 1.8); end
                end
                xlabel(axA, 't after impulse (s)'); ylabel(axA, '\alpha (deg)');
                title(axA, sprintf('Average of %d impulse responses (grey sim, red rig)', r.n));
            case {9, 10, 23}
                axis(axA, 'on');
                plot(axA, real(lp.olPend), imag(lp.olPend), 'x', 'Color', [0.6 0.6 0.6], 'MarkerSize', 10, 'LineWidth', 2);
                plot(axA, real(lp.cl), imag(lp.cl), 'x', 'Color', C.blue, 'MarkerSize', 11, 'LineWidth', 2.2);
                xline(axA, 0, 'k'); Lm = max(2, 1.3 * max(abs([lp.cl; lp.olPend])));
                xlim(axA, [-Lm 0.5 * Lm]); ylim(axA, [-Lm Lm] * 0.8);
                title(axA, sprintf('Closed-loop poles of A - BK (grey: open loop)  %s', ternary(lp.stable, 'stable', 'UNSTABLE')));
            case 21
                axis(axA, 'on');
                plot(axA, S.t, abs(S.psi), 'Color', C.sim, 'LineWidth', 1.4);
                if ~isempty(H), plot(axA, H.t, abs(H.psi), 'Color', C.pend, 'LineWidth', 1.6); end
                yline(axA, 1, '--', 'Color', C.green);
                xlabel(axA, 't (s)'); ylabel(axA, '|\psi| (deg)');
                title(axA, 'Swing amplitude; stopped = inside 1 deg (dashed)');
            case 22
                axis(axA, 'on');
                e = S.ref - S.rotor;
                plot(axA, e, S.u, '.', 'Color', C.sim, 'MarkerSize', 4);
                if ~isempty(H), plot(axA, H.ref - H.rotor, H.u, '.', 'Color', C.blue, 'MarkerSize', 5); end
                xlabel(axA, 'error r - \theta (deg)'); ylabel(axA, 'u (deg/s^2)');
                title(axA, 'On-off: u switches on the sign of the error');
        end
    end

    function fillTable()
        ms = odyssix.sim.metrics(S, cfg);
        mh = struct(); if ~isempty(H), mh = odyssix.sim.metrics(H, hwRun.cfg); end
        rows = TT().metrics; d = cell(0, 4);
        if isfield(cfg, 'target') && isfinite(cfg.target_t)
            rows = [rows; {'hold_reach_s', sprintf('Time to reach %.1f deg (+/-%.1f)', cfg.target, ternary(isInv(), 1.5, 0.5)), ''; ...
                           'hold_error_deg', 'Hold error, last 3 s (deg)', '0'}];
        end
        for i = 1:size(rows, 1)
            d(end+1, :) = {rows{i, 2}, fmt(getf(ms, rows{i, 1})), fmt(getf(mh, rows{i, 1})), rows{i, 3}}; %#ok<AGROW>
        end
        if hasMargins()
            d(end+1, :) = {'Phase margin (linear, deg)', fmt(lp.margins.phiMdeg), '', TT().pm};
            d(end+1, :) = {'Gain margin(s) (linear, dB)', gmText(lp.L), '', TT().gm};
            d(end+1, :) = {'Peak sensitivity M_S (linear, dB)', fmt(lp.margins.MsdB), '', TT().ms};
        end
        % (no "pendulum loop margin" for T7: that loop is open-loop unstable, so a
        % crossover margin is not a stability verdict; the closed-loop poles are)
        if ~isempty(lp) && tut >= 6
            d(end+1, :) = {'Slowest closed-loop pole (1/s)', fmt(-max(real(lp.cl))), '', ''};
        end
        ui.table.Data = d;
    end

    function verdict()
        st = S.Properties.UserData.state; why = S.Properties.UserData.abort;
        if ~isempty(lp) && ~lp.stable
            txt = 'UNSTABLE (linear model)'; col = C.red;
        elseif strcmp(st, 'ABORTED')
            txt = ['SIM ABORTED: ' why]; col = C.amber;
        elseif hasMargins() && lp.margins.MsdB > 8
            txt = 'Stable, but fragile (M_S > 8 dB)'; col = C.amber;
        else
            txt = TT().ok; col = C.green;
        end
        ui.badge.Text = txt; ui.badge.BackgroundColor = col;
    end

    % =================================================================== rig
    function onDetect()
        B = odyssix.stm32.listBoards(); ui.probe.Text = B.text;
        if ~isempty(B.ports), refreshPorts(B.ports{1}); end
    end

    function onFlash()
        if link.isOpen(), uialert(fig, 'Disconnect first: flashing resets the board.', 'Flash'); return; end
        d = uiprogressdlg(fig, 'Title', 'Flashing', 'Indeterminate', 'on', ...
            'Message', 'Checking the image, identifying the MCU, writing and verifying...');
        R = odyssix.stm32.flash(); close(d);
        if R.ok, uialert(fig, R.message, 'Flashed', 'Icon', 'success'); onDetect();
        else, uialert(fig, sprintf('%s\n\nLog: %s', R.message, R.logFile), 'Flash failed', 'Icon', 'error'); end
    end

    function refreshPorts(prefer)
        B = odyssix.stm32.listBoards(); p = B.ports;
        if ~isempty(emu.port), p = [{emu.port}, p]; end
        if isempty(p), p = {'(no ports)'}; end
        ui.port.Items = p;
        if nargin && any(strcmp(p, prefer)), ui.port.Value = prefer; end
    end

    function onConnect()
        if link.isOpen(), link.close(); ui.connect.Text = 'Connect'; setEnabled(); return; end
        connectTo(ui.port.Value);
    end

    function connectTo(port)
        if strcmp(port, '(no ports)'), say('No serial port: plug in the Nucleo, Detect board.'); return; end
        try
            link.open(port, T.baud); link.stream(true); ui.connect.Text = 'Disconnect'; armOk = false;
            say(sprintf('Open %s. Waiting for data...', port));
        catch err
            say(['Connect failed: ' err.message]);
        end
        setEnabled();
    end

    function onEmulator()
        if ~isempty(emu.pid), connectTo(emu.port); return; end
        try, exe = odyssix.stm32.emulatorBinary(); catch err, uialert(fig, err.message, 'Emulator'); return; end
        f = [tempname '.pty'];
        system(sprintf('"%s" --pty --parent %d > "%s" 2>&1 & echo $! > "%s.pid"', exe, feature('getpid'), f, f));
        for i = 1:50, if isfile(f) && ~isempty(strtrim(fileread(f))), break; end, pause(0.1); end
        emu.port = strtrim(fileread(f)); emu.pid = strtrim(fileread([f '.pid']));
        refreshPorts(emu.port); connectTo(emu.port);
    end

    function send(c)
        if link.isOpen(), try, link.key(c); catch err, say(['send failed: ' err.message]); end, end
    end
    function doAbort(), hwRun.on = false; if link.isOpen(), link.abort(); end, end
    function onKey(e), if any(strcmp(e.Key, {'escape', 'space'})), doAbort(); end, end

    function onArm()
        if ~armOk
            msg = ['ARM energises the stepper (it holds, it does not move yet).' newline ...
                   '  - 12 V within reach; swing path clear of hands and cables' newline ...
                   '  - ABORT here, Esc or Space; pulling 12 V always works'];
            if isInv(), msg = [msg newline '  - Upright experiment: TWO people; one holds the pendulum, one on ABORT']; end
            sel = uiconfirm(fig, msg, 'Arm the motor', 'Options', {'ARM', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(sel, 'ARM'), return; end
            armOk = true;
        end
        send('a');
    end
    function armNow(), armOk = true; send('a'); end
    function gotoNow(v), ui.target.Value = v; onGoto(); end

    function onRunRig()
        if ~link.isOpen(), say('Connect first.'); return; end
        if ~strcmp(link.state, 'RUNNING'), say('ARM, then START, before running.'); return; end
        if link.protocol < 2, say('This board runs old firmware (protocol 1): Flash firmware.'); return; end
        if tut >= 6 && link.protocol < 3
            say(sprintf('%s needs firmware 2.1.0 (protocol 3); this board has protocol %d: Flash firmware.', TT().short, link.protocol)); return;
        end
        % the pendulum datum must have been zeroed hanging and still: an unzeroed
        % encoder (e.g. 1439 deg after hand-turning) trips the limit at once, and
        % a datum taken off-vertical biases every Tutorial 3-5 run
        link.poll(); D0 = link.table();                         % freshest samples
        if isempty(D0) || height(D0) == 0, say('No data from the board yet: wait a second.'); return; end
        w = D0.psi_deg(max(1, end - 24):end);                     % last 0.5 s: a swing
        psi0 = w(end);                                             % through 0 must not pass
        if isInv()
            % the firmware aborts EXP005 (PENDULUM_LOST) the moment the pendulum is
            % more than 15 deg from upright, even while it waits to capture: so the
            % pendulum must already be held up (datum zeroed hanging => reads 180)
            okDatum = all(abs(abs(w) - 180) < 10);
            if ~okDatum
                say(sprintf(['%s: pendulum reads %.1f deg from hanging; it must be held UPRIGHT (180 deg) ' ...
                             'and still BEFORE Run. Zero datums with it hanging, lift it, hold it, then Run.'], TT().short, psi0));
                return;
            end
        elseif tut == 21
            % P21 stops a swing: pluck it first; only the datum must be sane
            if ~all(abs(w) < 60)
                say(sprintf('P21: pendulum reads %.1f deg: zero datums hanging, pluck 10-30 deg, then Run.', psi0)); return;
            end
        elseif ~all(abs(w) < 10)
            say(sprintf(['Pendulum reads %.1f deg (or is swinging). Let it hang still, press Zero datums, ' ...
                         'then run.'], psi0));
            return;
        end
        readControls();
        H = []; clearRig();
        if tut == 1
            link.sendLine(sprintf('move=%.4f', cfg.step));             % out now, back after 3.5 s
            hwRun = struct('on', true, 'i0', link.n + 1, 'cfg', cfg, 'seq', 1, 't0', tic);
        else
            % send, then insist the board echoes EXACTLY these values before GO:
            % a lost byte on the serial link must never change a gain silently
            ok = false;
            for attempt = 1:2
                try, link.configure(cfg); catch, end     % the echo below is the check
                t0 = tic;
                while toc(t0) < 1.5
                    ok = cfgMatches(link.cfg, cfg);
                    if ok, break; end
                    pause(0.05); link.poll();
                end
                if ok, break; end
            end
            if ~isempty(link.lastError), say(['Rejected: ' link.lastError]); return; end
            if ~ok, say('The board did not confirm the configuration (serial link?). Not starting.'); return; end
            i0 = link.n + 1;
            try, link.go(); catch, end                    % the board's GO/RUN events confirm it
            % mark the run active only now: a timer tick during the pause above
            % must not see it (it would read the previous run's FINISHED event)
            c = cfg; c.target = NaN; c.target_t = NaN;
            hwRun = struct('on', true, 'i0', i0, 'cfg', c, 'seq', 0, 't0', tic);
        end
        say(sprintf('Running %s on the %s.', TT().short, ternary(link.emulator, 'EMULATOR', 'rig')));
    end

    function onStopRun()
        if link.isOpen() && link.protocol >= 2, link.stopRun(); end
    end

    function onGoto()
        % live set-point: P21 while regulating, T6/T7/T8/P23 once balancing in HOLD
        if ~hwRun.on, say('Start a run first.'); return; end
        v = ui.target.Value;
        try, link.setRef(v); catch err, say(err.message); return; end
        t0 = tic; while toc(t0) < 1 && isnan(link.lastRef) && isempty(link.lastError), pause(0.05); link.poll(); end
        if ~isempty(link.lastError), say(['Rejected: ' link.lastError]); return; end
        if isnan(link.lastRef)
            say(['No REF reply: the set-point is accepted only while P21 regulates or once the pendulum ' ...
                 'balances in HOLD (after the sequence).']); return;
        end
        D = link.table(); i0 = min(hwRun.i0, height(D));
        hwRun.cfg.target = v; hwRun.cfg.target_t = D.t_s(end) - D.t_s(i0);
        say(sprintf('Arm going to %.1f deg (REF %.3f).', v, link.lastRef));
    end

    function onLive()
        % send only what changed; the firmware echoes a C line and applies it
        % (gains, filters, rate, limits: not exp, sequence or step)
        if ~hwRun.on || tut < 6, return; end
        readControls(); c0 = hwRun.cfg;
        keys = setdiff([link.KEYS2, link.KEYS3], {'step', 'dist', 'imp', 'rrate'}, 'stable');
        n = 0;
        for i = 1:numel(keys)
            f = keys{i};
            if isfield(cfg, f) && abs(cfg.(f) - c0.(f)) > 1e-9
                link.setLive(f, cfg.(f)); hwRun.cfg.(f) = cfg.(f); n = n + 1;
            end
        end
        t0 = tic; while toc(t0) < 1 && ~cfgMatches(link.cfg, hwRun.cfg), pause(0.05); link.poll(); end
        if ~isempty(link.lastError), say(['Rejected: ' link.lastError]);
        else, say(sprintf('%d gain(s) changed live.', n)); end
    end

    function onLqr()
        q = str2num(ui.lqrQ.Value); r = ui.lqrR.Value; %#ok<ST2NM>
        if tut == 10
            A = [0 1; 0 -ui.bv.Value]; B = [0; 1];
        else
            readControls(); [A, B] = odyssix.ctrl.pendulumModel('inverted', pl);
        end
        if numel(q) ~= size(A, 1), say(sprintf('Q needs %d weights.', size(A, 1))); return; end
        try
            K = odyssix.ctrl.lqr(A, B, diag(q), r);
        catch err
            say(err.message); return;
        end
        names = {'k1', 'k2', 'k3', 'k4'};
        for i = 1:numel(K), setSlider(ui.(names{i}), K(i)); end
        update();
        say(sprintf('LQR: K = [%s], closed-loop poles %s', num2str(K, '%.4g '), mat2str(round(eig(A - B * K).', 3))));
    end

    function clearRig()
        set([tr.thH tr.pH tr.uH], 'XData', nan, 'YData', nan);
    end

    % =================================================================== tick
    function onTick()
        % never let one bad tick stop the timer: a stopped timer means no
        % reading, no keep-alive (the board's watchdog aborts) and a frozen UI
        try
            tickBody();
        catch err
            say(['internal: ' err.message]);
            fprintf(2, 'enr312_lab tick error:\n%s\n', getReport(err, 'extended', 'hyperlinks', 'off'));
            hwRun.on = false;
        end
    end

    function tickBody()
        if ~isvalid(fig), return; end
        if link.isOpen()
            try
                link.poll();
                % MATLAB's serial write can throw although the byte went out
                % (seen on the emulator pty). Only 5 failures in a row (0.5 s)
                % mean a lost link; the firmware's 1 s watchdog stops the rig.
                try, link.keepAlive(); wrFail = 0;
                catch werr, wrFail = wrFail + 1; if wrFail >= 5, rethrow(werr); end
                end
            catch err
                say(['Link lost: ' err.message]); fprintf(2, 'enr312_lab: link lost: %s\n', getReport(err, 'basic')); link.close(); ui.connect.Text = 'Connect';
            end
            if link.n ~= lastN, lastN = link.n; dataT = tic;
            elseif toc(dataT) > 2
                ui.state.Text = 'NO DATA FROM BOARD'; ui.state.BackgroundColor = C.grey;
                say('No data from the board for 2 s: the display is stale. ABORT, Disconnect, Connect; if still silent, replug USB.');
                return;
            end
        end
        setEnabled();
        if ~link.isOpen() || link.n == 0, return; end
        D = link.table(); k = height(D);
        if hwRun.on, rigProgress(D); end
        if recording.on && D.t_s(end) >= recording.tEnd, finishRecord(D); end
        if ~hwRun.on && ~recording.on
            odyssix.ui.rigPose(rig, D.rotor_deg(k), 180 - D.psi_deg(k), D.ref_deg(k), ui.L.Value / 0.258);
            ui.readout.Text = sprintf('%s   arm %+7.2f deg    pendulum %+8.2f deg', ...
                ternary(link.emulator, 'EMULATOR', 'RIG'), D.rotor_deg(k), D.psi_deg(k));
        end
        if link.n > 50 * 900, link.clearData(); hwRun.i0 = 1; end
    end

    function rigProgress(D)
        i0 = min(hwRun.i0, height(D)); d = D(i0:end, :);
        if isempty(d), return; end
        t = d.t_s - d.t_s(1);
        if tut == 1
            if hwRun.seq == 1 && toc(hwRun.t0) > 3.5
                link.sendLine(sprintf('move=%.4f', -hwRun.cfg.step)); hwRun.seq = 2; hwRun.t0 = tic;
            elseif hwRun.seq == 2 && toc(hwRun.t0) > 3.5
                hwRun.on = false;
            end
            tMove = abs(hwRun.cfg.step) * (3200 / 360) / 200;     % 200 microsteps/s
            ph = zeros(height(d), 1); ph(t >= tMove + 0.1 & t < 3.4) = 2;
        else
            ph = d.phase;
            ev = link.runEvent;
            if contains(ev, 'FINISHED') || contains(ev, 'ABORTED') || ~strcmp(link.state, 'RUNNING')
                hwRun.on = false;
                if contains(ev, 'ABORTED'), say(['Rig run ', ev]); end
            end
        end
        H = table(t, d.rotor_deg, d.psi_deg, d.u, d.ref_deg, ph, 'VariableNames', {'t', 'rotor', 'psi', 'u', 'ref', 'phase'});
        set(tr.thH, 'XData', t, 'YData', H.rotor); set(tr.pH, 'XData', t, 'YData', pendView(H.psi));
        set(tr.uH, 'XData', t, 'YData', H.u);
        odyssix.ui.rigPose(rig, H.rotor(end), 180 - H.psi(end), H.ref(end), ui.L.Value / 0.258);
        ui.readout.Text = sprintf('%s  t %5.1f s   arm %+7.2f deg   pendulum %+7.2f deg   %s', ...
            ternary(link.emulator, 'EMULATOR', 'RIG'), t(end), H.rotor(end), pendView(H.psi(end)), ...
            ternary(tut >= 2, phaseName(H.phase(end)), ''));
        if isInv() && hwRun.on, t5Cue(H); end
        xl = [0, max(S.t(end), t(end))]; for ax = [axT axP axU], xlim(ax, xl); end
        autoY();
        if ~hwRun.on, fillTable(); if any(tut == [3 7 21 22]), drawAnalysis(); end, end
    end

    function t5Cue(H)
        % firmware 2.0.8: after capture the motor stays still (u = 0) until the
        % pendulum moves 1.5 deg on its own, i.e. until the hand has let go
        % (the same for T6/T7/T8/P23: phase 0 capture, 1 wait for release)
        p = H.phase(end); waiting = p == 1 && all(H.u(max(1, end - 4):end) == 0);
        bal = (tut == 5 && p <= 4) || (tut ~= 5 && p >= 2 && p <= 8);
        if ~isfield(hwRun, 'cue'), hwRun.cue = ''; end
        if p == 0,      cue = 'HOLD IT UPRIGHT AND STILL (captured after 1 s within 2 deg)'; col = C.amber;
        elseif waiting, cue = 'LET GO NOW  -  the arm waits, motor still, until you release'; col = C.red;
        elseif bal && p == 8, cue = 'HOLD: balancing; Go to angle / Apply gains live; Stop run or ABORT to end'; col = C.green;
        elseif bal,     cue = 'BALANCING  -  hands off; Stop run or ABORT to end'; col = C.green;
        else,           return;
        end
        if ~strcmp(cue, hwRun.cue)
            if waiting, beep; end
            hwRun.cue = cue; ui.badge.Text = cue; ui.badge.BackgroundColor = col;
        end
    end

    function setEnabled()
        on = link.isOpen(); st = link.state; if ~on, st = 'NOT CONNECTED'; end
        cols = struct('SAFE', C.green, 'ARMED', C.amber, 'RUNNING', C.red, 'FAULT', C.red);
        if isfield(cols, st), col = cols.(st); else, col = C.grey; end
        lbl = st;
        if strcmp(st, 'SAFE'), lbl = 'SAFE: motor off'; end
        if strcmp(st, 'ARMED'), lbl = 'ARMED: motor holding'; end
        if strcmp(st, 'RUNNING'), lbl = ternary(hwRun.on, 'RUNNING: experiment active', 'RUNNING: motion permitted'); end
        if strcmp(st, 'FAULT'), lbl = sprintf('FAULT 0x%02X', link.faults); end
        ui.state.Text = lbl; ui.state.BackgroundColor = col;
        en = @(h, c) set(h, 'Enable', matlab.lang.OnOffSwitchState(c));
        en(ui.flash, ~on); en(ui.emu, ~on && isunix); en(ui.abort, on); en(ui.zero, on);
        en(ui.clear, on && strcmp(st, 'FAULT')); en(ui.arm, on && strcmp(st, 'SAFE'));
        en(ui.start, on && strcmp(st, 'ARMED'));
        en(ui.run, on && strcmp(st, 'RUNNING') && ~hwRun.on); en(ui.stopRun, on && hwRun.on);
        en(ui.hold, on && link.emulator && isInv()); en(ui.pluck, on && link.emulator);
        en(ui.goto, on && hwRun.on && any(tut == [21 6 7 8 23])); en(ui.live, on && hwRun.on && tut >= 6);
        en(ui.record, on && any(strcmp(st, {'SAFE', 'FAULT'})) && ~recording.on);
        en(ui.useFit, ~isempty(fitRes)); en(ui.save, ~isempty(H) && ~hwRun.on);
    end

    % =================================================================== free swing
    function onRecord()
        D = link.table(); if isempty(D), return; end
        recording = struct('on', true, 'i0', height(D) + 1, 'tEnd', D.t_s(end) + 15);
        say('Recording 15 s: release the pendulum now.');
    end

    function finishRecord(D)
        recording.on = false; d = D(min(recording.i0, height(D)):end, :);
        if height(d) < 100 || max(d.psi_deg) - min(d.psi_deg) < 4
            say('Not enough swing recorded (need > 4 deg). Try again.'); return;
        end
        say('Fitting the nonlinear pendulum model...'); drawnow;
        fitRes = pendulum_free_swing_fit(d.t_s, d.psi_deg);
        % PEND A4: what a stopwatch and a ruler would give
        try
            fs = odyssix.pend.freeSwing(d.t_s, d.psi_deg, 10);
            fitRes.pend = fs;
            a4 = sprintf(' PEND A4: T = %.3f s over %d swings, L = g(T/2pi)^2 = %.3f m (ruler should read ~%.3f m), zeta = %.4f.', ...
                fs.T, fs.nOsc, fs.Lsimple, fs.LrodPredicted, fs.zeta);
        catch
            a4 = '';
        end
        say(sprintf('%s free swing: wg2 = %.2f 1/s^2 (Tutorial 57.01), Q = %.1f (27).%s', ...
            ternary(link.emulator, 'SYNTHETIC', 'MEASURED'), fitRes.wg2, fitRes.Q, a4));
        if tut == 1, drawAnalysis(); end
    end

    function onUseFit()
        if isempty(fitRes), return; end
        setSlider(ui.L, min(0.40, max(0.15, 9.81 / (fitRes.wg2 * 0.6805))));
        setSlider(ui.Q, min(60, max(3, fitRes.Q)));
        update();
        say('Simulation now uses the measured wg2 and Q (suspended swing; upright friction may differ).');
    end

    function onSave()
        if isempty(H), return; end
        [~, rev] = system(sprintf('git -C "%s" rev-parse --short HEAD', T.repo)); rev = strtrim(rev);
        now_ = datetime('now', 'TimeZone', 'UTC');
        stem = sprintf('EXP%03d_%s_%s', tut, char(now_, 'yyyyMMdd_HHmmss'), rev);
        if link.emulator
            dDir = fullfile(T.repo, 'matlab', 'data', 'synthetic'); mDir = dDir;
            stem = [stem '_emulator_synthetic']; cls = 'SYNTHETIC';
        else
            dDir = fullfile(T.repo, 'data', 'raw', sprintf('EXP%03d', tut));
            mDir = fullfile(T.repo, 'data', 'metadata', sprintf('EXP%03d', tut)); cls = 'HARDWARE';
        end
        if ~isfolder(dDir), mkdir(dDir); end
        if ~isfolder(mDir), mkdir(mDir); end
        csv = fullfile(dDir, [stem '.csv']); writetable(H, csv);
        if isunix, system(sprintf('chmod 444 "%s"', csv)); end
        c = hwRun.cfg;
        y = {sprintf('experiment_id: EXP%03d', tut), sprintf('data_class: %s', cls), ...
             sprintf('raw_data_file: %s', strrep(csv, [T.repo filesep], '')), ...
             sprintf('date_utc: %s', char(now_, 'yyyy-MM-dd HH:mm:ss')), 'operator: ""   # FILL IN', ...
             sprintf('firmware_protocol: %d', link.protocol), sprintf('repository_rev: %s', rev), ...
             ['config: {' cfgText(c) '}'], ...
             sprintf('serial_port: %s', link.port), 'sampling: 50 Hz stream of the 500 Hz loop (MCU ticks)', ...
             'units: {t: s, rotor: deg, psi: deg (encoder, 0 = hanging datum), u: deg/s^2, ref: deg}'};
        fid = fopen(fullfile(mDir, [stem '.yaml']), 'w'); fprintf(fid, '%s\n', y{:}); fclose(fid);
        say(sprintf('Saved %s run: %s', cls, csv));
    end

    % =================================================================== small helpers
    function r = nextRow(h), row = row + 1; cg.RowHeight{row} = h; r = row; end
    function section(txt)
        h = uilabel(cg, 'Text', txt, 'FontWeight', 'bold', 'FontSize', 13, 'FontColor', C.navy, 'VerticalAlignment', 'bottom');
        place(h, nextRow(26), [1 2]);
    end
    function h = note(txt, ht)
        h = uilabel(cg, 'Text', txt, 'WordWrap', 'on', 'FontSize', 11, 'FontColor', [0.3 0.32 0.36], 'VerticalAlignment', 'top');
        place(h, nextRow(ht), [1 2]);
    end
    function h = btn(txt, fcn, col, cols, ht)
        if nargin < 5, ht = 28; end
        h = uibutton(cg, 'Text', txt, 'ButtonPushedFcn', fcn, 'FontWeight', 'bold');
        if ~isempty(col), h.BackgroundColor = col; h.FontColor = 'w'; end
        place(h, nextRow(ht), cols);
    end
    function h = check(txt, val)
        h = uicheckbox(cg, 'Text', txt, 'Value', val, 'ValueChangedFcn', @(~, ~) update());
        place(h, nextRow(22), [1 2]);
    end
    function s = slider(txt, lims, val, fmt_)
        l = uilabel(cg, 'Text', txt, 'FontSize', 11.5); place(l, nextRow(18), 1); r1 = row;
        v = uilabel(cg, 'Text', sprintf(fmt_, val), 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontColor', C.blue);
        place(v, row, 2);
        s = uislider(cg, 'Limits', lims, 'Value', val, 'MajorTicks', [], 'MinorTicks', []);
        place(s, nextRow(22), [1 2]);
        s.UserData = struct('label', v, 'fmt', fmt_, 'name', l, 'rows', [r1 row]);
        s.ValueChangingFcn = @(~, e) set(v, 'Text', sprintf(fmt_, e.Value));
        s.ValueChangedFcn = @(~, ~) update();
    end
    function setSlider(s, v)
        v = min(max(v, s.Limits(1)), s.Limits(2)); s.Value = v;
        s.UserData.label.Text = sprintf(s.UserData.fmt, v);
    end
    function setParam(name, v)
        h = ui.(name);
        if isa(h, 'matlab.ui.control.Slider'), setSlider(h, v); else, h.Value = v; end
        update();
    end
    function ax = mkAx(parent, ttl, r, c)
        ax = uiaxes(parent); ax.Layout.Row = r; ax.Layout.Column = c;
        hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); title(ax, ttl); ax.FontSize = 10.5;
        try, ax.Toolbar.Visible = 'off'; catch, end
    end
    function y = pendView(psi)
        if isInv(), y = mod(180 - psi + 180, 360) - 180; else, y = psi; end
    end
    function b = isInv(), b = any(tut == [5 6 7 8 23]); end
    function E = TT(), E = TUT([TUT.exp] == tut); end
    function b = hasMargins(), b = ~isempty(lp) && isfield(lp, 'margins') && ~isempty(lp.margins); end
    function n = phaseName(p)
        names = S.Properties.UserData.phaseNames; n = '';
        if p + 1 <= numel(names) && p >= 0, n = names{p + 1}; end
    end
    function say(txt), if isvalid(ui.link), ui.link.Text = txt; end, end
    function r = getSim(), r = S; end
    function r = getRig(), r = H; end
    function r = getFit(), r = fitRes; end
    function r = getRigCfg(), r = hwRun.cfg; end
    function onClose()
        try, stop(tick); delete(tick); catch, end
        try, link.close(); catch, end
        if ~isempty(emu.pid), system(['kill ' emu.pid ' 2>/dev/null']); end
        delete(fig);
    end
end

% ======================================================================= data
function T = tutorials()
    T(1).name = '1  Digital actuator & angle sensing';
    T(1).presets = {'First motion +5 deg', struct('step', 5); 'Larger move +20 deg', struct('step', 20); ...
                    'Small move +1 deg', struct('step', 1)};
    T(1).caption = ['The stepper is POSITION-commanded: it moves exactly N microsteps of 0.1125 deg. ' ...
        'Watch the hanging pendulum: every start and stop of the constant-speed move kicks it. ' ...
        'On the rig, check the move with a protractor (conflict C-1) and measure the pendulum by free swing.'];
    T(1).ok = 'Open loop: nothing to stabilise';
    T(1).metrics = {'rotor_after_move_deg', 'Arm angle after the move (deg)', '= step, within 0.11';
                    'pend_swing_pp_deg', 'Pendulum swing after the move (p-p, deg)', 'model prediction'};
    T(1).pm = ''; T(1).gm = ''; T(1).ms = '';
    T(1).exp = 1; T(1).short = 'Tutorial 1';
    T(1).note = 'Tutorial 1 has NO controller: Run on rig makes open-loop arm moves. Pick T2-T10 above to set gains.';
    T(1).limit = '<b>Tutorial 1:</b> open loop. The firmware moves at a constant 200 microsteps/s with no ramp, hence the kicks.';

    T(2).name = '2  Sensitivity functions (rotor only)';
    T(2).presets = {'Selected design Kp 5, Kd 2.5', struct('kp', 5, 'kd', 2.5); ...
                    'Faster Kp 6.55, Kd 4 (step 1.5)', struct('kp', 6.55, 'kd', 4, 'step', 1.5); ...
                    'Sluggish Kp 1, Kd 1', struct('kp', 1, 'kd', 1)};
    T(2).caption = ['Pendulum REMOVED or CLAMPED. A reference step measures T(s); a load-disturbance step ' ...
        'measures S_D(s). A PD controller leaves a steady offset D/Kp: it never returns to zero. Try raising Kp.'];
    T(2).ok = 'Stable rotor loop';
    T(2).metrics = {'overshoot_pct', 'Overshoot (%)', '26.76'; 'peak_time_s', 'Peak time (s)', '1.055';
                    'settling_s', 'Settling time (s)', '3.239'; 'dist_offset_deg', 'Disturbance offset (deg)', 'D/Kp';
                    'u_max', 'Peak actuator command (deg/s^2)', '< limit'};
    T(2).pm = ''; T(2).gm = ''; T(2).ms = '';
    T(2).exp = 2; T(2).short = 'Tutorial 2';
    T(2).note = ['Your design: Kp, Kd on the rotor angle (PD, as in the Tutorials). ' ...
                 'No Ki on purpose: the offset D/Kp after the load step is the lesson (Ki arrives in Tutorial 6).'];
    T(2).limit = '<b>Tutorial 2:</b> pendulum removed or clamped; the disturbance D is injected by the firmware at the plant input.';

    T(3).name = '3  MIMO control effort (suspended)';
    T(3).presets = {'Design 1 Kp 6, Kd 4.8', struct('kp', 6, 'kd', 4.8); ...
                    'Design 2 Kp 1.5, Kd 1.725', struct('kp', 1.5, 'kd', 1.725); ...
                    'Design 3 Kp 0.3, Kd 0.75', struct('kp', 0.3, 'kd', 0.75)};
    T(3).caption = ['Pendulum HANGING. The inner PD (10, 5) damps it; you design the rotor PD. Lower gains spend ' ...
        'less control effort and respond slower: Tutorial 3 asks for at least a 2x effort reduction. ' ...
        'Untick quantisation: the effort drops; the chatter is real on the rig.'];
    T(3).ok = 'Stable suspended MIMO loop';
    T(3).metrics = {'overshoot_pct', 'Overshoot (%)', 'D1 32.4'; 'settling_s', 'Settling time (s)', 'D1 2.10';
                    'ce_max', 'CE_max (deg/s^2)', 'filter-dependent'; 'ce_total', 'CE_total (deg/s)', 'D1 10.90 / D2 3.78 / D3 1.65';
                    'pend_peak_deg', 'Pendulum peak (deg)', ''};
    T(3).pm = ''; T(3).gm = ''; T(3).ms = '';
    T(3).exp = 3; T(3).short = 'Tutorial 3';
    T(3).note = 'Kp, Kd rotor = your outer loop. Kp, Kd pendulum = inner loop (from the Tutorial).';
    T(3).limit = '<b>Tutorial 3:</b> CE_total includes quantisation chatter, which the Tutorial&apos;s continuous model does not.';

    T(4) = T(3);
    T(4).name = '4  MIMO sensitivity (suspended)';
    T(4).presets = {'Reference Kp 6, Kd 4.8', struct('kp', 6, 'kd', 4.8); ...
                    'Design A Kp 1.20, Kd 1.50', struct('kp', 1.2, 'kd', 1.5); ...
                    'Design B Kp 0.25, Kd 4.80', struct('kp', 0.25, 'kd', 4.8)};
    T(4).caption = ['Same rig as Tutorial 3, different question: how close does L(jw) come to -1? ' ...
        'M_S = max|S(jw)| = 1 / (closest approach). Design A must reach M_S < 1 dB, Design B < 3 dB. ' ...
        'The pendulum must return to zero after the step.'];
    T(4).ok = 'Stable suspended MIMO loop';
    T(4).metrics = {'overshoot_pct', 'Overshoot (%)', ''; 'settling_s', 'Settling time (s)', '';
                    'pend_end_deg', 'Pendulum at end of step (deg)', '0 (no steady deflection)'};
    T(4).ms = '2.794 (ref)';
    T(4).exp = 4; T(4).short = 'Tutorial 4';
    T(4).limit = '<b>Tutorial 4:</b> margins and Nyquist are continuous-time; the 500 Hz loop and filter reduce them slightly.';

    T(5).name = '5  Inverted pendulum (unstable MIMO)';
    T(5).presets = {'System 1 Kp 9, Kd 9', struct('kp', 9, 'kd', 9); 'System 2 Kp 10, Kd 3.33', struct('kp', 10, 'kd', 3.33); ...
                    'Design A Kp 6.25, Kd 7', struct('kp', 6.25, 'kd', 7); 'Design B Kp 0.5, Kd 10.75', struct('kp', 0.5, 'kd', 10.75)};
    T(5).caption = ['INVERTED, TWO PEOPLE. Zero datums hanging, then HOLD THE PENDULUM UPRIGHT and press Run ' ...
        '(it aborts if more than 15 deg from upright). After 1 s within 2 deg the app says LET GO: release it; ' ...
        'the motor stays still until the pendulum moves on its own, then balancing starts. ' ...
        'The arm first moves the WRONG way (right-half-plane zero). The rig keeps balancing after the ' ...
        'sequence until you press Stop run or ABORT.'];
    T(5).ok = 'BALANCES';
    T(5).metrics = {'undershoot_pct', 'Wrong-way undershoot (%)', 'approx -33'; 'overshoot_pct', 'Overshoot (%)', '';
                    'alpha_peak_deg', 'Peak pendulum angle (deg)', '< 15 (abort)'; 'hunting_deg', 'Residual hunting (deg)', 'quantisation'};
    T(5).pm = '47.3 (Sys 1)'; T(5).gm = '6.01 (Sys 1)'; T(5).ms = '6.37 (Sys 1)';
    T(5).exp = 5; T(5).short = 'Tutorial 5';
    T(5).note = 'Kp, Kd rotor = outer loop (sign-inverted, Tutorial 5). Kp, Kd pendulum = balancing inner loop.';
    T(5).limit = '<b>Tutorial 5:</b> EXP005 aborts beyond 15 deg; pendulum sign alpha = -(psi - 180) (physics audit).';

    upright = ['UPRIGHT, TWO PEOPLE, as Tutorial 5: zero datums hanging, HOLD THE PENDULUM UPRIGHT, Run; ' ...
               'LET GO when told; the motor waits until the pendulum moves on its own. '];
    invMetrics = {'overshoot_pct', 'Overshoot (%)', ''; 'settling_s', 'Settling time, 5 % band (s)', '';
                  'undershoot_pct', 'Wrong-way undershoot (%)', '< 0 (RHP zero)'; 'ss_error_deg', 'Steady-state error (deg)', '';
                  'rotor_wobble_deg', 'Balancing wobble p-p, last 2 s (deg)', 'quantisation'; 'alpha_rms_deg', 'Pendulum rms while balancing (deg)', ''};
    invLimit = ['<b>Upright:</b> aborts beyond 15 deg from upright. Margins are continuous-time; the loop is ' ...
                'conditionally stable, so it has a LOWER gain margin (negative: gain may not drop that much) and an upper one. ' ...
                'The rotor wobbles about +/-1 deg while balancing (encoder 0.15 deg); a linear model has no such wobble, ' ...
                'so settling uses a 5 % band.'];

    T(6) = T(5);
    T(6).exp = 6; T(6).short = 'Tutorial 6';
    T(6).name = '6  PID: integral action (inverted)';
    T(6).presets = {'Tutorial 6 Kp 15, Ti 5 s, Td 0.5 s', struct();
                    'No integral (Ki 0)', struct('ki', 0);
                    'Ti 2 s (Ki 7.5)', struct('ki', 7.5);
                    'Lower Kp 10, Ti 5 (Ki 2)', struct('kp', 10, 'ki', 2)};
    T(6).caption = [upright 'Rotor PID (Ki = Kp/Ti, Kd = Kp Td) with the Tutorial 5 inner loop: step 40 deg ' ...
        'and back, then HOLD. Integral action removes the steady error; too much Ki costs phase margin.'];
    T(6).note = ['Kp, Ki, Kd rotor = PID outer loop (Tutorial 6: Kp 15, Ti 5 s -> Ki 3; Td 0.5 s -> Kd 7.5). ' ...
                 'The tutorial text writes Ki = 5: that is Ti; Ki = Kp/Ti = 3.'];
    T(6).ok = 'BALANCES (PID)';
    T(6).metrics = invMetrics; T(6).metrics{1, 3} = '52.6 (Tut. 6, linear)'; T(6).metrics{2, 3} = '3.1 (Tut. 6, linear, 2 %)';
    T(6).pm = '31.45'; T(6).gm = '7.59 (upper)'; T(6).ms = '';
    T(6).limit = invLimit;

    T(7) = T(6);
    T(7).exp = 7; T(7).short = 'Tutorial 7';
    T(7).name = '7  Pendulum loop design, impulses (inverted)';
    T(7).presets = {'Pendulum PD 300 / 30', struct(); 'Stiffer 600 / 50', struct('kpp', 600, 'kdp', 50);
                    'Softer 200 / 20', struct('kpp', 200, 'kdp', 20); 'Too soft 150 / 15', struct('kpp', 150, 'kdp', 15)};
    T(7).caption = [upright 'Rotor PID fixed (15, 0, 7.5); you design the pendulum PD (Kp 150-600, Kd 15-50). ' ...
        'Eight 10 deg pendulum-reference impulses, 5 s apart; their responses are averaged (Tutorial 7, signal averaging).'];
    T(7).note = 'Kp, Kd rotor fixed by Tutorial 7 (15, 7.5, D filter 50 Hz). Design Kp, Kd pendulum.';
    T(7).ok = 'BALANCES';
    T(7).metrics = {'n_impulses', 'Impulses applied', '8'; 'pend_peak_deg', 'Pendulum peak, averaged (deg)', '';
                    'pend_settling_s', 'Pendulum settling (s)', ''; 'rotor_peak_deg', 'Rotor peak, averaged (deg)', '';
                    'rotor_settling_s', 'Rotor settling (s)', ''; 'alpha_rms_deg', 'Pendulum rms (deg)', ''};
    T(7).pm = ''; T(7).gm = ''; T(7).ms = '';

    T(8) = T(6);
    T(8).exp = 8; T(8).short = 'Tutorial 8';
    T(8).name = '8  Root locus, load disturbance (inverted)';
    T(8).presets = {'Tutorial 8 Kp 15, Ti 2 s, Td 0.5 s', struct(); 'No integral (Ki 0)', struct('ki', 0);
                    'Disturbance 90 deg/s^2', struct('dist', 90); 'Kp 25, Ti 2', struct('kp', 25, 'ki', 12.5, 'kd', 12.5)};
    T(8).caption = [upright 'Step 40 deg and back, then a load disturbance D at the plant input for 10 s and off. ' ...
        'The root locus shows where the closed-loop poles go as the rotor gains scale. Without Ki the arm sits off by D/Kp.'];
    T(8).note = 'Kp, Ki, Kd rotor = PID (Tutorial 8: Kp 15, Ti 2 s -> Ki 7.5, Td 0.5 s). D = load disturbance.';
    T(8).metrics = [invMetrics(1:4, :); {'ld_peak_deg', 'Load-disturbance peak (deg)', ''; ...
                    'ld_final_deg', 'Offset under the disturbance (deg)', '0 with Ki'; 'ld_settling_s', 'Disturbance recovery (s)', ''}];
    T(8).pm = ''; T(8).gm = ''; T(8).ms = '';

    sfLimit = ['<b>State feedback:</b> u = -(k1 (theta - r) + k2 thetadot) - b thetadot, thetadot = the commanded stepper rate ' ...
               '(exact while no steps are missed). b emulates the Tutorial 9/10 rotor plant 1/(s^2 + b s).'];
    sfMetrics = {'overshoot_pct', 'Overshoot (%)', ''; 'settling_s', 'Settling time (s)', '';
                 'final_value_deg', 'Final value (deg)', '= step'; 'pend_peak_deg', 'Pendulum peak (deg)', ''};
    T(9) = T(3);
    T(9).exp = 9; T(9).short = 'Tutorial 9';
    T(9).name = '9  Full-state feedback, pole placement (rotor)';
    T(9).presets = {'Reference wN 1, zeta 1: K = [1 2]', struct();
                    'wN 2, zeta 0.2: K = [4 0.8]', struct('k1', 4, 'k2', 0.8);
                    '16 % OS, 4 s: K = [3.94 2]', struct('k1', 3.94, 'k2', 2)};
    T(9).caption = ['Pendulum HANGING (pendulum gains 0). Place the poles of s^2 + k2 s + k1: k1 = wN^2, k2 = 2 zeta wN. ' ...
        'Step 20 deg and back. The poles plot shows A - BK.'];
    T(9).note = 'k1 = wN^2, k2 = 2 zeta wN (Tutorial 9). b = virtual rotor damping (0 = double integrator).';
    T(9).ok = 'Stable state feedback'; T(9).metrics = sfMetrics; T(9).metrics{2, 3} = '5.8 (reference)';
    T(9).limit = sfLimit;

    T(10) = T(9);
    T(10).exp = 10; T(10).short = 'Tutorial 10';
    T(10).name = '10  LQR (rotor)';
    T(10).presets = {'Q = I, R = 1, b = 0: K = [1 1.7321]', struct();
                     'Q = I, R = 1, b = 2: K = [1 0.6458]', struct('k2', 0.6458, 'bv', 2);
                     'Q = I, R = 0.1: K = [3.162 4.040]', struct('k1', 3.1623, 'k2', 4.0404)};
    T(10).caption = ['Pendulum HANGING. LQR minimises the integral of x''Qx + u''Ru: type diag(Q) and R and press LQR ' ...
        '(odyssix.ctrl.lqr, no toolbox). Smaller R = more aggressive, more actuator effort.'];
    T(10).note = 'LQR gains from Q, R below (Tutorial 10). b = virtual damping of the rotor plant.';
    T(10).metrics{2, 3} = '';

    T(11) = T(3);
    T(11).exp = 21; T(11).short = 'PEND 21';
    T(11).name = 'P21  PEND: stop a swing (suspended PID)';
    T(11).presets = {'Gain set 1: rotor 6/4.8, pendulum 10/5', struct();
                     'Gain set 2: pendulum Kd 15', struct('kdp', 15);
                     'Gain set 3: rotor only (pendulum 0/0)', struct('kpp', 0, 'kdp', 0)};
    T(11).caption = ['PEND A5. Pendulum HANGING: zero datums, pluck it 10-30 deg, press Run: the controller regulates ' ...
        'the arm at 0 and damps the swing. Time how long it takes to stop, for three gain sets. ' ...
        'It keeps regulating (Go to angle works) until Stop run.'];
    T(11).note = 'Rotor PD + pendulum PD, suspended (as Tutorial 3). The simulation plucks 20 deg.';
    T(11).ok = 'Stable suspended loop';
    T(11).metrics = {'swing_start_deg', 'Swing at start (deg)', ''; 'stop_time_s', 'Time to stop, inside 1 deg (s)', '';
                     'rotor_peak_deg', 'Arm excursion (deg)', ''};
    T(11).limit = '<b>PEND 21:</b> the free pendulum alone (Q ~ 27) takes ~10 s to decay to 1 deg from 20 deg: compare.';

    T(12) = T(9);
    T(12).exp = 22; T(12).short = 'PEND 22';
    T(12).name = 'P22  PEND: On-Off control (suspended)';
    T(12).presets = {'u_on 200, dead band 0.5 deg', struct(); 'No dead band', struct('db', 0); 'Weak u_on 50', struct('uon', 50)};
    T(12).caption = ['PEND Q7, Q14. Pendulum HANGING. Bang-bang: u = +/-u_on on the sign of the error (0 inside the dead band). ' ...
        'Step 20 deg and back. It overshoots and keeps oscillating (limit cycle) and shakes the pendulum: compare with P control.'];
    T(12).note = 'u = u_on sign(r - theta) outside the dead band, 0 inside. No gains to tune: that is the drawback.';
    T(12).ok = 'Runs (on-off has no linear stability)';
    T(12).metrics = {'overshoot_pct', 'Overshoot (%)', ''; 'final_value_deg', 'Final value (deg)', '';
                     'limit_cycle_deg', 'Limit-cycle amplitude (deg)', '> 0'; 'pend_peak_deg', 'Pendulum peak (deg)', ''};
    T(12).limit = '<b>PEND 22:</b> on-off control; no linear model, no margins.';

    T(13) = T(6);
    T(13).exp = 23; T(13).short = 'PEND 23';
    T(13).name = 'P23  PEND: LQR balancing (inverted, 4 states)';
    K1 = lqrInv([1 1 10 1], 0.01); K2 = lqrInv([1 1 10 1], 0.1); K3 = lqrInv([1 1 100 1], 0.01);
    T(13).presets = {'Q = diag(1,1,10,1), R = 0.01', struct();
                     sprintf('R = 0.1: K = [%.3g %.3g %.4g %.3g]', K2), struct('k1', K2(1), 'k2', K2(2), 'k3', K2(3), 'k4', K2(4));
                     sprintf('Q_alpha 100: K = [%.3g %.3g %.4g %.3g]', K3), struct('k1', K3(1), 'k2', K3(2), 'k3', K3(3), 'k4', K3(4))};
    T(13).caption = [upright 'PEND C10. One state-feedback law on [theta, thetadot, alpha, alphadot] replaces both PID loops. ' ...
        'Change Q (what you care about) and R (how much effort costs) and compare with Tutorial 6.'];
    T(13).note = sprintf('LQR on the 4-state upright model (Tutorial 5 plant). Default K = [%.3g %.3g %.4g %.3g].', K1);
    T(13).ok = 'BALANCES (LQR)';
    T(13).metrics = invMetrics; T(13).pm = ''; T(13).gm = ''; T(13).ms = '';
    T(13).limit = [invLimit '<br><b>PEND 23:</b> alphadot is a filtered difference of the encoder (fdp).'];
end

function K = lqrInv(q, r)
    [A, B] = odyssix.ctrl.pendulumModel('inverted', odyssix.sim.plant(5));
    K = odyssix.ctrl.lqr(A, B, diag(q), r);
end



function ok = cfgMatches(c, want)
%CFGMATCHES  Board's '$cfg' echo equals the requested configuration.
    ok = isstruct(c) && isfield(c, 'exp') && c.exp == want.exp;
    f = {'kp', 'kd', 'kpp', 'kdp', 'step', 'dist', 'ulim', 'vmax'};
    if want.exp >= 6, f = [f, odyssix.stm32.RigLink.KEYS3]; end
    for i = 1:numel(f)
        if ~ok, return; end
        ok = isfield(c, f{i}) && abs(c.(f{i}) - want.(f{i})) <= 1e-3 * max(1, abs(want.(f{i})));
    end
end

function v = maxUlim(k)
    switch k, case 2, v = 1600; case {3, 4}, v = 1500; otherwise, v = 1500; end
end
function s = cfgText(c)
    f = [{'exp'}, odyssix.stm32.RigLink.KEYS2, odyssix.stm32.RigLink.KEYS3, {'target', 'target_t'}];
    p = {};
    for i = 1:numel(f)
        if isfield(c, f{i}) && ~(any(strcmp(f{i}, {'target', 'target_t'})) && ~isfinite(c.(f{i})))
            p{end+1} = sprintf('%s: %g', f{i}, c.(f{i})); %#ok<AGROW>
        end
    end
    s = strjoin(p, ', ');
end
function s = gmText(L)
%GMTEXT  Gain margins at EVERY -180 deg crossing: a conditionally stable loop
%   (Tutorials 5-8) has a lower one (gain may not drop by more) and an upper one.
    w = logspace(-2, 3, 20000); Lj = polyval(L.num, 1j * w) ./ polyval(L.den, 1j * w);
    ph = unwrap(angle(Lj)) * 180 / pi;
    k = find(diff(floor((ph + 180) / 360)) ~= 0);
    if isempty(k), s = 'Inf'; return; end
    s = strjoin(arrayfun(@(i) sprintf('%+.2f', -20 * log10(abs(Lj(i)))), k, 'UniformOutput', false), ' / ');
end
function v = getf(s, f), if isfield(s, f), v = double(s.(f)); else, v = NaN; end, end
function s = fmt(v), if isempty(v) || ~isfinite(v), s = '--'; else, s = sprintf('%.3g', v); end, end
function l = pad(l, m)
    if ~all(isfinite(l)), l = [-1 1]; end
    c = mean(l); h = max(diff(l) / 2 * 1.15, m / 2); l = c + [-h h];
end
function s = ternary(c, a, b), if c, s = a; else, s = b; end, end
function place(h, r, c), h.Layout.Row = r; h.Layout.Column = c; end

function s = limitsHtml(extra)
    common = ['<b>Simulated exactly as the firmware runs it:</b> 500 Hz loop (or 500/div), PD/PID with filtered derivatives, ' ...
              'actuator limit, speed ceiling 360 deg/s, encoder 0.15 deg and microstep 0.1125 deg quantisation, ' ...
              'tutorial sequences and aborts (verified identical to the firmware code).<br>' ...
              '<b>Physics:</b> nonlinear rigid pendulum (docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md).<br>' ...
              '<b>NOT simulated:</b> stepper torque limit and missed steps; Coulomb friction; sensor noise; ' ...
              'USB delay; the 2x rotor-scale conflict C-1. <b>Plant values are the Tutorials&apos;</b> until your ' ...
              'free-swing measurement replaces them.'];
    s = ['<b style="font-size:13px">&#9888; What this model does and does not include</b><br>' extra '<br>' common];
end

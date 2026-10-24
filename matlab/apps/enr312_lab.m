function app = enr312_lab()
%ENR312_LAB  ENR312 rotary pendulum: mission control for the rig and its simulation.
%
%   addpath(genpath(fullfile(<repo>, 'matlab'))); enr312_lab
%
%   Missions T1-T10 (the ENR312 tutorials) and LAB (free use: hanging or
%   upright, PID / LQR / state feedback / on-off, step, go to angle, live
%   gains, swing-up, free-swing identification). Every number the PEND
%   handout asks for is produced by one of them (docs/PEND_ANSWER_GUIDE.md).
%
%   SIMULATE   odyssix.sim.* : the firmware's control code, line by line,
%              on a nonlinear pendulum (test_sim_matches_firmware)
%   RIG        the same configuration on the board (or the emulator)
%   RECORD     every rig run is saved automatically (odyssix.data.saveRun):
%              data/raw/EXPnnn/<id>.csv + data/metadata/EXPnnn/<id>.yaml/.json,
%              and listed under RUNS, where any run can be replayed.
%
%   Safety: ARM asks for confirmation; ABORT (button, Esc, Space) is always
%   live; MATLAB feeds the firmware's 1 s watchdog during a run, so a closed
%   or crashed MATLAB stops the rig; closing the window aborts.
%   Base MATLAB only.

    K = palette();
    MIS = missions();
    T = odyssix.stm32.tools();
    link = odyssix.stm32.RigLink();
    emu = struct('pid', '', 'port', '');
    armOk = false; wrFail = 0; lastN = -1; dataT = tic;
    mis = 5;                                     % current mission (index into MIS; 11 = LAB)
    lab = struct('mode', 'hanging', 'ctrl', 'PID');
    measured = [];                                 % the pendulum from FREE SWING, once USE MEASURED is pressed
    cfg = odyssix.sim.defaults(5); pl = odyssix.sim.plant(5);
    S = []; lp = []; H = []; replay = [];
    hwRun = idleRun();
    fitRes = []; recording = struct('on', false, 'i0', 0, 'tEnd', 0);
    lastSaved = ''; savedT = tic; session = struct('step', 0); drawCount = 0; swingPanel = false;
    feedT = tic;                                   % last watchdog feed from inside a simulation
    NEW = {'ki', 'fdr', 'fdp', 'k1', 'k2', 'k3', 'k4', 'bv', 'imp', 'uon', 'db', 'div', 'ma'};
    tr = struct();

    % =================================================================== window
    % as large as 1800 x 1010, but never larger than the screen (a 1366 x 768 laptop gets
    % 1326 x 688; the left panel scrolls, the plots shrink)
    ss = get(groot, 'ScreenSize'); W = min(1800, ss(3) - 40); Hf = min(1010, ss(4) - 80); small = W < 1600;
    fig = uifigure('Name', 'ENR312 · Pendulum', 'Position', [max(1, (ss(3) - W) / 2), max(40, (ss(4) - Hf) / 2), W, Hf], 'Color', K.bg, ...
                   'CloseRequestFcn', @(~, ~) onClose(), 'WindowKeyPressFcn', @(~, e) onKey(e));
    if exist('theme', 'file'), try, theme(fig, 'dark'); catch, end, end
    G = uigridlayout(fig, [3 3], 'RowHeight', {52, '1x', 196}, 'ColumnWidth', {318, '1x', '1.2x'}, ...
        'Padding', [10 8 10 10], 'RowSpacing', 8, 'ColumnSpacing', 10, 'BackgroundColor', K.bg);

    % ---- top bar --------------------------------------------------------------
    top = uigridlayout(G, [1 8], 'ColumnWidth', {250, '1x', 110, 150, 230, 90, 70, 150}, ...
        'Padding', [12 6 6 6], 'ColumnSpacing', 10, 'BackgroundColor', K.panel);
    top.Layout.Row = 1; top.Layout.Column = [1 3];
    lbl(top, 'ENR312 // PENDULUM', 17, K.text, 'bold');
    ui.mission = lbl(top, '', 15, K.cyan, 'bold');
    ui.linkChip = chip(top, 'OFFLINE');
    ui.stateChip = chip(top, '—');
    ui.fw = lbl(top, '', 11, K.dim, 'normal');
    ui.rec = chip(top, '● REC'); ui.rec.Visible = 'off'; ui.rec.BackgroundColor = K.red;
    ui.sessionLbl = lbl(top, '', 11, K.dim, 'normal');
    ui.abort = uibutton(top, 'Text', 'ABORT', 'FontSize', 16, 'FontWeight', 'bold', ...
        'BackgroundColor', K.red, 'FontColor', 'w', 'ButtonPushedFcn', @(~, ~) doAbort(), ...
        'Tooltip', 'Esc or Space');

    % ---- left: missions and controls ------------------------------------------
    L = uigridlayout(G, [140 2], 'ColumnWidth', {'1x', '1x'}, 'RowSpacing', 4, 'ColumnSpacing', 6, ...
        'Padding', [10 10 10 10], 'BackgroundColor', K.panel, 'Scrollable', 'on');
    L.Layout.Row = 2; L.Layout.Column = 1; L.RowHeight = repmat({0}, 1, 140); row = 0;
    head('MISSION');
    mg = uigridlayout(L, [6 2], 'Padding', [0 0 0 0], 'RowSpacing', 4, 'ColumnSpacing', 4, ...
        'RowHeight', repmat({28}, 1, 6), 'BackgroundColor', K.panel);
    place(mg, next(188), [1 2]);
    ui.mb = matlab.ui.control.Button.empty;
    for kk = 1:numel(MIS)
        ui.mb(kk) = uibutton(mg, 'Text', sprintf('%s · %s', MIS(kk).tag, MIS(kk).short), 'FontWeight', 'bold', ...
            'UserData', kk, 'Tooltip', MIS(kk).brief, 'HorizontalAlignment', 'left', ...
            'ButtonPushedFcn', @(s, ~) selectMission(s.UserData));
        ui.mb(kk).Layout.Row = ceil(kk / 2); ui.mb(kk).Layout.Column = mod(kk - 1, 2) + 1;
    end
    ui.brief = note('', 52);
    ui.preset = uidropdown(L, 'Items', {'-'}, 'ValueChangedFcn', @(~, ~) applyPreset(), ...
        'BackgroundColor', K.field, 'FontColor', K.text);
    place(ui.preset, next(28), [1 2]);

    % LAB selectors
    ui.labMode = uibuttongroup(L, 'BorderType', 'none', 'BackgroundColor', K.panel, ...
        'SelectionChangedFcn', @(~, e) setLabMode(lower(e.NewValue.Text)));
    place(ui.labMode, next(30), [1 2]); ui.labRow = row;
    ui.labHang = uitogglebutton(ui.labMode, 'Text', 'HANGING', 'Position', [0 2 136 26]);
    ui.labUp = uitogglebutton(ui.labMode, 'Text', 'UPRIGHT', 'Position', [140 2 136 26]);
    ui.labCtrl = uidropdown(L, 'Items', {'PID'}, 'ValueChangedFcn', @(s, ~) setLabCtrl(s.Value), ...
        'BackgroundColor', K.field, 'FontColor', K.text);
    place(ui.labCtrl, next(28), [1 2]); ui.labRow(2) = row;

    head('CONTROLLER');
    ui.kp   = slider('kp',   'Kp rotor', [0 25], '%.2f');
    ui.ki   = slider('ki',   'Ki rotor', [0 20], '%.2f');
    ui.kd   = slider('kd',   'Kd rotor', [0 25], '%.2f');
    ui.kpp  = slider('kpp',  'Kp pendulum', [0 1000], '%.0f');
    ui.kdp  = slider('kdp',  'Kd pendulum', [0 200], '%.1f');
    ui.k1   = slider('k1',   'k1  arm angle', [-50 50], '%.3f');
    ui.k2   = slider('k2',   'k2  arm rate', [-50 50], '%.3f');
    ui.k3   = slider('k3',   'k3  pendulum angle', [0 900], '%.1f');
    ui.k4   = slider('k4',   'k4  pendulum rate', [0 150], '%.2f');
    ui.bv   = slider('bv',   'b  virtual damping', [0 5], '%.2f');
    ui.uon  = slider('uon',  'u on (deg/s²)', [0 1500], '%.0f');
    ui.db   = slider('db',   'dead band (deg)', [0 5], '%.2f');
    ui.imp  = slider('imp',  'impulse (deg)', [-20 20], '%.1f');
    ui.step = slider('step', 'step (deg)', [-45 45], '%.1f');
    ui.dist = slider('dist', 'load D (deg/s²)', [-90 90], '%.1f');
    ui.ulim = slider('ulim', 'u limit (deg/s²)', [50 1500], '%.0f');
    ui.fdr  = slider('fdr',  'D filter rotor (Hz)', [0.5 200], '%.1f');
    ui.fdp  = slider('fdp',  'D filter pendulum (Hz)', [0.5 200], '%.1f');
    ui.div  = slider('div',  'loop rate (Hz)', [10 500], '%.0f');
    ui.ma   = slider('ma',   'moving average (n)', [1 32], '%.0f');
    ui.div.ValueChangedFcn = @(s, ~) intSlider(s, 'div');
    ui.ma.ValueChangedFcn = @(s, ~) intSlider(s, 'ma');
    ui.labels = struct('kp', ui.kp.UserData.name, 'kd', ui.kd.UserData.name);   % renamed for the swing-up
    ui.lqrQ = uieditfield(L, 'text', 'Value', '1 1 10 1', 'Tooltip', 'diag(Q)', ...
        'BackgroundColor', K.field, 'FontColor', K.text);
    place(ui.lqrQ, next(26), 1); ui.lqrRow = row;
    ui.lqrR = uieditfield(L, 'numeric', 'Value', 0.01, 'Limits', [1e-6 1e6], 'Tooltip', 'R', ...
        'BackgroundColor', K.field, 'FontColor', K.text);
    place(ui.lqrR, row, 2);
    ui.lqr = btn('LQR  →  k', @(~, ~) onLqr(), [1 2], 28); ui.lqrRow(2) = row;

    head('PENDULUM');
    ui.L   = slider('physics', 'length L (m)', [0.12 0.40], '%.3f');
    ui.Q   = slider('physics', 'pivot Q', [3 60], '%.1f');
    ui.r   = slider('physics', 'arm radius r (m)', [0.08 0.20], '%.3f');
    ui.fitBtn = btn('FREE SWING  ·  record 15 s', @(~, ~) onRecord(), [1 2], 28);
    ui.useFit = btn('USE MEASURED PENDULUM', @(~, ~) onUseFit(), [1 2], 28);

    % ---- centre: rig, telemetry ---------------------------------------------------
    C = uigridlayout(G, [3 1], 'RowHeight', {'1x', 84, 30}, 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
        'BackgroundColor', K.bg);
    C.Layout.Row = 2; C.Layout.Column = 2;
    axR = uiaxes(C); axR.BackgroundColor = K.bg; rig = odyssix.ui.rigBuild(axR, 'Dark', true);
    tg = uigridlayout(C, [2 4], 'RowHeight', {20, '1x'}, 'Padding', [12 4 12 4], 'RowSpacing', 0, ...
        'BackgroundColor', K.panel);
    names = {'ARM  θ', 'PENDULUM', 'INPUT  u  deg/s²', 'PHASE'};
    for kk = 1:4, lbl(tg, names{kk}, 10, K.dim, 'bold'); end
    ui.tTheta = big(tg, K.cyan); ui.tPend = big(tg, K.orange); ui.tU = big(tg, K.text); ui.tPhase = big(tg, K.text);
    ui.tPhase.FontSize = 17;
    ui.say = lbl(C, '', 12.5, K.text, 'normal'); ui.say.HorizontalAlignment = 'center';

    % ---- right: plots -----------------------------------------------------------------
    P = uigridlayout(G, [3 1], 'RowHeight', {'1x', '1x', '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 6, ...
        'BackgroundColor', K.bg);
    P.Layout.Row = 2; P.Layout.Column = 3;
    axT = mkAx(P, 'ARM  θ  (deg)'); axP = mkAx(P, 'PENDULUM  (deg)'); axA = mkAx(P, '');
    tr.ref = plot(axT, nan, nan, '--', 'Color', K.dim, 'LineWidth', 1.1);
    tr.thS = plot(axT, nan, nan, 'Color', K.ghost, 'LineWidth', 1.6);
    tr.thR = plot(axT, nan, nan, 'Color', K.violet, 'LineWidth', 1.4);
    tr.thH = plot(axT, nan, nan, 'Color', K.cyan, 'LineWidth', 1.9);
    tr.pS = plot(axP, nan, nan, 'Color', K.ghost, 'LineWidth', 1.6);
    tr.pR = plot(axP, nan, nan, 'Color', K.violet, 'LineWidth', 1.4);
    tr.pH = plot(axP, nan, nan, 'Color', K.orange, 'LineWidth', 1.9);
    tr.pK = plot(axP, nan, nan, '.', 'Color', K.text, 'MarkerSize', 4);     % 500 Hz records of a replayed run
    tr.cur = [xline(axT, nan, 'Color', K.dim) xline(axP, nan, 'Color', K.dim)];
    legend(axT, [tr.thH tr.thS tr.thR tr.ref], {'rig', 'sim', 'replay', 'ref'}, 'Location', 'northeast', ...
        'TextColor', K.dim, 'Color', K.bg, 'EdgeColor', 'none', 'AutoUpdate', 'off', 'Orientation', 'horizontal');   % opaque: traces never run through the text

    % ---- bottom: rig control, metrics + live actions, runs -------------------------
    B1 = uigridlayout(G, [4 2], 'RowHeight', {28, 38, 38, 38}, 'ColumnWidth', {'1x', '1x'}, ...
        'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 6, 'BackgroundColor', K.panel);
    B1.Layout.Row = 3; B1.Layout.Column = 1;
    ui.port = uidropdown(B1, 'Items', {'auto'}, 'BackgroundColor', K.field, 'FontColor', K.text);
    ui.connect = uibutton(B1, 'Text', 'CONNECT', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onConnect());
    ui.arm = uibutton(B1, 'Text', 'ARM', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onArm());
    ui.start = uibutton(B1, 'Text', 'START', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) send('s'));
    ui.run = uibutton(B1, 'Text', '▶  RUN', 'FontSize', 15, 'FontWeight', 'bold', ...
        'BackgroundColor', K.cyanDim, 'FontColor', 'w', 'ButtonPushedFcn', @(~, ~) onRunRig());
    ui.stopRun = uibutton(B1, 'Text', '■  STOP', 'FontSize', 15, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(~, ~) onStopRun());
    ui.zero = uibutton(B1, 'Text', 'ZERO DATUMS', 'ButtonPushedFcn', @(~, ~) send('z'));
    ui.sim = uibutton(B1, 'Text', 'PLAY SIMULATION', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) animate(S, 'sim'));

    B2 = uigridlayout(G, [3 1], 'RowHeight', {'1x', 30, 30}, 'Padding', [10 8 10 8], 'RowSpacing', 5, ...
        'BackgroundColor', K.panel);
    B2.Layout.Row = 3; B2.Layout.Column = 2;
    ui.table = uitable(B2, 'ColumnName', {'', 'SIM', 'RIG', 'REF'}, 'RowName', {}, ...
        'ColumnWidth', {'auto', 70, 70, 120}, 'FontSize', 12, 'BackgroundColor', K.panel, 'ForegroundColor', K.text);
    ag = uigridlayout(B2, [1 5], 'ColumnWidth', {90, 70, '1x', '1x', '1x'}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 6, 'BackgroundColor', K.panel);
    lbl(ag, 'ARM', 11, K.cyan, 'bold');
    ui.target = uieditfield(ag, 'numeric', 'Value', 30, 'Limits', [-120 120], 'ValueDisplayFormat', '%.0f°', ...
        'BackgroundColor', K.field, 'FontColor', K.text);
    ui.goto = uibutton(ag, 'Text', 'GO TO', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onGoto(ui.target.Value, false));
    ui.stepBtn = uibutton(ag, 'Text', 'STEP', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onGoto(ui.target.Value, true), ...
        'Tooltip', 'instant set-point jump to the typed angle');
    ui.home = uibutton(ag, 'Text', 'HOME  0°', 'ButtonPushedFcn', @(~, ~) onGoto(0, false));
    pg_ = uigridlayout(B2, [1 5], 'ColumnWidth', {90, 70, '2x', '1x', '1x'}, 'Padding', [0 0 0 0], ...
        'ColumnSpacing', 6, 'BackgroundColor', K.panel);
    lbl(pg_, 'PENDULUM', 11, K.orange, 'bold');
    ui.ptarget = uieditfield(pg_, 'numeric', 'Value', 180, 'Limits', [0 180], 'ValueDisplayFormat', '%.0f°', ...
        'BackgroundColor', K.field, 'FontColor', K.text, ...
        'Tooltip', '180 = swing up and balance  ·  0 < a < 180 = swing to ±a  ·  0 = stop the swing');
    ui.swing = uibutton(pg_, 'Text', 'SWING  →  180°', 'FontWeight', 'bold', 'BackgroundColor', K.orangeDim, ...
        'FontColor', 'w', 'ButtonPushedFcn', @(~, ~) onPendulumTarget(ui.ptarget.Value, false));
    ui.ptarget.ValueChangedFcn = @(~, ~) pendTargetChanged();
    ui.pstop = uibutton(pg_, 'Text', 'STOP SWING', 'ButtonPushedFcn', @(~, ~) onPendulumTarget(0, false));
    ui.push = uibutton(pg_, 'Text', 'PUSH MARK', 'ButtonPushedFcn', @(~, ~) onPushMark(), ...
        'Tooltip', 'Press right after pushing the pendulum on purpose: the push is logged with the run and the firmware sends the last 1.5 s at 500 Hz');
    if small, set([ui.goto ui.stepBtn ui.home ui.swing ui.pstop ui.push], 'FontSize', 10.5); end   % laptop screens

    B3 = uigridlayout(G, [3 4], 'RowHeight', {'1x', 28, 28}, 'ColumnWidth', {150, 100, '1x', 70}, ...
        'Padding', [10 8 10 8], 'RowSpacing', 5, 'ColumnSpacing', 6, 'BackgroundColor', K.panel);
    B3.Layout.Row = 3; B3.Layout.Column = 3;
    ui.runs = uitable(B3, 'ColumnName', {'RUN', 'RESULT', 'KEY NUMBERS'}, 'RowName', {}, ...
        'ColumnWidth', {270, 150, 'auto'}, 'FontSize', 11, 'BackgroundColor', K.panel, ...
        'ForegroundColor', K.text, 'CellSelectionCallback', @(~, e) onPickRun(e));
    ui.runs.Layout.Column = [1 4];
    ui.runsFilter = uidropdown(B3, 'Items', {'this mission', 'all runs', 'hardware only'}, ...
        'ValueChangedFcn', @(~, ~) refreshRuns(), 'BackgroundColor', K.field, 'FontColor', K.text);
    ui.loadRun = uibutton(B3, 'Text', 'OVERLAY RUN', 'ButtonPushedFcn', @(~, ~) onOverlay(), ...
        'Tooltip', 'draw the selected run over the simulation (violet)');
    ui.tTime = lbl(B3, '', 11, K.dim, 'normal');
    ui.next = uibutton(B3, 'Text', 'NEXT ›', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) nextSession(), ...
        'Tooltip', 'guided session: every experiment in order');
    ui.play = uibutton(B3, 'Text', '▶  PLAY', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) onPlay(), ...
        'Tooltip', 'play / pause the simulation or the overlaid run on the 3-D rig');
    ui.speed = uidropdown(B3, 'Items', {'0.5x', '1x', '2x', '4x'}, 'Value', '1x', 'BackgroundColor', K.field, 'FontColor', K.text);
    ui.scrub = uislider(B3, 'Limits', [0 1], 'Value', 0, 'MajorTicks', [], 'MinorTicks', [], ...
        'ValueChangingFcn', @(~, e) onScrub(e.Value), 'ValueChangedFcn', @(s, ~) onScrub(s.Value));
    ui.scrub.Layout.Column = [3 4];
    player = struct('D', [], 'kind', '', 't', 0, 'playing', false, ...
        'timer', timer('ExecutionMode', 'fixedSpacing', 'Period', 0.05, 'BusyMode', 'drop', 'TimerFcn', @(~, ~) playerTick()));

    styleButtons(fig);
    pending = timer('ExecutionMode', 'singleShot', 'StartDelay', 0.25, 'TimerFcn', @(~, ~) safeUpdate());
    tick = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, 'BusyMode', 'drop', ...
                 'TimerFcn', @(~, ~) onTick(), 'ErrorFcn', @(~, e) say(['internal: ' e.Data.message], 'warn'));
    refreshPorts(); selectMission(5); setEnabled(); start(tick);

    app = struct('fig', fig, 'ui', ui, 'link', link, 'select', @selectMission, 'lab', @selectLab, ...
                 'preset', @setPreset, 'set', @setParam, 'simulate', @() animate(S, 'sim'), 'result', @() getS(), ...
                 'startEmulator', @onEmulator, 'connect', @onConnect, 'send', @send, 'armNoPrompt', @armNow, ...
                 'runRig', @onRunRig, 'stopRun', @onStopRun, 'rigData', @() getH(), 'abort', @doAbort, 'pushMark', @onPushMark, ...
                 'gotoAngle', @(v) onGoto(v, false), 'step', @(v) onGoto(v, true), ...
                 'swingUp', @(varargin) onPendulumTarget(180, varargin{:}), ...
                 'pendulumTarget', @(a, varargin) onPendulumTarget(a, varargin{:}), ...
                 'record', @onRecord, 'fit', @() getFit(), 'useFit', @onUseFit, 'lqr', @onLqr, ...
                 'rigCfg', @() getRigCfg(), 'lastSaved', @() getLastSaved(), 'replay', @loadReplay, ...
                 'next', @nextSession, 'mission', @() getMission());

    % =================================================================== missions
    function selectMission(k)
        if hwRun.on, say('Stop the run first.', 'warn'); return; end
        mis = k; M = MIS(k);
        for j = 1:numel(ui.mb)
            if j == k, set(ui.mb(j), 'BackgroundColor', K.cyan, 'FontColor', K.bg);
            else,      set(ui.mb(j), 'BackgroundColor', K.btn, 'FontColor', K.text); end
        end
        ui.mission.Text = upper(M.title);
        ui.brief.Text = M.brief;
        isLab = strcmp(M.tag, 'LAB');
        for r_ = ui.labRow, L.RowHeight{r_} = 30 * isLab; end
        set([ui.labMode ui.labCtrl], 'Visible', onoff(isLab));
        ui.preset.Visible = onoff(~isLab); L.RowHeight{ui.preset.Layout.Row} = 28 * ~isLab;
        replay = []; clearTrace('replay'); H = []; clearTrace('rig');
        if isLab
            setLabMode(lab.mode);
        else
            ui.preset.Items = M.presets(:, 1)'; ui.preset.Value = ui.preset.Items{1};
            pl = basePlant(max(M.exp, 2)); physicsToSliders();
            applyPreset();
        end
        refreshRuns();
    end

    function selectLab(mode, ctrl)
        if mis ~= numel(MIS), selectMission(numel(MIS)); end
        lab.mode = mode; if nargin > 1, lab.ctrl = ctrl; end
        setLabMode(mode);
    end

    function setLabMode(m)
        lab.mode = m;
        ui.labHang.Value = strcmp(m, 'hanging'); ui.labUp.Value = strcmp(m, 'upright');
        % upright: LQR first; the robust tuning study gave it 27 % less pendulum
        % error than the best dual PID (results/reports/2026-10-21_rig_session.md)
        if strcmp(m, 'hanging'), items = {'PID', 'State feedback', 'On-off', 'Energy (swing / swing-up)'}; else, items = {'LQR', 'PID'}; end
        if strcmp(m, 'upright') && ~any(strcmp(lab.ctrl, items)), lab.ctrl = 'LQR'; end
        ui.labCtrl.Items = items;
        if ~any(strcmp(items, lab.ctrl)), lab.ctrl = items{1}; end
        setLabCtrl(lab.ctrl);
    end

    function setLabCtrl(c)
        lab.ctrl = c; ui.labCtrl.Value = c;
        swingPanel = false; ui.labels.kp.Text = 'Kp rotor'; ui.labels.kd.Text = 'Kd rotor';
        ui.uon.UserData.name.Text = 'u on (deg/s²)';
        if startsWith(c, 'Energy')
            cfg = swingCfg(ui.ptarget.Value); pl = basePlant(3); physicsToSliders();
            showSwingPanel(); simSwing(ui.ptarget.Value); return;
        end
        e = labExp();
        cfg = odyssix.sim.defaults(e); cfg.seq = 0; cfg.seconds = 24;
        pl = basePlant(e); physicsToSliders();
        enableFor(e); loadControls(cfg);          % limits first: a value must never be clamped by the previous mission's range
        if e == 23, ui.lqrQ.Value = '1 1 10 1'; ui.lqrR.Value = 0.01; end
        ui.brief.Text = ternary(strcmp(lab.mode, 'hanging'), ...
            'Hanging. RUN, then GO TO / STEP the arm, pluck it, change gains live. PENDULUM: swing it to any height, 180 = up.', ...
            ternary(strcmp(lab.ctrl, 'LQR'), ...
            'Upright, LQR (recommended: 27 % less pendulum error than the best PID). Hold it up, RUN, let go when told.', ...
            'Upright, dual PID. Hold it up, RUN, let go when told. Then GO TO, tap it, change gains live.'));
        update();
    end

    function showSwingPanel()
        % the energy controller's own parameters; the PID ones do nothing here
        if swingPanel, return; end
        swingPanel = true; d = odyssix.sim.defaults(24);
        enableFor(24);
        for f = {'uon', 'kp', 'kd', 'k1', 'k2', 'k3', 'k4'}, setSlider(ui.(f{1}), d.(f{1})); end
        ui.labels.kp.Text = 'Kp arm centring'; ui.labels.kd.Text = 'Kd arm centring';
        ui.uon.UserData.name.Text = 'pump strength (deg/s²)';
        ui.brief.Text = ['Energy control. PENDULUM 180 swings it up and the LQR (k1..k4) catches it; ' ...
                         'any other angle sets the swing height; 0 stops it.'];
    end

    function e = labExp()
        if strcmp(lab.mode, 'hanging')
            e = 21; if strcmp(lab.ctrl, 'State feedback'), e = 9; elseif strcmp(lab.ctrl, 'On-off'), e = 22; elseif startsWith(lab.ctrl, 'Energy'), e = 24; end
        else
            e = 6; if strcmp(lab.ctrl, 'LQR'), e = 23; end
        end
    end

    function applyPreset()
        M = MIS(mis); p = M.presets(strcmp(M.presets(:, 1), ui.preset.Value), :);
        cfg = odyssix.sim.defaults(M.exp);
        v = p{2}; f = fieldnames(v);
        for i = 1:numel(f), cfg.(f{i}) = v.(f{i}); end
        enableFor(M.exp); loadControls(cfg);      % limits first (a T5 range once clamped T9's 20 deg step to 10)
        if M.exp == 10, ui.lqrQ.Value = '1 1'; ui.lqrR.Value = 1; end
        want = cfg; readControls();
        for f_ = {'kp', 'kd', 'kpp', 'kdp', 'step', 'dist', 'ulim'}
            if abs(want.(f_{1}) - cfg.(f_{1})) > 1e-9
                say(sprintf('%s = %g is outside its slider; using %g', f_{1}, want.(f_{1}), cfg.(f_{1})), 'warn');
            end
        end
        update();
    end
    function setPreset(name), ui.preset.Value = name; applyPreset(); end

    function loadControls(c)
        f = [{'kp', 'kd', 'kpp', 'kdp', 'step', 'dist', 'ulim'}, NEW];
        for i = 1:numel(f)
            if isfield(c, f{i})
                v = c.(f{i}); if strcmp(f{i}, 'div'), v = 500 / v; end
                setSlider(ui.(f{i}), v);
            end
        end
    end

    function enableFor(e)
        % only what this experiment uses is shown
        pid = any(e == [2:8 21 24]); inner = any(e == [3:8 21]); sf = any(e == [9 10 23 24]);
        isLab = strcmp(MIS(mis).tag, 'LAB');
        vis = struct('kp', pid, 'kd', pid, 'kpp', inner, 'kdp', inner, 'ki', any(e == [6 8 21]), ...
            'k1', sf, 'k2', sf, 'k3', any(e == [23 24]), 'k4', any(e == [23 24]), 'bv', any(e == [9 10]) && ~isLab, ...
            'uon', any(e == [22 24]), 'db', e == 22, 'imp', e == 7, 'step', ~isLab && ~any(e == [7 21]), ...
            'dist', any(e == [2 8]), 'ulim', e >= 2 && e ~= 24, 'fdr', any(e == [6 7 8 21]), ...
            'fdp', any(e == [6 7 8 21 23]), 'div', e >= 6 && e ~= 24, 'ma', e >= 6 && e ~= 24);
        f = fieldnames(vis);
        for i = 1:numel(f), showSlider(ui.(f{i}), vis.(f{i})); end
        lq = any(e == [10 23]);
        for r_ = ui.lqrRow, L.RowHeight{r_} = 28 * lq; end
        set([ui.lqrQ ui.lqrR ui.lqr], 'Visible', onoff(lq));
        ui.step.Limits = ternary(e >= 2 && e <= 5, [-10 10], [-45 45]);
        ui.dist.Limits = ternary(e == 2, [-5 5], [-90 90]);
    end

    function readControls()
        cfg.kp = ui.kp.Value; cfg.kd = ui.kd.Value; cfg.kpp = ui.kpp.Value; cfg.kdp = ui.kdp.Value;
        cfg.step = ui.step.Value; cfg.dist = ui.dist.Value; cfg.ulim = ui.ulim.Value;
        if cfg.exp >= 6
            for i = 1:numel(NEW), cfg.(NEW{i}) = ui.(NEW{i}).Value; end
            cfg.div = max(1, min(50, round(500 / ui.div.Value))); cfg.ma = round(ui.ma.Value);
        end
        pl.wg2 = 9.81 / (ui.L.Value * 0.6805); pl.Q = ui.Q.Value; pl.wr2 = ui.r.Value * pl.wg2 / 9.81;
        if cfg.exp >= 6, cfg.wg2 = min(120, max(20, pl.wg2)); end
    end

    function physicsToSliders()
        setSlider(ui.L, 9.81 / (pl.wg2 * 0.6805)); setSlider(ui.Q, pl.Q); setSlider(ui.r, pl.wr2 * 9.81 / pl.wg2);
    end

    % =================================================================== simulation
    function update()
        readControls();
        try
            if cfg.exp >= 6, [o, c] = simScript(cfg); o.onTick = @feedRig; S = odyssix.sim.runCtrl(c, pl, o); cfg.target = c.target; cfg.target_t = c.target_t; cfg.target_end = c.target_end;
            else, S = odyssix.sim.runTutorial(cfg, pl, struct('onTick', @feedRig)); end
            if cfg.exp >= 2, lp = odyssix.sim.loop(cfg, pl); else, lp = []; end
        catch err
            say(['simulation: ' err.message], 'warn'); return;
        end
        drawTrace(S, 'sim'); drawAnalysis(); fillTable(); poseAt(S, height(S));
    end

    function safeUpdate()
        try, if isvalid(fig), update(); end, catch err, say(['simulation: ' err.message], 'warn'); end
    end

    function feedRig()
        % A simulation blocks MATLAB's timers, including the one that feeds the
        % firmware's 1 s host watchdog; a run still active on the rig would stop.
        if toc(feedT) > 0.25, feedT = tic; try, link.keepAlive(); catch, end, end
    end

    function [o, c] = simScript(c)
        % the simulated operator, so the preview shows the mission
        o = struct(); c.target = NaN; c.target_t = NaN; c.target_end = NaN;
        if strcmp(MIS(mis).tag, 'LAB')
            if strcmp(lab.mode, 'hanging'), o.psi0 = 20; ts = 6; else, ts = 8; end
            v = ui.target.Value;
            o.events = struct('t', {ts, ts + 8}, 'key', {'ref', 'ref'}, 'val', {v, 0});
            c.target = v; c.target_t = ts; c.target_end = ts + 8; c.seconds = 24;   % holds v until it goes home
        elseif c.exp == 21
            o.psi0 = 20;
        end
    end

    function c = swingCfg(amp)
        % the firmware's energy-control defaults, with what the swing panel shows
        % (pump, arm centring, catch LQR); the pendulum constant from the PENDULUM
        % fields (measured by FREE SWING), the target from the field
        if nargin < 1, amp = ui.ptarget.Value; end
        c = odyssix.sim.defaults(24); c.amp = amp; if amp < 179, c.seconds = 25; end
        if swingPanel
            c.uon = ui.uon.Value; c.kp = ui.kp.Value; c.kd = ui.kd.Value;
            c.k1 = ui.k1.Value; c.k2 = ui.k2.Value; c.k3 = ui.k3.Value; c.k4 = ui.k4.Value;
        end
        pl.wg2 = 9.81 / (ui.L.Value * 0.6805); pl.Q = ui.Q.Value; pl.wr2 = ui.r.Value * pl.wg2 / 9.81;
        c.wg2 = min(120, max(20, pl.wg2));
    end

    function simSwing(amp)
        c = swingCfg(amp);
        o = struct('onTick', @feedRig); if amp < 1, o.psi0 = 40; end   % 'stop the swing': start swinging
        S = odyssix.sim.runCtrl(c, pl, o); lp = []; cfg = c;
        drawTrace(S, 'sim'); drawAnalysis(); fillTable(); poseAt(S, height(S));
        player.D = S; player.kind = 'sim'; player.t = S.t(1); player.playing = false; ui.play.Text = '▶  PLAY';
    end

    % =================================================================== drawing
    function drawTrace(D, kind)
        if isempty(D), return; end
        y = pendView(D);
        switch kind
            case 'sim', set(tr.thS, 'XData', D.t, 'YData', D.rotor); set(tr.pS, 'XData', D.t, 'YData', y);
                set(tr.ref, 'XData', D.t, 'YData', D.ref);
            case 'rig', set(tr.thH, 'XData', D.t, 'YData', D.rotor); set(tr.pH, 'XData', D.t, 'YData', y);
            case 'replay', set(tr.thR, 'XData', D.t, 'YData', D.rotor); set(tr.pR, 'XData', D.t, 'YData', y);
        end
        autoAxes();
    end

    function clearTrace(kind)
        switch kind
            case 'rig', set([tr.thH tr.pH], 'XData', nan, 'YData', nan);
            case 'replay', set([tr.thR tr.pR tr.pK], 'XData', nan, 'YData', nan);
        end
    end

    function autoAxes()
        tt = [0 1]; yT = []; yP = [];
        for h_ = [tr.thS tr.thH tr.thR tr.ref]
            x = h_.XData; y = h_.YData; ok = isfinite(y);
            if any(ok), tt(2) = max(tt(2), max(x(ok))); yT = [yT, y(ok)]; end %#ok<AGROW>
        end
        for h_ = [tr.pS tr.pH tr.pR]
            y = h_.YData; ok = isfinite(y); if any(ok), yP = [yP, y(ok)]; end %#ok<AGROW>
        end
        xlim(axT, tt); xlim(axP, tt);
        if ~isempty(yT), ylim(axT, pad([min(yT) max(yT)], 1)); end
        if ~isempty(yP), ylim(axP, pad([min(yP) max(yP)], 1)); end
        if showAlpha(), axP.Title.String = 'PENDULUM  α from upright (deg)';
        elseif cfg.exp == 24 && getf(cfg, 'amp', 180) >= 179, axP.Title.String = 'PENDULUM  |ψ| from hanging  (180 = upright)';
        else, axP.Title.String = 'PENDULUM  ψ from hanging (deg)'; end
    end

    function b = showAlpha(), b = any(cfg.exp == [5 6 7 8 23]); end
    function y = pendView(D)
        if showAlpha(), y = mod(180 - D.psi + 180, 360) - 180;
        elseif cfg.exp == 24 && getf(cfg, 'amp', 180) >= 179, y = abs(mod(D.psi + 180, 360) - 180);   % height: 180 = upright
        else, y = mod(D.psi + 180, 360) - 180; end
    end
    function b = isUp(), b = any(cfg.exp == [5 6 7 8 23]); end

    function poseAt(D, k)
        if isempty(D) || k < 1, return; end
        odyssix.ui.rigPose(rig, D.rotor(k), 180 - D.psi(k), D.ref(k), ui.L.Value / 0.258);
        ui.tTheta.Text = sprintf('%+7.2f°', D.rotor(k));
        ui.tPend.Text = sprintf('%+7.2f°', pendView(D(k, :)));
        ui.tU.Text = sprintf('%+6.0f', D.u(k));
        ui.tPhase.Text = phaseName(D, D.phase(k));
    end

    % ---- player: plays a simulation or a recorded run on the 3-D rig and the
    %      plot cursor; timer-driven, so the window stays live; pause / seek / speed
    function animate(D, kind)
        if isempty(D), return; end
        if hwRun.on, say('A rig run is live: the rig view shows it.', 'warn'); return; end
        player.D = D; player.kind = kind; player.t = D.t(1);
        ui.scrub.Limits = [D.t(1), max(D.t(end), D.t(1) + 0.01)]; ui.scrub.Value = D.t(1);
        player.playing = true; ui.play.Text = '❚❚  PAUSE';
        if strcmp(get(player.timer, 'Running'), 'off'), start(player.timer); end
    end
    function onPlay()
        if isempty(player.D)
            if ~isempty(replay), animate(replay, 'replay'); elseif ~isempty(S), animate(S, 'sim'); end
            return;
        end
        player.playing = ~player.playing;
        ui.play.Text = ternary(player.playing, '❚❚  PAUSE', '▶  PLAY');
        if player.playing
            if player.t >= player.D.t(end), player.t = player.D.t(1); end
            if strcmp(get(player.timer, 'Running'), 'off'), start(player.timer); end
        end
    end
    function playerTick()
        try
            if ~isvalid(fig) || ~player.playing || isempty(player.D), return; end
            sp = sscanf(ui.speed.Value, '%fx'); player.t = player.t + 0.05 * sp;
            if player.t >= player.D.t(end)
                player.t = player.D.t(end); player.playing = false; ui.play.Text = '▶  PLAY';
            end
            showAt(player.t);
        catch
        end
    end
    function onScrub(t)
        if isempty(player.D)
            if ~isempty(replay), player.D = replay; player.kind = 'replay'; elseif ~isempty(S), player.D = S; player.kind = 'sim'; else, return; end
            ui.scrub.Limits = [player.D.t(1), max(player.D.t(end), player.D.t(1) + 0.01)];
        end
        player.t = t; showAt(t);
    end
    function showAt(t)
        D = player.D; k = find(D.t >= t, 1); if isempty(k), k = height(D); end
        poseAt(D, k); set(tr.cur, 'Value', D.t(k)); ui.scrub.Value = min(max(D.t(k), ui.scrub.Limits(1)), ui.scrub.Limits(2));
        ui.tTime.Text = sprintf('%s  %5.1f / %.1f s', upper(player.kind), D.t(k) - D.t(1), D.t(end) - D.t(1));
    end

    function drawAnalysis()
        cla(axA, 'reset'); styleAx(axA); hold(axA, 'on');
        e = cfg.exp; D = H; if isempty(D), D = replay; end
        dc = ternary(isempty(H), K.violet, K.cyan);              % a replayed run keeps its violet
        if strcmp(MIS(mis).tag, 'LAB') || e == 24
            plot(axA, S.t, S.u, 'Color', K.ghost, 'LineWidth', 1);
            if ~isempty(D), plot(axA, D.t, D.u, 'Color', dc, 'LineWidth', 1.2); end
            title(axA, 'INPUT  u  (deg/s²)'); axLabels('t (s)', ''); axis(axA, 'tight'); return;
        end
        switch e
            case 1
                if isempty(fitRes)
                    title(axA, 'FREE SWING  ·  record it on the rig'); axis(axA, 'off');
                else
                    plot(axA, fitRes.t, fitRes.yDeg, '.', 'Color', K.dim, 'MarkerSize', 5);
                    plot(axA, fitRes.t, fitRes.yFitDeg, 'Color', K.orange, 'LineWidth', 1.4);
                    title(axA, sprintf('FREE SWING  ωg² %.2f  ·  dry friction %.2f rad/s²  ·  rms %.2f°', fitRes.wg2, getf(fitRes, 'coulomb'), fitRes.rmsDeg));
                    axLabels('t from the start of the decay (s)', 'ψ (deg)');
                end
            case {2, 4}
                w = logspace(-1, 2, 400); s = 1j * w; Lj = polyval(lp.L.num, s) ./ polyval(lp.L.den, s);
                if e == 2
                    plot(axA, w, 20*log10(abs(1 ./ (1 + Lj))), 'Color', K.cyan, 'LineWidth', 1.5);
                    plot(axA, w, 20*log10(abs(Lj ./ (1 + Lj))), 'Color', K.orange, 'LineWidth', 1.5);
                    set(axA, 'XScale', 'log'); title(axA, '|S| (cyan)  |T| (orange)  dB'); axLabels('ω (rad/s)', 'dB');
                else
                    plot(axA, real(Lj), imag(Lj), 'Color', K.cyan, 'LineWidth', 1.5);
                    plot(axA, -1, 0, '+', 'Color', K.red, 'MarkerSize', 12, 'LineWidth', 2);
                    th = linspace(0, 2*pi, 100); r0 = 1 / 10^(lp.margins.MsdB / 20);
                    plot(axA, -1 + r0*cos(th), r0*sin(th), '--', 'Color', K.orange);
                    xlim(axA, [-3 1]); ylim(axA, [-2 2]); title(axA, sprintf('NYQUIST  M_S %.2f dB', lp.margins.MsdB));
                    axLabels('Re L(jω)', 'Im L(jω)');
                end
            case 3
                ms = metricsOf(S); v = [getf(ms, 'ce_total') NaN];
                if ~isempty(D), mh = metricsOf(D); v(2) = getf(mh, 'ce_total'); end
                b = bar(axA, categorical({'sim', 'rig'}, {'sim', 'rig'}), v, 'FaceColor', 'flat', 'EdgeColor', 'none');   % fixed order: not alphabetical
                b.CData = [K.ghost; dc]; title(axA, 'CONTROL EFFORT  ∫|u|dt'); axLabels('', 'deg/s');
            case 7
                r = odyssix.sim.impulseAverage(S.t, S.alpha, S.rotor, S.phase);
                if r.n > 0, plot(axA, r.t, r.alpha - mean(r.alpha(r.t < 0)), 'Color', K.ghost, 'LineWidth', 1.5); end
                if ~isempty(D)
                    q = odyssix.sim.impulseAverage(D.t, mod(180 - D.psi + 180, 360) - 180, D.rotor, D.phase);
                    if q.n > 0, plot(axA, q.t, q.alpha - mean(q.alpha(q.t < 0)), 'Color', K.orange, 'LineWidth', 1.7); end
                end
                title(axA, sprintf('IMPULSE RESPONSE  ·  average of %d', r.n)); axLabels('t from the impulse (s)', 'α (deg)');
            otherwise
                if isempty(lp), return; end
                if isfield(lp, 'L') && ~isempty(lp.L)
                    n = lp.L.num; d = lp.L.den; n = [zeros(1, numel(d) - numel(n)), n];
                    ks = logspace(-1.5, 1, 140); Pz = zeros(numel(d) - 1, numel(ks));
                    for i = 1:numel(ks), Pz(:, i) = roots(d + ks(i) * n); end
                    plot(axA, real(Pz(:)), imag(Pz(:)), '.', 'Color', K.line, 'MarkerSize', 4);
                end
                plot(axA, real(lp.olPend), imag(lp.olPend), 'x', 'Color', K.dim, 'MarkerSize', 9, 'LineWidth', 1.5);
                plot(axA, real(lp.cl), imag(lp.cl), 'x', 'Color', K.cyan, 'MarkerSize', 11, 'LineWidth', 2.2);
                xline(axA, 0, 'Color', K.dim);
                Lm = min(40, 1.3 * max(abs([lp.cl; 1]))); xlim(axA, [-Lm 0.5 * Lm]); ylim(axA, [-Lm Lm]);
                title(axA, sprintf('CLOSED-LOOP POLES  ·  %s', ternary(lp.stable, 'stable', 'UNSTABLE')));
                axLabels('Re s (1/s)', 'Im s (1/s)');
        end
    end

    function axLabels(xl, yl)
        xlabel(axA, xl, 'Color', K.dim, 'FontSize', 9.5); ylabel(axA, yl, 'Color', K.dim, 'FontSize', 9.5);
    end

    function fillTable()
        M = MIS(mis); D = H; if isempty(D), D = replay; end
        if strcmp(M.tag, 'LAB') || cfg.exp == 24, rows = labRows(); else, rows = M.metrics; end
        ms = metricsOf(S); mh = struct(); if ~isempty(D), mh = metricsOf(D); end
        d = cell(0, 4);
        for i = 1:size(rows, 1)
            d(end+1, :) = {rows{i, 2}, fmt(getf(ms, rows{i, 1})), fmt(getf(mh, rows{i, 1})), rows{i, 3}}; %#ok<AGROW>
        end
        if ~isempty(lp) && isfield(lp, 'margins') && ~isempty(lp.margins) && ~strcmp(M.tag, 'LAB')
            d(end+1, :) = {'phase margin (°)', fmt(lp.margins.phiMdeg), '', M.pm};
        end
        ui.table.Data = d;
        if hwRun.on, return; end
        st = S.Properties.UserData.state; why = S.Properties.UserData.abort;
        if ~isempty(lp) && ~lp.stable, say('Simulation: UNSTABLE with these gains.', 'warn');
        elseif strcmp(st, 'ABORTED'), say(['Simulation aborts: ' why], 'warn');
        else, say(M.next, 'ok'); end
    end

    function rows = labRows()
        if cfg.exp == 24 && getf(cfg, 'amp', 180) < 179
            rows = {'swing_amp_deg', 'swing amplitude, last 5 s (°)', sprintf('%.0f', cfg.amp); 'arm_max_deg', 'arm travel (°)', '< 240'};
        elseif cfg.exp == 24
            rows = {'t_catch_s', 'caught upright after (s)', '4-18 sim'; 'arm_max_deg', 'arm travel (°)', '< 240'; ...
                    'alpha_rms_up_deg', 'α rms after catch (°)', ''};
        elseif strcmp(lab.mode, 'hanging')
            rows = {'stop_time_s', 'swing stopped after (s)', '< 3'; 'hold_reach_s', 'reached target (s)', ''; ...
                    'hold_error_deg', 'hold error (°)', '0'};
        else
            rows = {'alpha_rms_deg', 'α rms balancing (°)', ''; 'hold_reach_s', 'reached target (s)', ''; ...
                    'hold_error_deg', 'hold error (°)', '0'; 'tap_recover_s', 'tap recovery (s)', ''};
        end
    end

    function m = metricsOf(D)
        % a simulation (500 Hz) is scored at the rig's 50 Hz stream, so both
        % columns see the same samples (control effort and peaks depend on it)
        if height(D) > 20 && median(diff(D.t(1:20))) < 0.01
            ud = D.Properties.UserData; D = D(1:10:end, :); D.Properties.UserData = ud;
        end
        c = cfg; u_ = D.Properties.UserData;
        if isstruct(u_) && isfield(u_, 'cfg') && isstruct(u_.cfg) && isfield(u_.cfg, 'exp'), c = u_.cfg; end
        try, m = odyssix.sim.metrics(D, c); catch, m = struct(); end
        k = find(D.phase == 8, 1);
        if c.exp == 24
            m.t_catch_s = NaN; if ~isempty(k), m.t_catch_s = D.t(k) - D.t(1); end
            m.arm_max_deg = max(abs(D.rotor));
            if ~isempty(k), a = mod(180 - D.psi(k:end) + 180, 360) - 180; m.alpha_rms_up_deg = sqrt(mean(a.^2)); end
            w5 = D.t >= D.t(end) - 5; m.swing_amp_deg = max(abs(mod(D.psi(w5) + 180, 360) - 180));
        end
        if any(c.exp == [6 23]) && ~isempty(k)
            a = mod(180 - D.psi + 180, 360) - 180; w = D.phase == 8;
            m.alpha_rms_deg = sqrt(mean(a(w).^2));
            j = find(w & abs(a) > 3, 1);                       % a tap: |alpha| > 3 deg in HOLD
            if ~isempty(j), r = odyssix.pend.recovery(D.t, a, D.t(j), 1); m.tap_recover_s = r.recoverS; end
        end
    end

    % =================================================================== rig: link
    function refreshPorts()
        B = odyssix.stm32.listBoards(); p = [{'auto'}, B.ports(:)'];
        if ~isempty(emu.port), p = [p, {emu.port}]; end
        ui.port.Items = p;
    end

    function onConnect()
        if link.isOpen(), doAbort(); link.close(); setEnabled(); return; end
        port = ui.port.Value;
        if strcmp(port, 'auto')
            B = odyssix.stm32.listBoards();
            if isempty(B.ports)
                sel = uiconfirm(fig, 'No board found. Use the emulator (the firmware''s own code on this PC)?', ...
                    'Connect', 'Options', {'Emulator', 'Cancel'}, 'DefaultOption', 1);
                if strcmp(sel, 'Emulator'), onEmulator(); end
                return;
            end
            port = B.ports{1};
            if numel(B.ports) > 1        % more than one candidate (Windows/macOS without a name match): ask
                sel = uiconfirm(fig, 'Which port is the board?', 'Connect', 'Options', [B.ports(:)' {'Cancel'}], ...
                    'DefaultOption', 1, 'CancelOption', numel(B.ports) + 1);
                if strcmp(sel, 'Cancel'), return; end
                port = sel;
            end
        end
        connectTo(port);
    end

    function connectTo(port)
        try
            link.open(port, T.baud); link.stream(true); armOk = false;
            say(sprintf('Connected %s.', port), 'ok');
        catch err
            say(['Connect failed: ' err.message], 'warn');
        end
        setEnabled();
    end

    function onEmulator()
        if ~isempty(emu.pid), connectTo(emu.port); return; end
        if ispc   % the emulator talks through a pseudo-terminal: Linux and macOS only
            uialert(fig, ['The emulator needs a POSIX pseudo-terminal (Linux or macOS). On Windows, ' ...
                'simulate here and connect the real board.'], 'Emulator'); return;
        end
        try, exe = odyssix.stm32.emulatorBinary(); catch err, uialert(fig, err.message, 'Emulator'); return; end
        f = [tempname '.pty'];
        system(sprintf('"%s" --pty --parent %d > "%s" 2>&1 & echo $! > "%s.pid"', exe, feature('getpid'), f, f));
        for i = 1:50, if isfile(f) && ~isempty(strtrim(fileread(f))), break; end, pause(0.1); end
        emu.port = strtrim(fileread(f)); emu.pid = strtrim(fileread([f '.pid']));
        refreshPorts(); ui.port.Value = emu.port; connectTo(emu.port);
    end

    function send(c)
        if link.isOpen(), try, link.key(c); catch err, say(['send failed: ' err.message], 'warn'); end, end
    end

    function doAbort()
        if hwRun.on, finishRun('ABORTED: OPERATOR'); end
        hwRun.on = false; if link.isOpen(), link.abort(); end
    end
    function onKey(e), if any(strcmp(e.Key, {'escape', 'space'})), doAbort(); end, end

    function onArm()
        if ~armOk
            msg = sprintf(['ARM energises the stepper (it holds; it does not move yet).\n\n' ...
                '•  12 V switch within reach\n•  arm sweep clear for a half turn either way\n' ...
                '•  ABORT here, Esc or Space%s'], ternary(isUp(), sprintf('\n•  upright: two people'), ''));
            sel = uiconfirm(fig, msg, 'ARM', 'Options', {'ARM', 'Cancel'}, 'DefaultOption', 2, ...
                'CancelOption', 2, 'Icon', 'warning');
            if ~strcmp(sel, 'ARM'), return; end
            armOk = true;
        end
        send('a');
    end
    function armNow(), armOk = true; send('a'); end

    % =================================================================== rig: runs
    function onRunRig()
        M = MIS(mis);
        if strcmp(M.tag, 'LAB') && startsWith(lab.ctrl, 'Energy')        % RUN = SWING with the target
            onPendulumTarget(ui.ptarget.Value, false); return;
        end
        if strcmp(M.tag, 'LAB') && cfg.exp ~= labExp()          % e.g. after a swing-up
            cfg = odyssix.sim.defaults(labExp()); cfg.seq = 0;
        end
        if ~gateOk(), return; end
        readControls();
        H = []; clearTrace('rig'); replay = []; clearTrace('replay');
        if M.exp == 1
            link.sendLine(sprintf('move=%.4f', cfg.step));
            hwRun = idleRun(); hwRun.on = true; hwRun.i0 = link.n + 1; hwRun.cfg = cfg; hwRun.seq = 1; hwRun.t0 = tic;
            hwRun.label = runLabel(); ui.rec.Visible = 'on'; say('Arm out and back.', 'ok'); return;
        end
        c = cfg;
        c = rmfield(c, intersect(fieldnames(c), {'target', 'target_t', 'target_end'}));
        startCfg(c, runLabel());
    end

    function pendTargetChanged()
        a = ui.ptarget.Value;
        if a >= 179, ui.swing.Text = 'SWING  →  180°';
        elseif a < 1, ui.swing.Text = 'SWING  →  0° (stop)';
        else, ui.swing.Text = sprintf('SWING  →  ±%.0f°', a); end
        if a > 2 && a < 179
            say(sprintf(['A pendulum can rest only hanging (0°) or upright (180°): to hold %.0f° still the arm would need ' ...
                'a constant acceleration (ωg²/ωr²)·tan %.0f° for ever. It will SWING to ±%.0f° and keep that height.'], a, a, a), 'ok');
        end
        if hwRun.on && isfield(hwRun.cfg, 'exp') && hwRun.cfg.exp == 24
            try, link.setLive('amp', a); hwRun.cfg.amp = a; logEvent('pendulum target', a);
                say(sprintf('LIVE  pendulum target %.0f°', a), 'ok');
            catch err, say(err.message, 'warn'); end
        end
    end

    function onPendulumTarget(amp, noPrompt)
        % energy control (exp 24): 180 swing up and balance, 0 < a < 180 swing to
        % +/-a, 0 stop the swing; live if a pendulum-target run is already going
        if nargin < 2, noPrompt = false; end
        ui.ptarget.Value = amp; pendTargetChanged();
        if hwRun.on && isfield(hwRun.cfg, 'exp') && hwRun.cfg.exp == 24, return; end   % changed live above
        if ~strcmp(MIS(mis).tag, 'LAB') || ~strcmp(lab.mode, 'hanging') || ~startsWith(lab.ctrl, 'Energy')
            selectLab('hanging', 'Energy (swing / swing-up)');
        end
        if hwRun.on, onStopRun(); t0 = tic; while hwRun.on && toc(t0) < 5, pause(0.1); drawnow; end, end
        showSwingPanel();
        if ~link.isOpen() || ~strcmp(link.state, 'RUNNING')
            simSwing(amp); say('Simulated. On the rig: CONNECT, ARM, START, then SWING.', 'ok'); return;
        end
        cfg = swingCfg(amp);
        if ~gateOk(), return; end
        if ~noPrompt && amp >= 179
            % the energy controller is only as good as its pendulum constant: on
            % 2026-10-21 the rig ran with 57.01 (Tutorial) while it measured 47.6-49.5
            rp = odyssix.rigParams().pendulum; off = abs(cfg.wg2 - rp.wg2) / rp.wg2 > 0.08;
            note = ''; opts = {'SWING UP', 'Cancel'};
            if off
                note = sprintf(['\n\n⚠  Pendulum constant in use: ωg² %.1f. This rig measured %.1f (%s).\n' ...
                    '   A wrong ωg² makes the pump overshoot the top. FREE SWING measures yours.'], cfg.wg2, rp.wg2, rp.source);
                opts = {sprintf('SWING UP with ωg² %.1f', rp.wg2), sprintf('SWING UP with %.1f', cfg.wg2), 'Cancel'};
            end
            sel = uiconfirm(fig, sprintf(['The arm swings the pendulum over the top and balances it.\n\n' ...
                '•  arm sweep up to about ±160°: clear the area\n•  the pendulum passes overhead: hands away\n' ...
                '•  ABORT any time; if it falls after the catch, the motor stops%s'], note), 'SWING UP', ...
                'Options', opts, 'DefaultOption', numel(opts), 'CancelOption', numel(opts), 'Icon', 'warning');
            if strcmp(sel, 'Cancel'), return; end
            if off && strcmp(sel, opts{1})
                cfg.wg2 = rp.wg2; setSlider(ui.L, 9.81 / (rp.wg2 * 0.6805));   % saved with the run's config
            end
        end
        H = []; clearTrace('rig');
        c = cfg; c = rmfield(c, intersect(fieldnames(c), {'target', 'target_t', 'target_end'}));
        startCfg(c, ternary(amp >= 179, 'swing-up', sprintf('pendulum-%03.0f', amp)));
    end

    function ok = gateOk()
        ok = false;
        if ~link.isOpen(), say('CONNECT first.', 'warn'); return; end
        if ~strcmp(link.state, 'RUNNING'), say('ARM, then START.', 'warn'); return; end
        if hwRun.on, say('A run is active.', 'warn'); return; end
        link.poll(); D0 = link.table();
        if isempty(D0) || height(D0) == 0, say('No data from the board yet.', 'warn'); return; end
        w = mod(D0.psi_deg(max(1, end - 24):end) + 180, 360) - 180;   % hanging angle: 360 = 0
        if isUp()
            if ~all(abs(abs(w) - 180) < 10)
                say(sprintf('Hold the pendulum UPRIGHT and still, then RUN (reads %.0f°).', w(end)), 'warn'); return;
            end
        elseif any(cfg.exp == [21 24]) || strcmp(MIS(mis).tag, 'LAB')
            if ~all(abs(w) < 60), say('Pendulum far from its datum: let it hang, ZERO DATUMS.', 'warn'); return; end
            if cfg.exp == 24 && cfg.amp >= 1 && ~all(abs(w) < 5), say('Let the pendulum hang still before SWING.', 'warn'); return; end
            if cfg.exp == 24 && cfg.amp < 1, ok = true; return; end              % stop a swing: any swing
        elseif ~all(abs(w) < 10)
            say(sprintf('Let the pendulum hang still (reads %.1f°); ZERO DATUMS if needed.', w(end)), 'warn'); return;
        end
        ok = true;
    end

    function startCfg(c, label)
        if c.exp >= 6 && link.protocol < 4
            say(sprintf('Board speaks protocol %d: flash firmware 2.2.0.', link.protocol), 'warn'); return;
        end
        ok = false;
        for attempt = 1:2
            try, link.configure(c); catch err, say(err.message, 'warn'); return; end
            t0 = tic;
            while toc(t0) < 1.5, ok = cfgMatches(link.cfg, c, link.protocol); if ok, break; end, pause(0.05); link.poll(); end
            if ok, break; end
        end
        if ~isempty(link.lastError), say(['Rejected: ' link.lastError], 'warn'); return; end
        if ~ok, say('The board did not confirm the configuration. Not starting.', 'warn'); return; end
        i0 = link.n + 1;
        try, link.go(); catch, end
        hwRun = idleRun(); hwRun.on = true; hwRun.i0 = i0; hwRun.cfg = c; hwRun.t0 = tic; hwRun.label = label;
        hwRun.cfg.target = NaN; hwRun.cfg.target_t = NaN; hwRun.cfg.target_end = NaN;
        logEvent('go', c.exp);
        ui.rec.Visible = 'on';
        say(sprintf('RUN  %s  ·  %s  ·  recording', upper(label), ternary(link.emulator, 'EMULATOR', 'RIG')), 'ok');
    end

    function onStopRun()
        if link.isOpen() && hwRun.on, logEvent('stop', 0); link.stopRun(); end
    end

    function onGoto(v, instant)
        ui.target.Value = v;
        if ~hwRun.on
            if strcmp(MIS(mis).tag, 'LAB'), update(); end
            say('Not running: shown in simulation. RUN to do it on the rig.', 'ok'); return;
        end
        try
            link.setLive('rrate', ternary(instant, 0, 90)); pause(0.05); link.setRef(v);
        catch err, say(err.message, 'warn'); return; end
        t0 = tic; while toc(t0) < 1 && isnan(link.lastRef) && isempty(link.lastError), pause(0.05); link.poll(); end
        if isnan(link.lastRef), say('Set-point not accepted yet (upright: once it balances).', 'warn'); return; end
        D = link.table(); i0 = min(hwRun.i0, height(D));
        hwRun.cfg.target = v; hwRun.cfg.target_t = D.t_s(end) - D.t_s(i0);
        logEvent(ternary(instant, 'step', 'goto'), v);
        say(sprintf('ARM  →  %.1f°', v), 'ok');
    end

    function setParam(name, v)
        h = ui.(name);
        if isfield(h.UserData, 'fmt'), setSlider(h, v); else, h.Value = v; end
        if strcmp(name, 'div'), intSlider(h, 'div'); return; end
        paramChanged(name, true);
    end

    function paramChanged(name, immediate)
        if nargin < 2, immediate = false; end
        if hwRun.on && isfield(hwRun.cfg, 'exp') && hwRun.cfg.exp >= 6 && ...
                any(strcmp(name, {'kp', 'ki', 'kd', 'kpp', 'kdp', 'k1', 'k2', 'k3', 'k4', 'bv', 'uon', 'db', ...
                                  'ulim', 'fdr', 'fdp', 'div', 'ma'}))
            readControls();
            try
                link.setLive(name, cfg.(name)); hwRun.cfg.(name) = cfg.(name);
                logEvent(['live ' name], cfg.(name));
                say(sprintf('LIVE  %s = %g', name, cfg.(name)), 'ok');
            catch err
                say(err.message, 'warn');
            end
            return;                                   % keep the rig traces; no re-simulation mid-run
        end
        if immediate, update(); return; end
        % typing several values in a row re-simulates once, 0.25 s after the last
        stop(pending); start(pending);
    end

    function logEvent(what, val)
        D = link.table(); t = 0;
        if ~isempty(D) && height(D) >= hwRun.i0 && hwRun.i0 > 0, t = D.t_s(end) - D.t_s(hwRun.i0); end
        hwRun.events(end+1) = struct('t', t, 'what', what, 'value', val);
    end

    function onCrashes(C)
        % 500 Hz crash records (firmware 2.3.3): with the run while it lasts, else
        % with the run saved in the last 30 s (an abort's record arrives after the save)
        for ci = 1:numel(C)
            if hwRun.on
                hwRun.crashes{end+1} = C{ci};
                logEvent(['500 Hz record: ' C{ci}.reason], C{ci}.triggerTick);
            elseif ~isempty(lastSaved) && toc(savedT) < 30
                keepCrash(C{ci});
            else
                say('A 500 Hz record arrived outside a run; not saved.', 'warn');
            end
        end
    end

    function keepCrash(c)
        try
            R = odyssix.data.saveCrash(lastSaved, c, struct('firmware', firmwareLine(), 'rawLog', link.logFile));
            say(sprintf('500 Hz RECORD  %s  ·  %s', c.reason, R.id), 'ok');
        catch err
            say(['500 Hz record not saved: ' err.message], 'warn');
        end
    end

    function onPushMark()
        % the operator pushes the pendulum on purpose: mark it in the run and ask
        % the firmware for the 500 Hz record around it
        if ~link.isOpen(), say('PUSH MARK needs the rig.', 'warn'); return; end
        if hwRun.on, logEvent('push (operator)', 1); end
        try, link.markPush(); catch err, say(err.message, 'warn'); return; end
        say('PUSH MARKED  ·  500 Hz record of the last 1.5 s follows', 'ok');
    end

    function finishRun(result)
        if ~hwRun.on, return; end
        hwRun.on = false; ui.rec.Visible = 'off';
        if isempty(H) || height(H) < 5, return; end
        m = metricsOf(H);
        info = struct('exp', hwRun.cfg.exp, 'label', hwRun.label, 'synthetic', link.emulator, ...
            'cfg', hwRun.cfg, 'plant', pl, 'events', hwRun.events, 'metrics', m, 'result', result, ...
            'firmware', firmwareLine(), 'protocol', link.protocol, 'port', link.port, 'rawLog', link.logFile);
        try
            R = odyssix.data.saveRun(H, info); lastSaved = R.id; savedT = tic;
            for ci = 1:numel(hwRun.crashes), keepCrash(hwRun.crashes{ci}); end
            say(sprintf('SAVED  %s  ·  %s', R.id, result), 'ok');
        catch err
            say(['SAVE FAILED: ' err.message], 'warn');
        end
        fillTable(); drawAnalysis(); refreshRuns();
    end

    function s = firmwareLine()
        s = link.firmware;                    % kept by RigLink; the line buffer rolls over
    end

    function s = runLabel()
        M = MIS(mis);
        if strcmp(M.tag, 'LAB')
            s = sprintf('lab-%s-%s', ternary(strcmp(lab.mode, 'hanging'), 'hang', 'up'), lower(strrep(lab.ctrl, ' ', '')));
        else
            s = sprintf('%s-%s', M.tag, ui.preset.Value);
        end
    end

    % =================================================================== timer
    function onTick()
        try, tickBody(); catch err
            say(['internal: ' err.message], 'warn');
            fprintf(2, 'enr312_lab tick:\n%s\n', getReport(err, 'extended', 'hyperlinks', 'off'));
        end
    end

    function tickBody()
        if ~isvalid(fig), return; end
        if link.isOpen()
            try
                link.poll();
                try, link.keepAlive(); wrFail = 0;
                catch werr, wrFail = wrFail + 1; if wrFail >= 5, rethrow(werr); end
                end
            catch err
                say(['Link lost: ' err.message], 'warn'); if hwRun.on, finishRun('LINK LOST'); end
                link.close();
            end
            if link.isOpen() && link.crashPending > 0, onCrashes(link.takeCrashes()); end
            if link.n ~= lastN, lastN = link.n; dataT = tic;
            elseif toc(dataT) > 2, ui.stateChip.Text = 'NO DATA'; ui.stateChip.BackgroundColor = K.amber; return;
            end
        end
        setEnabled();
        if ~link.isOpen() || link.n == 0, return; end
        D = link.table(); k = height(D);
        if hwRun.on, rigProgress(D); end
        if recording.on && D.t_s(end) >= recording.tEnd, finishRecord(D); end
        if ~hwRun.on && ~recording.on
            odyssix.ui.rigPose(rig, D.rotor_deg(k), 180 - D.psi_deg(k), D.ref_deg(k), ui.L.Value / 0.258);
            ui.tTheta.Text = sprintf('%+7.2f°', D.rotor_deg(k));
            ui.tPend.Text = sprintf('%+7.2f°', mod(D.psi_deg(k) + 180, 360) - 180);
            ui.tU.Text = '—'; ui.tPhase.Text = link.state;
        end
        if link.n > 50 * 1200 && ~hwRun.on, link.clearData(); end
    end

    function rigProgress(D)
        i0 = min(hwRun.i0, height(D)); d = D(i0:end, :);
        if isempty(d), return; end
        t = d.t_s - d.t_s(1);
        if hwRun.cfg.exp == 1
            ph = zeros(height(d), 1); tMove = abs(hwRun.cfg.step) * (3200 / 360) / 200;
            ph(t >= tMove + 0.1 & t < 3.4) = 2;
            H = mkH(t, d, ph); drawTrace(H, 'rig'); poseAt(H, height(H));
            if hwRun.seq == 1 && toc(hwRun.t0) > 3.5
                link.sendLine(sprintf('move=%.4f', -hwRun.cfg.step)); hwRun.seq = 2; hwRun.t0 = tic;
            elseif hwRun.seq == 2 && toc(hwRun.t0) > 3.5
                finishRun('FINISHED');
            end
            return;
        end
        % samples before the board starts the run carry the previous run's
        % phase (the stream reports it while idle): mark them -1
        ph = d.phase; ph(d.run_exp == 0) = -1;
        H = mkH(t, d, ph);
        drawCount = drawCount + 1;
        if mod(drawCount, 2) == 0, drawTrace(H, 'rig'); end   % plots at 5 Hz, rig and numbers at 10 Hz
        poseAt(H, height(H));
        cue(H);
        ev = link.runEvent;
        if contains(ev, 'FINISHED') || contains(ev, 'ABORTED') || ~strcmp(link.state, 'RUNNING')
            res = 'FINISHED';
            if contains(ev, 'ABORTED'), res = ['ABORTED: ' strtrim(char(extractAfter(ev, 'reason=')))]; end
            if ~strcmp(link.state, 'RUNNING') && ~contains(ev, 'ABORTED'), res = ['ABORTED: ' link.state]; end
            finishRun(res);
        end
    end

    function X = mkH(t, d, ph)
        X = table(t, d.rotor_deg, d.psi_deg, mod(180 - d.psi_deg + 180, 360) - 180, d.u, d.ref_deg, ph, ...
            'VariableNames', {'t', 'rotor', 'psi', 'alpha', 'u', 'ref', 'phase'});
        X.Properties.UserData = struct('cfg', hwRun.cfg, 'phaseNames', {phaseList(hwRun.cfg.exp)});
    end

    function cue(X)
        p = X.phase(end); e = hwRun.cfg.exp;
        if e == 24
            if p == 11, say('SWINGING UP  ·  hands clear', 'go');
            elseif p == 8, say('CAUGHT  ·  balancing upright  ·  GO TO / tap / STOP', 'ok'); end
            return;
        end
        if ~any(e == [5 6 7 8 23]), return; end
        waiting = p == 1 && all(X.u(max(1, end - 4):end) == 0);
        if p == 0, say('HOLD IT UPRIGHT AND STILL', 'warn');
        elseif waiting
            say('LET GO NOW', 'go'); if ~hwRun.beeped, beep; hwRun.beeped = true; end
        elseif p == 8, say('BALANCING  ·  GO TO / tap / live gains  ·  STOP to end', 'ok');
        elseif p >= 2 && e ~= 5 || (e == 5 && p >= 1), say('BALANCING  ·  hands off', 'ok'); end
    end

    function setEnabled()
        on = link.isOpen(); st = link.state; if ~on, st = 'OFFLINE'; end
        cols = struct('SAFE', K.green, 'ARMED', K.amber, 'RUNNING', K.red, 'FAULT', K.red, 'OFFLINE', K.btn);
        if isfield(cols, st), c = cols.(st); else, c = K.btn; end
        ui.stateChip.Text = ternary(strcmp(st, 'RUNNING') && hwRun.on, 'RUN ACTIVE', ternary(on, st, '—')); ui.stateChip.BackgroundColor = c;
        if on, ui.linkChip.Text = ternary(link.emulator, 'EMULATOR', 'RIG'); ui.linkChip.BackgroundColor = ternary(link.emulator, K.violet, K.cyanDim);
        else, ui.linkChip.Text = 'OFFLINE'; ui.linkChip.BackgroundColor = K.btn; end
        ui.fw.Text = ternary(on, sprintf('protocol %d  ·  %s', link.protocol, link.port), 'simulation');
        ui.connect.Text = ternary(on, 'DISCONNECT', 'CONNECT');
        en = @(h, c_) set(h, 'Enable', onoff(c_));
        run_ = on && strcmp(st, 'RUNNING');
        en(ui.arm, on && strcmp(st, 'SAFE')); en(ui.start, on && strcmp(st, 'ARMED'));
        en(ui.run, run_ && ~hwRun.on); en(ui.stopRun, on && hwRun.on); en(ui.zero, on && ~hwRun.on);
        live = ~hwRun.on || (isfield(hwRun.cfg, 'exp') && any(hwRun.cfg.exp == [6 7 8 9 10 21 22 23 24]));
        en(ui.goto, live); en(ui.stepBtn, live); en(ui.home, live);
        pend = ~hwRun.on || (isfield(hwRun.cfg, 'exp') && hwRun.cfg.exp == 24);
        en(ui.swing, pend); en(ui.pstop, pend); en(ui.ptarget, pend); en(ui.fitBtn, on && any(strcmp(st, {'SAFE', 'FAULT'})) && ~recording.on);
        en(ui.useFit, true);                                        % fresh fit, else the rig's measured values
        ui.sessionLbl.Text = ternary(session.step > 0, sprintf('STEP %d / %d', session.step, size(sessionPlan(), 1)), '');
    end

    % =================================================================== free swing (A4)
    function onRecord()
        D = link.table(); if isempty(D), return; end
        recording = struct('on', true, 'i0', height(D) + 1, 'tEnd', D.t_s(end) + 15);
        ui.rec.Visible = 'on'; say('RECORDING 15 s  ·  displace 10-20° and let go', 'go');
    end

    function finishRecord(D)
        recording.on = false; ui.rec.Visible = 'off';
        d = D(min(recording.i0, height(D)):end, :);
        if height(d) < 100 || max(d.psi_deg) - min(d.psi_deg) < 4, say('Not enough swing (> 4° needed).', 'warn'); return; end
        fitRes = pendulum_free_swing_fit(d.t_s, d.psi_deg);
        try, fs = odyssix.pend.freeSwing(d.t_s, d.psi_deg, 10); catch, fs = struct(); end
        fitRes.pend = fs;
        z = zeros(height(d), 1);
        X = table(d.t_s - d.t_s(1), d.rotor_deg, d.psi_deg, mod(180 - d.psi_deg + 180, 360) - 180, z, z, z, ...
            'VariableNames', {'t', 'rotor', 'psi', 'alpha', 'u', 'ref', 'phase'});
        m = struct('wg2_fit', fitRes.wg2, 'Q_fit', fitRes.Q, 'coulomb_fit', fitRes.coulomb, 'rms_fit_deg', fitRes.rmsDeg, ...
                   't_release_s', fitRes.tStart - d.t_s(1));
        if isfield(fs, 'T'), m.period_s = fs.T; m.L_simple_m = fs.Lsimple; m.L_rod_predicted_m = fs.LrodPredicted; m.zeta = fs.zeta; end
        try
            R = odyssix.data.saveRun(X, struct('exp', 1, 'label', 'free-swing', 'synthetic', link.emulator, ...
                'metrics', m, 'result', 'RECORDED', 'firmware', firmwareLine(), 'protocol', link.protocol, ...
                'port', link.port, 'rawLog', link.logFile));
            lastSaved = R.id;
        catch err
            say(['SAVE FAILED: ' err.message], 'warn');
        end
        say(sprintf('FREE SWING  released at %.1f s  ·  ωg² %.2f  ·  dry friction %.2f rad/s²  ·  fit rms %.2f°  ·  saved', ...
            fitRes.tStart - d.t_s(1), fitRes.wg2, fitRes.coulomb, fitRes.rmsDeg), 'ok');
        if MIS(mis).exp == 1, drawAnalysis(); end
        refreshRuns();
    end

    function onUseFit()
        % wg2 and the dry friction from the free swing. A small swing cannot see the
        % viscous part when dry friction dominates (fit Q very large): then Q stays.
        if isempty(fitRes)                                          % no fresh free swing: the documented one
            rp = odyssix.rigParams().pendulum;
            measured = struct('wg2', rp.wg2, 'coulomb', rp.coulomb, 'Q', mean(rp.QLargeSwing));
        else
            measured = struct('wg2', fitRes.wg2, 'coulomb', getf(fitRes, 'coulomb'), 'Q', NaN);
            if isfinite(fitRes.Q) && fitRes.Q < 200, measured.Q = fitRes.Q; end
        end
        pl = basePlant(max(MIS(mis).exp, 2)); physicsToSliders();
        update(); say(sprintf('Simulation and swing-up now use the measured pendulum: ωg² %.2f, dry friction %.2f rad/s².', ...
            measured.wg2, measured.coulomb), 'ok');
    end

    function p = basePlant(e)
        p = odyssix.sim.plant(e);
        if ~isempty(measured)
            p.wg2 = measured.wg2; p.coulomb = measured.coulomb;
            if ~isnan(measured.Q), p.Q = measured.Q; end
        end
    end

    function onLqr()
        q = str2num(ui.lqrQ.Value); r = ui.lqrR.Value; %#ok<ST2NM>
        readControls();
        if cfg.exp == 10, A = [0 1; 0 -ui.bv.Value]; Bm = [0; 1];
        else, [A, Bm] = odyssix.ctrl.pendulumModel('inverted', pl); end
        if numel(q) ~= size(A, 1), say(sprintf('Q needs %d weights.', size(A, 1)), 'warn'); return; end
        try, Kk = odyssix.ctrl.lqr(A, Bm, diag(q), r); catch err, say(err.message, 'warn'); return; end
        nm = {'k1', 'k2', 'k3', 'k4'};
        for i = 1:numel(Kk), setSlider(ui.(nm{i}), Kk(i)); end
        if hwRun.on, for i = 1:numel(Kk), paramChanged(nm{i}); end, else, update(); end
        say(sprintf('LQR  K = [%s]', strtrim(num2str(Kk, '%.4g  '))), 'ok');
    end

    % =================================================================== runs, replay, session
    function refreshRuns()
        try, Tn = odyssix.data.listRuns(); catch, Tn = table(); end
        if isempty(Tn), ui.runs.Data = cell(0, 3); ui.runs.UserData = {}; return; end
        switch ui.runsFilter.Value
            case 'this mission'
                if strcmp(MIS(mis).tag, 'LAB'), keep = startsWith(Tn.label, ["lab", "swing"]);
                else, keep = Tn.experiment == sprintf('EXP%03d', MIS(mis).exp); end
                Tn = Tn(keep, :);
            case 'hardware only', Tn = Tn(Tn.data_class == "HARDWARE", :);
        end
        % rig runs first (newest first), then emulator runs, which are marked
        hw = Tn.data_class == "HARDWARE"; Tn = [Tn(hw, :); Tn(~hw, :)];
        Tn = Tn(1:min(height(Tn), 120), :);
        res = cellstr(Tn.result); syn = Tn.data_class ~= "HARDWARE";
        res(syn) = strcat('EMULATOR · ', res(syn));
        ui.runs.Data = [cellstr(Tn.run_id), res, cellstr(Tn.key_metrics)];
        ui.runs.UserData = cellstr(Tn.run_id);
    end

    function onPickRun(e)
        % selecting a run only selects it; OVERLAY RUN draws it, PLAY replays it
        if isempty(e.Indices), return; end
        ui.runs.Tag = ui.runs.UserData{e.Indices(1, 1)};
        say(sprintf('Selected %s  ·  OVERLAY RUN to compare, then ▶ PLAY', ui.runs.Tag), 'ok');
    end
    function onOverlay()
        if isempty(ui.runs.Tag), say('Select a run in the list first.', 'warn'); return; end
        loadReplay(ui.runs.Tag);
    end

    function loadReplay(id)
        try, [D, M] = odyssix.data.loadRun(id); catch err, say(err.message, 'warn'); return; end
        for f = {'ref', 'u', 'phase'}
            if ~ismember(f{1}, D.Properties.VariableNames), D.(f{1}) = zeros(height(D), 1); end
        end
        c = cfg; if isfield(M, 'config') && isstruct(M.config) && isfield(M.config, 'exp'), c = M.config; end
        D.Properties.UserData = struct('cfg', c, 'phaseNames', {phaseList(getf(c, 'exp'))});
        if startsWith(getf(M, 'label', ''), 'free-swing')          % fit it now (the stored numbers may predate the current fit)
            try, fitRes = pendulum_free_swing_fit(D.t, D.psi); catch, end
        end
        replay = D; drawTrace(D, 'replay'); fillTable(); drawAnalysis();
        nK = drawRecords(id, D);
        player.D = D; player.kind = 'replay'; player.t = D.t(1); player.playing = false; ui.play.Text = '▶  PLAY';
        ui.scrub.Limits = [D.t(1), max(D.t(end), D.t(1) + 0.01)]; ui.scrub.Value = D.t(1);
        say(sprintf('Overlaid %s  ·  %s%s  ·  ▶ PLAY', regexprep(id, '^EXP\d+_\d{8}-(\d{2})(\d{2})\d{2}_', '$1:$2 '), getf(M, 'result', ''), ...
            ternary(nK > 0, sprintf('  ·  %d record(s) at 500 Hz (dots)', nK), '')), 'ok');
    end

    function n = drawRecords(id, D)
        % the run's 500 Hz records, as dots on the pendulum plot at their place in the run
        set(tr.pK, 'XData', nan, 'YData', nan); n = 0;
        try, Kr = odyssix.data.loadRecords(id, D); catch, return; end
        x = []; y = [];
        for r = Kr
            if r.fit > 2, continue; end               % placement not trustworthy: leave it out
            x = [x; r.D.t; nan]; y = [y; pendView(r.D); nan]; n = n + 1; %#ok<AGROW>
        end
        if n > 0, set(tr.pK, 'XData', x, 'YData', y); end
    end

    function plan = sessionPlan()
        plan = {1, 'First motion +5 deg'; -1, ''; 2, ''; 3, ''; 4, ''; 5, ''; 6, ''; 7, ''; 8, ''; ...
                9, ''; 10, ''; 0, 'hanging|PID'; 0, 'hanging|On-off'; 0, 'upright|LQR'; 0, 'swing|'};
    end

    function nextSession()
        if hwRun.on, say('Stop the run first.', 'warn'); return; end
        plan = sessionPlan();
        session.step = mod(session.step, size(plan, 1)) + 1; s = plan(session.step, :);
        if s{1} > 0
            selectMission(s{1}); if ~isempty(s{2}), setPreset(s{2}); end
        elseif s{1} == -1
            selectMission(1); say('FREE SWING  ·  motor SAFE  ·  press FREE SWING, release from 15°', 'go');
        else
            parts = split(s{2}, '|');
            if strcmp(parts{1}, 'swing'), selectLab('hanging'); say('SWING UP  ·  ARM, START, then SWING UP', 'go');
            else, selectLab(parts{1}, parts{2}); end
        end
        setEnabled();
    end

    % =================================================================== helpers
    function r = next(h), row = row + 1; L.RowHeight{row} = h; r = row; end
    function head(txt)
        h = uilabel(L, 'Text', txt, 'FontSize', 10.5, 'FontWeight', 'bold', 'FontColor', K.dim, 'VerticalAlignment', 'bottom');
        place(h, next(24), [1 2]);
    end
    function h = note(txt, ht)
        h = uilabel(L, 'Text', txt, 'WordWrap', 'on', 'FontSize', 11.5, 'FontColor', K.text, 'VerticalAlignment', 'top');
        place(h, next(ht), [1 2]);
    end
    function h = btn(txt, fcn, cols, ht)
        h = uibutton(L, 'Text', txt, 'ButtonPushedFcn', fcn, 'FontWeight', 'bold');
        place(h, next(ht), cols);
    end
    function s = slider(key, txt, lims, fmt_)
        % one row: name on the left, a number field on the right (type, or use
        % the arrow keys); the value is applied when the field is left
        l = uilabel(L, 'Text', txt, 'FontSize', 11.5, 'FontColor', K.text); place(l, next(26), 1); r1 = row;
        s = uieditfield(L, 'numeric', 'Limits', lims, 'Value', lims(1), 'ValueDisplayFormat', fmt_, ...
            'FontName', K.mono, 'FontSize', 12.5, 'HorizontalAlignment', 'right', ...
            'BackgroundColor', K.field, 'FontColor', K.cyan, 'Tooltip', sprintf('%g … %g', lims(1), lims(2)));
        place(s, row, 2);
        s.UserData = struct('fmt', fmt_, 'name', l, 'rows', r1, 'key', key);
        s.ValueChangedFcn = @(~, ~) paramChanged(key);
    end
    function showSlider(s, v)
        u = s.UserData; L.RowHeight{u.rows(1)} = 26 * v;
        set([u.name s], 'Visible', onoff(v));
    end
    function setSlider(s, v)
        s.Value = min(max(v, s.Limits(1)), s.Limits(2));
    end
    function intSlider(s, key)
        if strcmp(key, 'div'), setSlider(s, 500 / max(1, min(50, round(500 / s.Value))));
        else, setSlider(s, round(s.Value)); end
        paramChanged(key);
    end
    function ax = mkAx(parent, ttl)
        ax = uiaxes(parent); styleAx(ax); hold(ax, 'on'); title(ax, ttl);
    end
    function styleAx(ax)
        ax.Color = K.panel; ax.XColor = K.dim; ax.YColor = K.dim; ax.GridColor = K.line; ax.GridAlpha = 1;
        ax.FontSize = 10; ax.Title.Color = K.text; ax.Title.FontWeight = 'bold'; ax.Title.FontSize = 10.5;
        ax.TitleHorizontalAlignment = 'left'; grid(ax, 'on'); box(ax, 'off');
        try, ax.Toolbar.Visible = 'off'; catch, end
        ax.BackgroundColor = K.bg;
    end
    function h = lbl(parent, txt, sz, col, wt)
        h = uilabel(parent, 'Text', txt, 'FontSize', sz, 'FontColor', col, 'FontWeight', wt);
    end
    function h = chip(parent, txt)
        h = uilabel(parent, 'Text', txt, 'FontSize', 12, 'FontWeight', 'bold', 'FontColor', 'w', ...
            'HorizontalAlignment', 'center', 'BackgroundColor', K.btn);
    end
    function h = big(parent, col)
        h = uilabel(parent, 'Text', '—', 'FontSize', ternary(small, 19, 26), 'FontWeight', 'bold', 'FontColor', col, 'FontName', K.mono);
    end
    function styleButtons(f)
        b = findall(f, 'Type', 'uibutton');
        for i = 1:numel(b)
            if all(b(i).BackgroundColor > 0.85) || all(b(i).BackgroundColor < 0.35 & b(i).BackgroundColor > 0.2)
                b(i).BackgroundColor = K.btn; b(i).FontColor = K.text;
            end
        end
        t = findall(f, 'Type', 'uitogglebutton');
        for i = 1:numel(t), t(i).BackgroundColor = K.btn; t(i).FontColor = K.text; t(i).FontWeight = 'bold'; end
    end
    function say(txt, kind)
        if ~isvalid(ui.say), return; end
        ui.say.Text = txt;
        switch kind
            case 'warn', ui.say.FontColor = K.amber;
            case 'go',   ui.say.FontColor = K.orange;
            otherwise,   ui.say.FontColor = K.text;
        end
    end
    function n = phaseName(D, p)
        n = ''; u = D.Properties.UserData;
        if isstruct(u) && isfield(u, 'phaseNames') && p + 1 >= 1 && p + 1 <= numel(u.phaseNames), n = u.phaseNames{p + 1};
        elseif isa(u, 'struct') && isfield(u, 'cfg'), names_ = phaseList(getf(u.cfg, 'exp')); if p + 1 >= 1 && p + 1 <= numel(names_), n = names_{p + 1}; end
        end
    end
    function r = getS(), r = S; end
    function r = getMission(), r = MIS(mis); end
    function r = getH(), r = H; end
    function r = getFit(), r = fitRes; end
    function r = getRigCfg(), r = hwRun.cfg; end
    function r = getLastSaved(), r = lastSaved; end
    function onClose()
        try, stop(tick); delete(tick); catch, end
        try, stop(player.timer); delete(player.timer); catch, end
        try, stop(pending); delete(pending); catch, end
        if hwRun.on, try, finishRun('ABORTED: WINDOW CLOSED'); catch, end, end
        try, link.close(); catch, end
        if ~isempty(emu.pid), system(['kill ' emu.pid ' 2>/dev/null']); end
        delete(fig);
    end
end

% ======================================================================= data
function M = missions()
%MISSIONS  The ten ENR312 tutorials and LAB, one line each.
    m = @(tag, exp, title, brief, next, presets, metrics, pm) struct('tag', tag, 'exp', exp, 'title', title, ...
        'brief', brief, 'next', next, 'presets', {presets}, 'metrics', {metrics}, 'pm', pm, ...
        'short', strtrim(extractAfter(title, '·')));
    M = m('T1', 1, 'T1 · Actuator', 'Open loop: the stepper moves exact microsteps; the hanging pendulum is kicked at start and stop.', ...
        'RUN moves the arm out and back.', ...
        {'First motion +5 deg', struct('step', 5); 'Larger move +20 deg', struct('step', 20); 'Small move +1 deg', struct('step', 1)}, ...
        {'rotor_after_move_deg', 'arm after move (°)', '= step ± 0.11'; 'pend_swing_pp_deg', 'pendulum swing p-p (°)', ''}, '');
    M(2) = m('T2', 2, 'T2 · Sensitivity', 'Rotor PD, pendulum clamped. Reference step and load disturbance: T(s) and S_D(s).', ...
        'Offset after the load step = D/Kp.', ...
        {'Kp 5, Kd 2.5', struct('kp', 5, 'kd', 2.5); 'Kp 6.55, Kd 4', struct('kp', 6.55, 'kd', 4, 'step', 1.5); 'Kp 1, Kd 1', struct('kp', 1, 'kd', 1)}, ...
        {'overshoot_pct', 'overshoot (%)', '26.8'; 'settling_s', 'settling (s)', '3.24'; 'dist_offset_deg', 'load offset (°)', 'D/Kp'}, '');
    M(3) = m('T3', 3, 'T3 · Effort', 'Hanging, dual PD. Lower rotor gains cost less effort and respond slower.', ...
        'Compare CE_total between designs.', ...
        {'Design 1  Kp 6, Kd 4.8', struct('kp', 6, 'kd', 4.8); 'Design 2  Kp 1.5, Kd 1.725', struct('kp', 1.5, 'kd', 1.725); 'Design 3  Kp 0.3, Kd 0.75', struct('kp', 0.3, 'kd', 0.75)}, ...
        {'overshoot_pct', 'overshoot (%)', 'D1 32.4'; 'settling_s', 'settling (s)', 'D1 2.10'; 'ce_total', 'CE_total (deg/s)', '10.9 / 3.78 / 1.65'}, '');
    M(4) = m('T4', 4, 'T4 · MIMO S(s)', 'Hanging. How close does L(jω) come to −1? M_S = 1 / closest approach.', ...
        'Design A: M_S < 1 dB, B: < 3 dB.', ...
        {'Reference  Kp 6, Kd 4.8', struct('kp', 6, 'kd', 4.8); 'Design A  Kp 1.2, Kd 1.5', struct('kp', 1.2, 'kd', 1.5); 'Design B  Kp 0.25, Kd 4.8', struct('kp', 0.25, 'kd', 4.8)}, ...
        {'overshoot_pct', 'overshoot (%)', ''; 'settling_s', 'settling (s)', ''; 'pend_end_deg', 'pendulum at end (°)', '0'}, '');
    M(5) = m('T5', 5, 'T5 · Inverted', 'Upright, two people. The arm first moves the wrong way: right-half-plane zero.', ...
        'Hold it upright, RUN, let go when told.', ...
        {'System 1  Kp 9, Kd 9', struct('kp', 9, 'kd', 9); 'System 2  Kp 10, Kd 3.33', struct('kp', 10, 'kd', 3.33); 'Design A  Kp 6.25, Kd 7', struct('kp', 6.25, 'kd', 7); 'Design B  Kp 0.5, Kd 10.75', struct('kp', 0.5, 'kd', 10.75)}, ...
        {'undershoot_pct', 'wrong-way undershoot (%)', '≈ −33'; 'overshoot_pct', 'overshoot (%)', ''; 'alpha_peak_deg', 'α peak (°)', '< 15'}, '47.3');
    M(6) = m('T6', 6, 'T6 · Integral', 'Upright, rotor PID. Ki removes offsets; too much Ki costs phase margin.', ...
        'Predicted 34 % overshoot on the rig (saturation); 52.6 % linear.', ...
        {'Tutorial 6  Kp 15, Ti 5, Td 0.5', struct(); 'No integral', struct('ki', 0); 'Ti 2 s', struct('ki', 7.5)}, ...
        {'overshoot_pct', 'overshoot (%)', '52.6 linear'; 'settling_s', 'settling 5 % (s)', '3.1 linear'; 'undershoot_pct', 'wrong-way (%)', '< 0'; 'alpha_rms_deg', 'α rms (°)', ''}, '31.45');
    M(7) = m('T7', 7, 'T7 · Pendulum PD', 'Upright. Eight 10° reference impulses on the pendulum, averaged.', ...
        'Design Kp, Kd pendulum; 150/15 falls.', ...
        {'300 / 30', struct(); '600 / 50', struct('kpp', 600, 'kdp', 50); '200 / 20', struct('kpp', 200, 'kdp', 20); '150 / 15 (falls)', struct('kpp', 150, 'kdp', 15)}, ...
        {'pend_peak_deg', 'pendulum peak (°)', '−1.4'; 'pend_settling_s', 'pendulum settling (s)', '1.9'; 'rotor_peak_deg', 'arm peak (°)', '4.8'}, '');
    M(8) = m('T8', 8, 'T8 · Disturbance', 'Upright. Step, then a 60 deg/s² load: offset −D/Kp without Ki, 0 with.', ...
        'Compare Ki 7.5 and Ki 0.', ...
        {'Tutorial 8  Kp 15, Ti 2, Td 0.5', struct(); 'No integral', struct('ki', 0); 'Load 90', struct('dist', 90)}, ...
        {'overshoot_pct', 'overshoot (%)', ''; 'ld_peak_deg', 'load peak (°)', ''; 'ld_final_deg', 'offset under load (°)', '0 with Ki'}, '');
    M(9) = m('T9', 9, 'T9 · Poles', 'Hanging, state feedback: k1 = ωN², k2 = 2ζωN.', ...
        'Reference settles in 5.8 s.', ...
        {'ωN 1, ζ 1  K [1 2]', struct(); 'ωN 2, ζ 0.2  K [4 0.8]', struct('k1', 4, 'k2', 0.8); '16 % OS, 4 s  K [3.94 2]', struct('k1', 3.94, 'k2', 2)}, ...
        {'overshoot_pct', 'overshoot (%)', ''; 'settling_s', 'settling (s)', '5.8'; 'final_value_deg', 'final (°)', '20'}, '');
    M(10) = m('T10', 10, 'T10 · LQR', 'Hanging. Choose Q and R, press LQR: smaller R = faster, more effort.', ...
        'Tutorial 10: Q = I, R = 1 → K = [1 1.7321].', ...
        {'Q I, R 1  K [1 1.7321]', struct(); 'b 2  K [1 0.6458]', struct('k2', 0.6458, 'bv', 2); 'R 0.1  K [3.16 4.04]', struct('k1', 3.1623, 'k2', 4.0404)}, ...
        {'overshoot_pct', 'overshoot (%)', ''; 'settling_s', 'settling (s)', ''; 'final_value_deg', 'final (°)', '20'}, '');
    M(11) = m('LAB', 21, 'LAB · Free', 'Hanging or upright, any controller. GO TO, STEP, tap, live gains, SWING UP.', ...
        'RUN, then drive it.', {'-', struct()}, {}, '');
end

function K = palette()
    K = struct('bg', [0.043 0.051 0.067], 'panel', [0.071 0.082 0.106], 'field', [0.10 0.115 0.145], ...
        'btn', [0.13 0.145 0.18], 'line', [0.20 0.22 0.27], 'text', [0.90 0.92 0.95], 'dim', [0.52 0.56 0.63], ...
        'cyan', [0.00 0.82 0.96], 'cyanDim', [0.00 0.45 0.58], 'orange', [1.00 0.48 0.12], ...
        'orangeDim', [0.70 0.30 0.05], 'green', [0.16 0.70 0.38], 'red', [0.86 0.16 0.18], ...
        'amber', [1.00 0.72 0.12], 'violet', [0.62 0.48 1.00], 'ghost', [0.42 0.45 0.52], ...
        'mono', 'Monospaced');
end

function h = idleRun()
    h = struct('on', false, 'i0', 0, 'cfg', struct(), 'seq', 0, 't0', tic, 'label', '', ...
               'events', struct('t', {}, 'what', {}, 'value', {}), 'beeped', false, 'crashes', {{}});
end

function n = phaseList(exp)
    if isempty(exp) || ~isnumeric(exp) || isnan(exp), exp = 0; end
    if exp >= 6
        n = {'WAIT_CAPTURE', 'WAIT_RELEASE', 'BALANCE', 'STEP', 'STEP_BACK', 'DIST', 'DIST_OFF', ...
             'IMPULSES', 'HOLD', 'IDLE', 'REGULATE', 'SWINGUP', 'DONE', 'ABORTED'};
    elseif exp == 5, n = {'WAIT_CAPTURE', 'BALANCE', 'STEP', 'SETTLE', 'HOLD', 'ABORTED'};
    elseif exp == 2, n = {'IDLE', 'REF_STEP', 'REF_SETTLE', 'DIST_STEP', 'DIST_SETTLE', 'DONE', 'ABORTED'};
    else, n = {'IDLE', 'STEP', 'SETTLE', 'DONE', 'ABORTED'};
    end
end

function ok = cfgMatches(c, want, protocol)
%CFGMATCHES  The board's '$cfg' echo equals the requested configuration.
    ok = isstruct(c) && isfield(c, 'exp') && c.exp == want.exp;
    f = {'kp', 'kd', 'kpp', 'kdp', 'step', 'dist', 'ulim', 'vmax'};
    if want.exp >= 6, f = [f, odyssix.stm32.RigLink.KEYS3]; end
    if want.exp >= 6 && protocol >= 4, f = [f, odyssix.stm32.RigLink.KEYS4]; end
    if want.exp >= 6 && protocol >= 5, f = [f, odyssix.stm32.RigLink.KEYS5]; end
    for i = 1:numel(f)
        if ~ok, return; end
        ok = isfield(c, f{i}) && isfield(want, f{i}) && abs(c.(f{i}) - want.(f{i})) <= 1e-3 * max(1, abs(want.(f{i})));
    end
end

function v = getf(s, f, d)
    if nargin < 3, d = NaN; end
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
    if isstring(v), v = char(v); end
end
function s = fmt(v), if isempty(v) || ~isnumeric(v) || ~isfinite(v), s = '—'; else, s = sprintf('%.3g', v); end, end
function l = pad(l, m)
    if ~all(isfinite(l)), l = [-1 1]; end
    c = mean(l); h = max(diff(l) / 2 * 1.12, m / 2); l = c + [-h h];
end
function s = ternary(c, a, b), if c, s = a; else, s = b; end, end
function s = onoff(c), s = matlab.lang.OnOffSwitchState(logical(c)); end
function place(h, r, c), h.Layout.Row = r; h.Layout.Column = c; end

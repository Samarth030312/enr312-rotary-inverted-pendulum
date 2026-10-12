function app = exp005_lab()
%EXP005_LAB  Interactive EXP005 (Tutorial 5) lab: balance the inverted pendulum.
%
%   addpath(genpath(fullfile(<repo>,'matlab'))); exp005_lab
%
%   Move a slider and every plot updates immediately; press RUN to watch the
%   rig respond in real time. Presets load the Tutorial 5 designs.
%
%   WHAT IS SIMULATED -- deliberately the same loop the ENR312 firmware runs
%   (firmware/enr312/src/enr312_exp005.c, enr312_pd.c), not an idealised one:
%     * 500 Hz sampling with the plant held constant between samples (ZOH)
%     * PD on the ERROR, derivative low-passed at fc (firmware default 10 Hz)
%     * outer (rotor) branch sign-inverted, u = -PD_rotor + PD_pend
%     * u = rotor acceleration command, clipped at +/-1500 deg/s^2
%     * encoder quantised to 0.15 deg (600 PPR x4), rotor to 0.1125 deg/microstep
%     * abort when |pendulum| > 15 deg (EXP005_PENDULUM_ABORT_DEG)
%   The PLANT is the linear Tutorial 5 model, identical to
%   matlab/models/exp005_inverted_model.m (checked at start-up).
%
%   WHAT IS NOT SIMULATED is listed in the app's "Model limits" panel and in
%   limitsText() below. Read it before trusting a result on hardware.
%
%   Returns a struct of handles so a script can drive it (see exp005_lab_tour).
%   Base MATLAB only.

    P = defaults();
    selfCheck(P);

    % ================================================================ layout
    fig = uifigure('Name', 'ENR312 EXP005 Lab', 'Position', [60 40 1680 960], ...
                   'Color', [0.96 0.97 0.99]);
    if exist('theme', 'file'), theme(fig, 'light'); end
    g = uigridlayout(fig, [3 3], 'RowHeight', {64, '1x', 250}, ...
        'ColumnWidth', {350, '1.15x', '1x'}, 'Padding', [10 10 10 10], ...
        'RowSpacing', 8, 'ColumnSpacing', 10, 'BackgroundColor', [0.96 0.97 0.99]);

    hdr = uilabel(g, 'BackgroundColor', [0.09 0.16 0.29], 'FontColor', 'w', ...
        'FontSize', 24, 'FontWeight', 'bold', 'VerticalAlignment', 'center', ...
        'Text', ['   ENR312  ' char(183) '  EXP005  ' char(183) '  Balance the inverted pendulum' ...
                 '      Tutorial 5 ' char(183) ' STEVAL-EDUKIT01 rig ' char(183) ' firmware-in-the-loop simulation']);
    hdr.Layout.Row = 1; hdr.Layout.Column = [1 3];

    % ---------------------------------------------------------- controls
    cp = uipanel(g, 'Title', 'Controls', 'FontWeight', 'bold', 'FontSize', 14, ...
                 'BackgroundColor', 'w', 'Scrollable', 'on');
    cp.Layout.Row = [2 3]; cp.Layout.Column = 1;
    cg = uigridlayout(cp, [30 2], 'ColumnWidth', {'1x', 92}, 'RowSpacing', 2, ...
                      'Padding', [10 6 10 6], 'BackgroundColor', 'w', 'Scrollable', 'on');
    cg.RowHeight = repmat({0}, 1, 40);
    row = 0;
    function r = nextRow(h)
        row = row + 1; cg.RowHeight{row} = h; r = row;
    end

    ui = struct();
    section('Experiment');
    ui.preset = uidropdown(cg, 'Items', presetNames(), 'FontSize', 13, ...
        'ValueChangedFcn', @(~, ~) applyPreset());
    place(ui.preset, nextRow(28), [1 2]);
    ui.run = uibutton(cg, 'Text', char(9654) + "  RUN", 'FontSize', 16, 'FontWeight', 'bold', ...
        'BackgroundColor', [0.13 0.59 0.33], 'FontColor', 'w', 'ButtonPushedFcn', @(~, ~) animate());
    place(ui.run, nextRow(40), [1 2]);
    lab(cg, 'Playback speed', nextRow(24), 1);
    ui.speed = uidropdown(cg, 'Items', {'0.25x', '0.5x', '1x'}, 'Value', '1x');
    place(ui.speed, row, 2);
    lab(cg, '3-D view angle zoom', nextRow(24), 1);
    ui.zoom = uidropdown(cg, 'Items', {'1x', '2x', '4x', '8x'}, 'Value', '4x', ...
        'ValueChangedFcn', @(~, ~) drawRig(1));
    place(ui.zoom, row, 2);

    section('Your rotor controller (outer PD)');
    ui.Kp  = slider('Kp  rotor', [0 25], P.Kp, '%.2f');
    ui.Kd  = slider('Kd  rotor', [0 25], P.Kd, '%.2f');
    ui.inv = uicheckbox(cg, 'Text', 'Invert rotor branch (needed when inverted)', ...
        'Value', P.signInv, 'ValueChangedFcn', @(~, ~) update());
    place(ui.inv, nextRow(24), [1 2]);
    ui.encsign = uicheckbox(cg, 'Text', 'Pendulum encoder sign WRONG (bench mistake)', ...
        'Value', false, 'ValueChangedFcn', @(~, ~) update());
    place(ui.encsign, nextRow(22), [1 2]);

    section('Pendulum controller (inner PD, Tutorial-supplied)');
    ui.Kpp = slider('Kp  pendulum', [0 600], P.Kpp, '%.0f');
    ui.Kdp = slider('Kd  pendulum', [0 80],  P.Kdp, '%.1f');

    section('Test');
    ui.step = slider('Rotor step (deg)',        [0 10], P.step, '%.1f');
    ui.tilt = slider('Release tilt (deg)',      [0 6],  P.tilt, '%.1f');

    section('Rig physics (Tutorial 5 values)');
    ui.L = slider('Pendulum eff. length L (m)', [0.15 0.40], P.L, '%.3f');
    ui.Q = slider('Pivot quality factor Q',     [2 60],      P.Q, '%.0f');
    ui.nonlin = uicheckbox(cg, 'Text', 'Nonlinear physics (sin, cos, centrifugal)', ...
        'Value', true, 'ValueChangedFcn', @(~, ~) update());
    place(ui.nonlin, nextRow(22), [1 2]);

    section('Firmware realism');
    lab(cg, 'Control loop rate', nextRow(24), 1);
    ui.fs = uidropdown(cg, 'Items', {'500 Hz', '250 Hz', '100 Hz', '50 Hz'}, ...
        'Value', '500 Hz', 'ValueChangedFcn', @(~, ~) update());
    place(ui.fs, row, 2);
    ui.fc = slider('Derivative filter fc (Hz)', [1 50], P.fc, '%.0f');
    ui.clip = uicheckbox(cg, 'Text', 'Actuator limit +/-1500 deg/s^2', 'Value', true, ...
        'ValueChangedFcn', @(~, ~) update());
    place(ui.clip, nextRow(22), [1 2]);
    ui.quant = uicheckbox(cg, 'Text', 'Encoder / microstep quantisation', 'Value', true, ...
        'ValueChangedFcn', @(~, ~) update());
    place(ui.quant, nextRow(22), [1 2]);
    ui.reset = uibutton(cg, 'Text', 'Reset to System 1', 'ButtonPushedFcn', ...
        @(~, ~) setPreset('System 1 (stable, Tutorial 5)'));
    place(ui.reset, nextRow(30), [1 2]);

    % ---------------------------------------------------------- rig view
    rp = uipanel(g, 'Title', '', 'BackgroundColor', 'w', 'BorderType', 'none');
    rp.Layout.Row = 2; rp.Layout.Column = 2;
    rg = uigridlayout(rp, [3 1], 'RowHeight', {36, 54, '1x'}, 'Padding', [0 0 0 0], ...
                      'RowSpacing', 2, 'BackgroundColor', 'w');
    ui.badge = uilabel(rg, 'Text', '', 'FontSize', 16, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'FontColor', 'w');
    ui.caption = uilabel(rg, 'FontSize', 15, 'WordWrap', 'on', 'HorizontalAlignment', 'center', ...
        'FontColor', [0.09 0.16 0.29], 'BackgroundColor', [0.91 0.94 0.99], ...
        'Text', ['Move any slider: every plot updates instantly. Press RUN to watch the rig. ' ...
                 'The rotor first moves the WRONG way. Can you make that dip smaller?']);
    axR = uiaxes(rg); axR.Layout.Row = 3;
    rig = odyssix.ui.rigBuild(axR);
    text(axR, 0.10, -0.22, 0.0, 'dashed green = rotor reference', 'FontSize', 10, ...
         'Color', [0.13 0.59 0.33]);

    % ---------------------------------------------------------- plots
    pg = uigridlayout(g, [3 2], 'RowHeight', {'1x', '1x', '1x'}, 'ColumnWidth', {'1.6x', '1x'}, ...
        'Padding', [0 0 0 0], 'RowSpacing', 4, 'ColumnSpacing', 6, 'BackgroundColor', [0.96 0.97 0.99]);
    pg.Layout.Row = 2; pg.Layout.Column = 3;
    axT = uiaxes(pg); axT.Layout.Row = 1; axT.Layout.Column = [1 2];
    axA = uiaxes(pg); axA.Layout.Row = 2; axA.Layout.Column = [1 2];
    axU = uiaxes(pg); axU.Layout.Row = 3; axU.Layout.Column = 1;
    axP = uiaxes(pg); axP.Layout.Row = 3; axP.Layout.Column = 2;
    tr = buildTraces(axT, axA, axU, axP);

    % ---------------------------------------------------------- bottom
    ui.res = uilabel(g, 'Interpreter', 'html', 'VerticalAlignment', 'top', ...
        'BackgroundColor', 'w', 'FontSize', 13, 'WordWrap', 'on');
    ui.res.Layout.Row = 3; ui.res.Layout.Column = 2;
    lim = uilabel(g, 'Interpreter', 'html', 'VerticalAlignment', 'top', 'WordWrap', 'on', ...
        'BackgroundColor', [1.0 0.97 0.88], 'FontSize', 12, 'Text', limitsText());
    lim.Layout.Row = 3; lim.Layout.Column = 3;

    S = [];                         % last simulation
    busy = false;
    update();

    app = struct('fig', fig, 'ui', ui, 'set', @setParam, 'preset', @setPreset, ...
                 'run', @animate, 'result', @getResult, ...
                 'caption', @(txt) set(ui.caption, 'Text', txt));

    % ================================================================ nested
    function section(txt)
        h = uilabel(cg, 'Text', txt, 'FontWeight', 'bold', 'FontSize', 13, ...
                    'FontColor', [0.09 0.16 0.29], 'VerticalAlignment', 'bottom');
        place(h, nextRow(30), [1 2]);
    end

    function s = slider(txt, lims, val, fmt)
        l = lab(cg, txt, nextRow(20), 1);
        v = uilabel(cg, 'Text', sprintf(fmt, val), 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'right', 'FontColor', [0.13 0.40 0.75]);
        place(v, row, 2);
        s = uislider(cg, 'Limits', lims, 'Value', val, 'MajorTicks', [], 'MinorTicks', []);
        place(s, nextRow(26), [1 2]);
        s.UserData = struct('valueLabel', v, 'fmt', fmt, 'label', l);
        s.ValueChangingFcn = @(~, e) set(v, 'Text', sprintf(fmt, e.Value));
        s.ValueChangedFcn  = @(~, ~) update();
    end

    function setParam(name, val)
        c = ui.(name);
        if isa(c, 'matlab.ui.control.Slider')
            c.Value = val; c.UserData.valueLabel.Text = sprintf(c.UserData.fmt, val);
        else
            c.Value = val;
        end
        update();
    end

    function setPreset(name)
        ui.preset.Value = name; applyPreset();
    end

    function applyPreset()
        p = presetValues(ui.preset.Value);
        f = fieldnames(p);
        for i = 1:numel(f)
            c = ui.(f{i});
            c.Value = p.(f{i});
            if isa(c, 'matlab.ui.control.Slider')
                c.UserData.valueLabel.Text = sprintf(c.UserData.fmt, c.Value);
            end
        end
        update();
    end

    function p = readParams()
        p = defaults();
        p.Kp = ui.Kp.Value; p.Kd = ui.Kd.Value; p.signInv = ui.inv.Value;
        p.Kpp = ui.Kpp.Value; p.Kdp = ui.Kdp.Value;
        p.step = ui.step.Value; p.tilt = ui.tilt.Value;
        p.L = ui.L.Value; p.Q = ui.Q.Value;
        p.fs = sscanf(ui.fs.Value, '%f'); p.fc = ui.fc.Value;
        p.clip = ui.clip.Value; p.quant = ui.quant.Value;
        p.nonlinear = ui.nonlin.Value; p.encSignWrong = ui.encsign.Value;
    end

    function update()
        p = readParams();
        lm = linModel(p);
        S = simulate(p);
        S.lin = lm;
        showTraces(tr, S, p, lastValid());
        drawPZ(axP, lm);
        showResults(p, lm, S);
        drawRig(numel(S.t));
    end

    function drawRig(k)
        if isempty(S), return; end
        k = min(k, lastValid());
        z = sscanf(ui.zoom.Value, '%f');
        odyssix.ui.rigPose(rig, z * S.th(k), z * S.al(k), z * S.r(k), ui.L.Value / P.L);
    end

    function animate()
        if busy, return; end
        busy = true; ui.run.Enable = 'off'; ui.run.Text = 'running...';
        c = onCleanup(@() finishRun());
        p = readParams();
        sp = sscanf(ui.speed.Value, '%f');
        stride = max(1, round(0.025 * p.fs));        % ~40 frames per sim-second
        n = lastValid();
        showTraces(tr, S, p, 1);
        t0 = tic;
        for k = 1:stride:n
            while toc(t0) * sp < S.t(k), end
            if ~isvalid(fig), return; end
            showTraces(tr, S, p, k);
            drawRig(k);
            drawnow limitrate;
        end
        showTraces(tr, S, p, n); drawRig(n); drawnow;
    end

    function r = getResult()
        r = S;
    end

    function n = lastValid()
        n = find(~isnan(S.th), 1, 'last');
    end

    function finishRun()
        busy = false;
        if isvalid(fig), ui.run.Enable = 'on'; ui.run.Text = char(9654) + "  RUN"; end
    end

    function showResults(p, lm, S)
        mg = lm.margins;
        if ~lm.innerStable
            state = 'UNSTABLE INNER LOOP: pendulum controller cannot hold it up';  col = [0.78 0.12 0.12];
        elseif ~lm.clStable
            state = 'UNSTABLE: the linear model diverges';                        col = [0.78 0.12 0.12];
        elseif ~isnan(S.abortT)
            state = sprintf('ABORTED at t = %.2f s: %s', S.abortT, S.abortWhy);  col = [0.85 0.42 0.05];
        elseif mg.MsdB > 8
            state = 'BALANCES, but fragile (M_S > 8 dB)';                       col = [0.80 0.60 0.05];
        else
            state = 'BALANCES';                                                  col = [0.13 0.59 0.33];
        end
        ui.badge.Text = state; ui.badge.BackgroundColor = col;

        m = S.metrics;
        ui.res.Text = sprintf([ ...
            '<b style="font-size:15px">Results</b><br>' ...
            '<table style="font-size:13px">' ...
            '<tr><td>Rotor undershoot (wrong-way start)</td><td><b>%s</b></td>' ...
                '<td>&nbsp;&nbsp;Phase margin</td><td><b>%s</b></td></tr>' ...
            '<tr><td>Rotor overshoot</td><td><b>%s</b></td>' ...
                '<td>&nbsp;&nbsp;Gain margin</td><td><b>%s</b></td></tr>' ...
            '<tr><td>Settling time %s</td><td><b>%s</b></td>' ...
                '<td>&nbsp;&nbsp;Peak sensitivity M<sub>S</sub></td><td><b>%s</b></td></tr>' ...
            '<tr><td>Peak pendulum angle</td><td><b>%.2f&deg;</b> (abort 15&deg;)</td>' ...
                '<td>&nbsp;&nbsp;Pendulum falls in</td><td><b>%.0f ms</b> (open loop)</td></tr>' ...
            '<tr><td>Peak actuator command</td><td><b>%.0f &deg;/s&sup2;</b> (limit 1500)</td>' ...
                '<td>&nbsp;&nbsp;Time at the limit</td><td><b>%.0f ms</b></td></tr>' ...
            '<tr><td>Residual hunting (last 2 s)</td><td><b>&plusmn;%.2f&deg;</b> rotor</td>' ...
                '<td>&nbsp;&nbsp;actuator chatter</td><td><b>&plusmn;%.0f &deg;/s&sup2;</b></td></tr>' ...
            '<tr><td>Peak rotor speed</td><td><b>%.0f &deg;/s</b></td>' ...
                '<td>&nbsp;&nbsp;= step rate</td><td><b>%.0f microsteps/s</b></td></tr>' ...
            '</table><span style="color:#555">RHP zero at s = +%.2f rad/s limits bandwidth to about %.1f rad/s. ' ...
            'Margins are from the continuous linear model; the time response is the 500 Hz firmware loop.</span>'], ...
            pct(m.under), deg(mg.phiMdeg), pct(m.over), dB(mg.GMdB), ...
            bandTxt(m.band), secs(m.settle), dB(mg.MsdB), ...
            m.peakAl, 1000 / lm.rhpPole, m.peakU, 1000 * m.clipT, m.huntTh, m.huntU, m.peakW, m.peakW * P.uStepsPerDeg, ...
            lm.rhpPole, lm.rhpPole / 2);
    end
end

% ======================================================================= model
function P = defaults()
    P.Kp = 9; P.Kd = 9; P.signInv = true;      % Tutorial 5 System 1
    P.Kpp = 300; P.Kdp = 30;                   % Tutorial 5 inner (Kd 30, not 150)
    P.step = 2; P.tilt = 0; P.tStep = 1.0; P.Tend = 7;
    P.g = 9.81; P.Q = 20; P.wr2 = 0.803;
    P.L = P.g / (55.85 * 0.6805);              % = 0.2581 m, reproduces wg2 = 55.85 exactly
    P.fs = 500; P.fc = 10; P.clip = true; P.quant = true;
    P.nonlinear = true; P.encSignWrong = false;
    P.uLim = 1500;                             % EXP005_DEFAULT_U_LIMIT, deg/s^2
    P.abortDeg = 15;                           % EXP005_PENDULUM_ABORT_DEG
    P.rotorLimDeg = 240;                       % ENR312_ROTOR_LIMIT_DEG
    P.encDeg = 360 / 2400;                     % 600 PPR, x4 decode
    P.uStepsPerDeg = 3200 / 360;               % 200 x 16; conflict C-1 (may be 2x)
end

function w = wg2Of(P)
    % Tutorial 5: omega_g^2 = g / (L * 0.6805). L = 0.2581 m gives 55.85.
    w = P.g / (P.L * 0.6805);
end

function lm = linModel(P)
    wg2 = wg2Of(P);
    gam = sqrt(wg2) / P.Q;
    denPend = [1, gam, -wg2];
    sp = 1 - 2 * P.encSignWrong;               % a wrong encoder sign negates the inner loop
    inner = denPend + sp * [0, P.wr2 * P.Kdp, P.wr2 * P.Kpp];
    sgn = 1 - 2 * P.signInv;                   % -1 when inverted
    lNum = conv(denPend, sgn * [P.Kd, P.Kp]);
    lDen = conv([1 0 0], inner);
    cl = lDen + [zeros(1, numel(lDen) - numel(lNum)), lNum];
    lm.wg2 = wg2; lm.denPend = denPend; lm.inner = inner; lm.cl = cl;
    lm.olPoles = roots(denPend); lm.rhpPole = max(real(lm.olPoles));
    lm.innerStable = all(real(roots(inner)) < 0);
    lm.clPoles = roots(cl); lm.clStable = all(real(lm.clPoles) < 0);
    lm.margins = exp005_stability_margins(struct('L', struct('num', lNum, 'den', lDen)), ...
                                          logspace(-2, 3, 20000));
end

function S = simulate(P)
%SIMULATE  The firmware loop at fs against the plant, u held between samples.
%   states x = [theta; theta_dot; alpha; alpha_dot], degrees; alpha is the
%   Tutorial-5 angle from upright (alpha = pi - psi, psi = encoder angle from
%   hanging, see rotary_pendulum_psiddot).
%   linear:    theta'' = u ;  alpha'' + gamma alpha' - wg2 alpha = wr2 u   (exact ZOH)
%   nonlinear: theta'' = u ;  alpha'' = -psi''(pi - alpha, ...)            (RK4, 4 substeps)
    wg2 = wg2Of(P); gam = sqrt(wg2) / P.Q;
    A = [0 1 0 0; 0 0 0 0; 0 0 0 1; 0 0 wg2 -gam];
    B = [0; 1; 0; P.wr2];
    Ts = 1 / P.fs;
    M = expm([A B; zeros(1, 5)] * Ts); Ad = M(1:4, 1:4); Bd = M(1:4, 5);
    a = 1 - exp(-2 * pi * P.fc * Ts);          % ENR312_PD_AlphaFromFc
    sgn = 1 - 2 * P.signInv;
    N = round(P.Tend * P.fs) + 1;
    t = (0:N-1)' * Ts;
    [th, al, u, r, w] = deal(nan(N, 1));
    x = [0; 0; P.tilt; 0];
    pp = struct('wg2', wg2, 'wr2', P.wr2, 'gamma', gam);
    nSub = 4; h = Ts / nSub;
    dR = 0; dP = 0; eR0 = 0; eP0 = 0;
    abortT = NaN; why = '';
    for k = 1:N
        r(k) = P.step * (t(k) >= P.tStep);
        thm = x(1); alm = x(3);
        if P.quant
            thm = round(thm * P.uStepsPerDeg) / P.uStepsPerDeg;
            alm = round(alm / P.encDeg) * P.encDeg;
        end
        if P.encSignWrong, alm = -alm; end       % pendulum sensed with the wrong sign
        eR = r(k) - thm; eP = -alm;
        if k > 1
            dR = dR + a * ((eR - eR0) / Ts - dR);
            dP = dP + a * ((eP - eP0) / Ts - dP);
        end
        eR0 = eR; eP0 = eP;
        uk = sgn * (P.Kp * eR + P.Kd * dR) + (P.Kpp * eP + P.Kdp * dP);
        if P.clip, uk = min(max(uk, -P.uLim), P.uLim); end
        th(k) = x(1); al(k) = x(3); w(k) = x(2); u(k) = uk;
        if abs(x(3)) > P.abortDeg
            abortT = t(k); why = sprintf('pendulum beyond %g deg', P.abortDeg); break;
        end
        if abs(x(1)) > P.rotorLimDeg
            abortT = t(k); why = sprintf('rotor beyond %g deg', P.rotorLimDeg); break;
        end
        if P.nonlinear
            for i = 1:nSub
                k1 = fnl(x, uk, pp); k2 = fnl(x + h/2*k1, uk, pp);
                k3 = fnl(x + h/2*k2, uk, pp); k4 = fnl(x + h*k3, uk, pp);
                x = x + h/6 * (k1 + 2*k2 + 2*k3 + k4);
            end
        else
            x = Ad * x + Bd * uk;
        end
    end
    S = struct('t', t, 'th', th, 'al', al, 'u', u, 'r', r, 'w', w, ...
               'abortT', abortT, 'abortWhy', why);
    S.metrics = metrics(S, P);
end

function dx = fnl(x, uDeg, pp)
%FNL  Nonlinear rigid-pendulum plant in the lab's degree units.
    d2r = pi / 180;
    psi = pi - x(3) * d2r; psiD = -x(4) * d2r;
    aDD = -rotary_pendulum_psiddot(psi, psiD, x(2) * d2r, uDeg * d2r, pp) / d2r;
    dx = [x(2); uDeg; x(4); aDD];
end

function m = metrics(S, P)
    v = ~isnan(S.th);
    after = v & S.t >= P.tStep;
    m.peakAl = max(abs(S.al(v)));
    m.peakU  = max(abs(S.u(v)));
    m.clipT  = nnz(abs(S.u(v)) >= P.uLim - 1e-9) / P.fs;
    m.peakW  = max(abs(S.w(v)));
    % Residual hunting over the last 2 s: quantisation-driven limit cycle.
    tail = v & S.t >= S.t(find(v, 1, 'last')) - 2;
    m.huntTh = (max(S.th(tail)) - min(S.th(tail))) / 2;
    m.huntU  = (max(S.u(tail))  - min(S.u(tail)))  / 2;
    if ~isnan(S.abortT)
        [m.under, m.over, m.settle, m.band] = deal(NaN);
    elseif P.step > 0 && any(after)
        y = S.th(after); tt = S.t(after);
        y0 = y(1);                              % where the rotor was at the step
        m.under = 100 * min(0, min(y - y0)) / P.step;
        m.over  = 100 * max(0, max(y) - P.step) / P.step;
        % Band: 2 % of the step, but never tighter than 2 microsteps -- the rotor
        % cannot sit closer than its own quantisation (0.1125 deg/microstep).
        m.band = max(0.02 * P.step, 2 / P.uStepsPerDeg);
        out = abs(y - P.step) > m.band;
        if ~isnan(S.abortT) || out(end), m.settle = NaN;
        elseif ~any(out), m.settle = 0;
        else, m.settle = tt(find(out, 1, 'last')) - P.tStep;
        end
    else
        [m.under, m.over, m.settle] = deal(NaN); m.band = NaN;
    end
end

function selfCheck(P)
    % The app's plant must be the repository's plant, or it teaches the wrong thing.
    ref = exp005_inverted_model(P.Kp, P.Kd);
    lm  = linModel(P);
    err = max(abs(ref.T.den - lm.cl)) / max(abs(ref.T.den));
    assert(err < 1e-6, 'exp005_lab: model differs from exp005_inverted_model (%.2g)', err);
end

% ===================================================================== presets
function n = presetNames()
    n = {'System 1 (stable, Tutorial 5)', 'System 2 (quasi-stable, Tutorial 5)', ...
         'Tutorial design A (Kp 6.25, Kd 7)', 'Tutorial design B (Kp 0.5, Kd 10.75)', ...
         'Forgot the sign inversion', 'Pendulum encoder sign wrong', 'Slow 50 Hz loop', 'Heavy derivative filter (2 Hz)'};
end

function p = presetValues(name)
    base = struct('Kp', 9, 'Kd', 9, 'inv', true, 'Kpp', 300, 'Kdp', 30, 'step', 2, ...
                  'tilt', 0, 'L', 9.81 / (55.85 * 0.6805), 'Q', 20, 'fs', '500 Hz', 'fc', 10, ...
                  'clip', true, 'quant', true, 'nonlin', true, 'encsign', false);
    p = base;
    switch strtok(name, ' ')
        case 'System'
            if contains(name, '2'), p.Kp = 10; p.Kd = 3.33; end
        case 'Tutorial'
            if contains(name, 'A'), p.Kp = 6.25; p.Kd = 7; else, p.Kp = 0.5; p.Kd = 10.75; end
        case 'Forgot'
            p.inv = false;
        case 'Pendulum'
            p.encsign = true;
        case 'Slow'
            p.fs = '50 Hz';
        case 'Heavy'
            p.fc = 2;
    end
end

% ===================================================================== drawing
function tr = buildTraces(axT, axA, axU, axP)
    blue = [0.16 0.38 0.78]; red = [0.86 0.22 0.18]; grn = [0.13 0.59 0.33];
    for ax = [axT axA axU]
        hold(ax, 'on'); grid(ax, 'on'); ax.FontSize = 11; ax.Box = 'on';
        ax.Toolbar.Visible = 'off';
    end
    tr.r  = plot(axT, nan, nan, '--', 'Color', grn, 'LineWidth', 1.6);
    tr.th = plot(axT, nan, nan, 'Color', blue, 'LineWidth', 2.2);
    tr.thDot = plot(axT, nan, nan, 'o', 'MarkerFaceColor', blue, 'MarkerEdgeColor', 'w', 'MarkerSize', 7);
    title(axT, 'Rotor angle \theta (deg)'); legend(axT, {'reference', '\theta'}, 'Location', 'southeast');
    tr.alWarn = [yline(axA, 10, ':', 'Color', [0.85 0.55 0.1]), yline(axA, -10, ':', 'Color', [0.85 0.55 0.1])];
    tr.alAbort = [yline(axA, 15, '--', 'abort', 'Color', red), yline(axA, -15, '--', 'Color', red)];
    tr.al = plot(axA, nan, nan, 'Color', red, 'LineWidth', 2.2);
    tr.alDot = plot(axA, nan, nan, 'o', 'MarkerFaceColor', red, 'MarkerEdgeColor', 'w', 'MarkerSize', 7);
    title(axA, 'Pendulum angle from upright \alpha (deg)');
    tr.uLim = [yline(axU, 1500, '--', 'Color', [0.5 0.5 0.5]), yline(axU, -1500, '--', 'Color', [0.5 0.5 0.5])];
    tr.u = plot(axU, nan, nan, 'Color', [0.45 0.25 0.65], 'LineWidth', 1.4);
    title(axU, 'Actuator u (deg/s^2)'); xlabel(axU, 't (s)');
    tr.axT = axT; tr.axA = axA; tr.axU = axU;
end

function showTraces(tr, S, P, k)
    t = S.t(1:k);
    set(tr.r,  'XData', t, 'YData', S.r(1:k));
    set(tr.th, 'XData', t, 'YData', S.th(1:k));
    set(tr.al, 'XData', t, 'YData', S.al(1:k));
    set(tr.u,  'XData', t, 'YData', S.u(1:k));
    set(tr.thDot, 'XData', S.t(k), 'YData', S.th(k));
    set(tr.alDot, 'XData', S.t(k), 'YData', S.al(k));
    for ax = [tr.axT tr.axA tr.axU], xlim(ax, [0 P.Tend]); end
    v = ~isnan(S.th);
    yT = [S.th(v); S.r(v); 0]; ylim(tr.axT, padLim([min(yT) max(yT)], 1));
    yA = max(abs(S.al(v))); ylim(tr.axA, padLim([-yA yA], 0.5));
    yU = max(abs(S.u(v))); ylim(tr.axU, padLim([-yU yU], 100));
    show = yA > 6;  set([tr.alWarn tr.alAbort], 'Visible', show);
    set(tr.uLim, 'Visible', yU > 600);
end

function l = padLim(l, minSpan)
    if ~all(isfinite(l)), l = [-1 1]; end
    c = mean(l); h = max(diff(l) / 2 * 1.15, minSpan / 2);
    l = c + [-h h];
end

function drawPZ(ax, lm)
    cla(ax); hold(ax, 'on'); grid(ax, 'on'); ax.FontSize = 10; ax.Box = 'on';
    ax.Toolbar.Visible = 'off';
    p = lm.clPoles; z = lm.rhpPole;
    xline(ax, 0, 'Color', [0.3 0.3 0.3]);
    patch(ax, [0 40 40 0], [-40 -40 40 40], [1 0.9 0.9], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
    plot(ax, real(lm.olPoles), imag(lm.olPoles), 'x', 'Color', [0.6 0.6 0.6], 'MarkerSize', 10, 'LineWidth', 2);
    plot(ax, real(p), imag(p), 'x', 'Color', [0.16 0.38 0.78], 'MarkerSize', 11, 'LineWidth', 2.4);
    plot(ax, z, 0, 'o', 'Color', [0.86 0.22 0.18], 'MarkerSize', 10, 'LineWidth', 2);
    L = 1.2 * max([abs(p); abs(lm.olPoles); 1]);
    L = min(L, 40);
    xlim(ax, [-L 0.7 * L]); ylim(ax, [-L L]);
    title(ax, 'Poles x  RHP zero o'); xlabel(ax, 'Re (rad/s)');
end

function l = lab(parent, txt, r, c)
    l = uilabel(parent, 'Text', txt, 'FontSize', 12);
    place(l, r, c);
end

function place(h, r, c)
    h.Layout.Row = r; h.Layout.Column = c;
end

function s = bandTxt(v), if isnan(v), s = ''; else, s = sprintf('(&plusmn;%.2f&deg;)', v); end, end
function s = pct(v),  if isnan(v), s = '--'; else, s = sprintf('%+.1f %%', v); end, end
function s = secs(v), if isnan(v), s = 'not settled'; else, s = sprintf('%.2f s', v); end, end
function s = deg(v),  if isnan(v), s = '--'; else, s = sprintf('%.1f&deg;', v); end, end
function s = dB(v),   if ~isfinite(v), s = '--'; else, s = sprintf('%.2f dB', v); end, end

function s = limitsText()
    s = ['<b style="font-size:14px">&#9888; Model limits: read before trusting a result</b><br>' ...
         '<b>Simulated as the firmware does it:</b> 500 Hz loop, derivative filter, ' ...
         '&plusmn;1500 &deg;/s&sup2; actuator clip, 0.15&deg; encoder and 0.1125&deg; microstep ' ...
         'quantisation, abort at |&alpha;| &gt; 15&deg; and |&theta;| &gt; 240&deg;.<br>' ...
         '<b>Physics:</b> nonlinear rigid pendulum (sin, cos, centrifugal (d&theta;/dt)&sup2;) by default; untick it to compare with the Tutorial&apos;s linear model. ' ...
         'Derivation: docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md.<br>' ...
         '<b>NOT simulated:</b><br>' ...
         '&bull; <b>Stepper = perfect acceleration source.</b> No missed steps, torque limit or resonance. ' ...
         'A real NEMA17 can stall at high acceleration.<br>' ...
         '&bull; <b>Plant values are Tutorial 5&apos;s</b> (&omega;<sub>r</sub>&sup2; 0.803, &omega;<sub>g</sub>&sup2; 55.85, Q 20), ' ...
         '<b>not measured on this rig</b> (open item OI-9).<br>' ...
         '&bull; No friction except Q, no backlash, no cable drag, no sensor noise, no I/O delay.<br>' ...
         '&bull; Rotor scale assumes 8.889 microsteps/&deg;; the Edukit manual says 2&times; that (conflict C-1, unresolved).<br>' ...
         '&bull; 3-D view angles are <b>zoomed</b> (see Controls); plots are true values.'];
end

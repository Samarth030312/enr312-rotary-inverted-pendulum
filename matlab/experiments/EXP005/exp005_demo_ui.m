function exp005_demo_ui(opts)
%EXP005_DEMO_UI  Teaching UI: EXP005 (Tutorial 5) inverted-pendulum simulation.
%
%   addpath(genpath(fullfile(<repo>,'matlab'))); exp005_demo_ui
%
%   Animates the repository's EXP005 model (exp005_inverted_model) for the two
%   Tutorial 5 designs, System 1 (Kp=9, Kd=9) and System 2 (Kp=10, Kd=3.33):
%   a 3-D view of the rig, rotor and pendulum angle traces, and the pole-zero
%   map. Plots are in true units; the 3-D animation exaggerates angles by
%   opts.VisualGain so a 2 deg step is visible on screen.
%
%   This is the LINEAR model of the INVERTED configuration. It is a prediction,
%   not hardware evidence. No toolbox required.
%
%   opts.SyncDir  : if set, write <SyncDir>/ready, wait for <SyncDir>/go, and
%                   write <SyncDir>/done at the end (used to screen-record).
%   opts.Close    : close the figure at the end (default false).

    arguments
        opts.StepDeg    (1,1) double = 2.0      % Tutorial 5 rotor step
        opts.Tend       (1,1) double = 6.0      % s, per design
        opts.TStep      (1,1) double = 0.5      % s, step instant
        opts.VisualGain (1,1) double = 8.0      % animation only
        opts.SyncDir    (1,:) char   = ''
        opts.Close      (1,1) logical = false
    end

    designs = { 'System 1 (stable)',       9.00, 9.00; ...
                'System 2 (quasi-stable)', 10.00, 3.33 };

    dt = 0.01;                         % s, animation and sample step
    t  = 0:dt:opts.Tend;

    % ---------------------------------------------------------------- figure
    fig = figure('Name', 'ENR312 EXP005 simulation', 'NumberTitle', 'off', ...
                 'Color', 'w', 'Units', 'pixels', 'Position', [120 80 1600 900], ...
                 'MenuBar', 'none', 'ToolBar', 'none');
    if exist('theme', 'file'), theme(fig, 'light'); end   % R2025a+ defaults to dark

    annotation(fig, 'textbox', [0 0.935 1 0.065], 'String', ...
        {'\bfENR312 \cdot EXP005 \cdot Tutorial 5: Unstable MIMO control (inverted rotary pendulum)', ...
         '\rmMATLAB simulation of the repository model  \cdot  G_{pend}(s) = \omega_r^2 s^2 / (s^2 + (\omega_g/Q) s - \omega_g^2)  \cdot  G_{rotor}(s) = 1/s^2  \cdot  inner K_{pend} = 300 + 30 s (fixed)'}, ...
        'EdgeColor', 'none', 'BackgroundColor', [0.12 0.20 0.33], 'Color', 'w', ...
        'FontSize', 13, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'Interpreter', 'tex');

    axRig = axes(fig, 'Position', [0.03 0.30 0.36 0.60]);
    axTh  = axes(fig, 'Position', [0.45 0.68 0.33 0.22]);
    axAl  = axes(fig, 'Position', [0.45 0.38 0.33 0.22]);
    axPZ  = axes(fig, 'Position', [0.83 0.38 0.15 0.52]);
    info  = annotation(fig, 'textbox', [0.03 0.02 0.94 0.25], 'String', '', ...
        'EdgeColor', [0.8 0.8 0.8], 'BackgroundColor', [0.97 0.97 0.97], ...
        'FontName', 'monospaced', 'FontSize', 13, 'Interpreter', 'none', 'Color', 'k', ...
        'VerticalAlignment', 'top');

    % ------------------------------------------------------------- rig view
    Ra = 0.15; Lp = 0.235; H = 0.20;   % m, arm, pendulum, column (visual)
    hold(axRig, 'on'); axis(axRig, 'equal'); grid(axRig, 'on');
    view(axRig, 35, 22);
    xlim(axRig, [-0.25 0.25]); ylim(axRig, [-0.25 0.25]); zlim(axRig, [0 0.5]);
    xlabel(axRig, 'x (m)'); ylabel(axRig, 'y (m)'); zlabel(axRig, 'z (m)');
    plot3(axRig, [0 0], [0 0], [0 H], 'Color', [0.3 0.3 0.3], 'LineWidth', 8);
    th = linspace(0, 2*pi, 60);
    fill3(axRig, 0.08*cos(th), 0.08*sin(th), zeros(size(th)), [0.85 0.85 0.85]);
    hArm  = plot3(axRig, [0 Ra], [0 0], [H H], 'Color', [0.10 0.35 0.75], 'LineWidth', 6);
    hPend = plot3(axRig, [Ra Ra], [0 0], [H H+Lp], 'Color', [0.85 0.20 0.15], 'LineWidth', 4);
    hBob  = plot3(axRig, Ra, 0, H+Lp, 'o', 'MarkerSize', 12, ...
                  'MarkerFaceColor', [0.85 0.20 0.15], 'MarkerEdgeColor', 'k');
    hRef  = plot3(axRig, [0 Ra], [0 0], [H H], '--', 'Color', [0.2 0.7 0.3], 'LineWidth', 1.5);
    hTitle = title(axRig, '', 'FontSize', 13);
    text(axRig, -0.24, -0.24, 0.48, sprintf('3-D view: angles exaggerated x%g', opts.VisualGain), ...
         'FontSize', 9, 'Color', [0.4 0.4 0.4]);

    % ----------------------------------------------------------- run designs
    if ~isempty(opts.SyncDir)
        drawnow;
        fclose(fopen(fullfile(opts.SyncDir, 'ready'), 'w'));
        while ~isfile(fullfile(opts.SyncDir, 'go')), pause(0.1); end
    end

    for d = 1:size(designs, 1)
        name = designs{d,1}; kp = designs{d,2}; kd = designs{d,3};
        m  = exp005_inverted_model(kp, kd);
        mg = exp005_stability_margins(m);

        % theta/r = L/(1+L); alpha/r = wr2 * K_rotor * s^2 / cl  (derived in
        % exp005_inverted_model: alpha = wr2/inner * v, v = K_r s^2 inner/cl * r)
        cl    = m.T.den;
        numAl = conv(m.wr2 * m.rotorSign * [kd, kp], [1 0 0]);
        r     = opts.StepDeg * (t >= opts.TStep);
        thDeg = simTf(m.T.num, cl, r, dt);
        alDeg = simTf(numAl, cl, r, dt);

        under = min(thDeg(t >= opts.TStep));
        stepTraces(axTh, axAl, t, r, opts);
        hThL = plot(axTh, nan, nan, 'Color', [0.10 0.35 0.75], 'LineWidth', 2);
        hAlL = plot(axAl, nan, nan, 'Color', [0.85 0.20 0.15], 'LineWidth', 2);
        drawPZ(axPZ, m);
        hTitle.String = sprintf('%s:  K_P = %.2f,  K_d = %.2f', name, kp, kd);

        base = sprintf([ ...
            '%s   rotor PD  K_P = %.2f  K_d = %.2f  (sign inverted: inverted-mode T_rotor has negative DC gain)\n' ...
            'open-loop pendulum poles  %+.2f, %+.2f rad/s  -> falls with time constant %.0f ms\n' ...
            'RHP pole becomes a NON-MINIMUM-PHASE ZERO of T_rotor at s = +%.2f rad/s -> rotor first moves the WRONG way\n' ...
            'margins: phase %.1f deg   gain %.2f dB   M_S %.2f dB   (closed loop %s)\n'], ...
            name, kp, kd, m.openLoopPoles(1), m.openLoopPoles(2), 1000*m.fallTimeConstant, ...
            m.nmpZero, mg.phiMdeg, mg.GMdB, mg.MsdB, ternary(m.closedLoopStable, 'STABLE', 'UNSTABLE'));

        t0 = tic;
        for k = 1:numel(t)
            while toc(t0) < t(k), end            % real time
            if mod(k-1, 2) ~= 0 && k ~= numel(t), continue; end   % 50 fps
            gT = deg2rad(opts.VisualGain * thDeg(k));
            gA = deg2rad(opts.VisualGain * alDeg(k));
            gR = deg2rad(opts.VisualGain * r(k));
            tip = [Ra*cos(gT), Ra*sin(gT), H];
            tang = [-sin(gT), cos(gT), 0];
            bob = tip + Lp * (sin(gA) * tang + [0 0 cos(gA)]);
            set(hArm,  'XData', [0 tip(1)], 'YData', [0 tip(2)]);
            set(hRef,  'XData', [0 Ra*cos(gR)], 'YData', [0 Ra*sin(gR)]);
            set(hPend, 'XData', [tip(1) bob(1)], 'YData', [tip(2) bob(2)], 'ZData', [H bob(3)]);
            set(hBob,  'XData', bob(1), 'YData', bob(2), 'ZData', bob(3));
            set(hThL,  'XData', t(1:k), 'YData', thDeg(1:k));
            set(hAlL,  'XData', t(1:k), 'YData', alDeg(1:k));
            info.String = [base, sprintf( ...
                't = %5.2f s   reference r = %.2f deg   rotor theta = %+7.3f deg   pendulum alpha = %+7.3f deg   undershoot so far %+.1f %%', ...
                t(k), r(k), thDeg(k), alDeg(k), 100 * min(0, min(thDeg(1:k))) / opts.StepDeg)];
            drawnow limitrate;
        end
        drawnow;
        fprintf('%s: undershoot %.1f %%, peak alpha %.3f deg\n', name, ...
                100 * under / opts.StepDeg, max(abs(alDeg)));
        pause(1.5);
    end

    if ~isempty(opts.SyncDir)
        fclose(fopen(fullfile(opts.SyncDir, 'done'), 'w'));
    end
    if opts.Close, close(fig); end
end

% -------------------------------------------------------------------------
function stepTraces(axTh, axAl, t, r, opts)
    cla(axTh); hold(axTh, 'on'); grid(axTh, 'on');
    plot(axTh, t, r, '--', 'Color', [0.2 0.7 0.3], 'LineWidth', 1.5);
    yline(axTh, 0, ':k');
    xlim(axTh, [0 opts.Tend]); ylim(axTh, opts.StepDeg * [-0.6 1.8]);
    ylabel(axTh, '\theta rotor (deg)'); title(axTh, 'Rotor angle vs 2\circ reference');
    cla(axAl); hold(axAl, 'on'); grid(axAl, 'on');
    yline(axAl, 0, ':k');
    xlim(axAl, [0 opts.Tend]); ylim(axAl, opts.StepDeg * [-0.6 0.6]);
    xlabel(axAl, 't (s)'); ylabel(axAl, '\alpha pendulum (deg)');
    title(axAl, 'Pendulum angle from upright');
end

function drawPZ(ax, m)
    cla(ax); hold(ax, 'on'); grid(ax, 'on');
    p0 = m.openLoopPoles; pc = m.closedLoopPoles;
    plot(ax, real(p0), imag(p0), 'x', 'Color', [0.6 0.6 0.6], 'MarkerSize', 12, 'LineWidth', 2);
    plot(ax, real(pc), imag(pc), 'bx', 'MarkerSize', 12, 'LineWidth', 2);
    plot(ax, m.nmpZero, 0, 'ro', 'MarkerSize', 11, 'LineWidth', 2);
    xline(ax, 0, 'k');
    legend(ax, {'open-loop pend. poles', 'closed-loop poles', 'NMP zero'}, ...
           'Location', 'southoutside', 'FontSize', 8);
    xlabel(ax, 'Re (rad/s)'); ylabel(ax, 'Im (rad/s)'); title(ax, 'Pole-zero map');
    lim = 1.15 * max(abs([p0; pc; m.nmpZero]));
    xlim(ax, [-lim, 0.6*lim]); ylim(ax, [-lim lim]);
end

function y = simTf(num, den, u, dt)
%SIMTF  Simulate strictly proper num/den with ZOH input u (no toolbox).
    num = num / den(1); den = den / den(1);
    n = numel(den) - 1;
    num = [zeros(1, n + 1 - numel(num)), num];
    b = num(2:end) - num(1) * den(2:end);      % num(1) == 0 for strictly proper
    A = [zeros(n-1, 1), eye(n-1); -fliplr(den(2:end))];
    B = [zeros(n-1, 1); 1];
    C = fliplr(b);
    M = expm([A B; zeros(1, n+1)] * dt);
    Ad = M(1:n, 1:n); Bd = M(1:n, n+1);
    x = zeros(n, 1); y = zeros(size(u));
    for k = 1:numel(u)
        y(k) = C * x;
        x = Ad * x + Bd * u(k);
    end
end

function s = ternary(c, a, b)
    if c, s = a; else, s = b; end
end

function R = identify_pendulum_20261021(outDir)
%IDENTIFY_PENDULUM_20261021  The pendulum constant and the pivot friction, from rig runs of 2026-10-21.
%
%   R = identify_pendulum_20261021()   writes
%       results/tables/PEND_identification_20261021.csv
%       results/figures/2026-10-21b_pendulum_identification.png
%
%   No dedicated free swing was recorded that day. Two stretches of the recorded runs
%   are close enough to one:
%
%   A. EXP010 R01 (Tutorial 10). After the arm settled it stood still (not one
%      microstep for 10 s), and the pendulum, knocked to 5.7 deg, swung freely.
%      Model, arm still, psi from the hanging datum:
%          psi'' = -wg2 sin(psi - psi_c) - gamma psi' - c sgn(psi')      (sliding)
%          psi'  = 0 while |wg2 sin(psi - psi_c)| <= c                    (stuck)
%      c is dry (Coulomb) friction as an angular deceleration [rad/s^2], gamma
%      viscous damping [1/s], psi_c the centre the pendulum swings about (the encoder
%      datum is itself a rest position, so it can be off true vertical). The model
%      is quantised to the encoder's 0.15 deg and fitted to the samples
%      (least squares, fminsearch, several starts). A viscous-only fit (c = 0) is
%      the alternative hypothesis.
%
%   B. EXP024 R05 (pendulum target 90 deg). In the undisturbed stretches the
%      pendulum swings to about 92 deg. The period of a pendulum of amplitude A is
%      T = 4 K(m) / wg with m = sin^2(A/2) (complete elliptic integral of the first
%      kind), so wg2 = (4 K(m) / T)^2. The arm is not still here (it moves 18-25 deg
%      peak to peak), which perturbs the period slightly.
%
%   C. The same R05 stretches, energy balance. With E = psi'^2/(2 wg2) + 1 - cos psi,
%      dE/dt = (psi'/wg2) (wr2 cos psi u - losses), so over whole cycles at a
%      steady swing the mean input (psi'/wg2) wr2 cos psi u equals the mean loss.
%      Dry friction c takes out c |psi'| / wg2; whatever remains is written as a
%      viscous gamma psi'^2 / wg2 (gamma, Q = wg / gamma). u is the arm
%      acceleration the firmware commanded (wr2 = 0.803, Tutorial value).
%
%   Base MATLAB only (fminsearch, ellipke).
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = repo; end
    d2r = pi / 180; ENC = 360 / 2400;

    % ---- A: free decay in T10 --------------------------------------------------------
    D = odyssix.data.loadRun('EXP010_20261021-162833_t10-q-i-r-1-k-1-1-7321_R01');
    [~, k0] = max(abs(D.psi)); w = D.t >= D.t(k0) & D.t <= D.t(k0) + 3;
    T = D.t(w) - D.t(k0); Y = D.psi(w) * d2r;
    armMoved = max(D.rotor(w)) - min(D.rotor(w));
    cost = @(x) sum((decay(x, T, Y(1), ENC) - Y).^2);
    best = struct('x', [], 'f', inf); opt = optimset('MaxFunEvals', 4000, 'MaxIter', 2000, 'TolX', 1e-6, 'TolFun', 1e-12);
    for c0 = [0.2 0.5 1.0], for g0 = [0 0.2 0.5]
        [x, f] = fminsearch(@(x) cost(guard(x)), [52 c0 g0 0.005], opt);
        if f < best.f, best.x = guard(x); best.f = f; end
    end, end
    [xv, fv] = fminsearch(@(x) cost(guard([x(1) 0 x(2) x(3)])), [52 0.3 0.005], opt); xv = guard([xv(1) 0 xv(2) xv(3)]);
    n = numel(Y); rmsC = sqrt(best.f / n) / d2r; rmsV = sqrt(fv / n) / d2r;
    A = struct('wg2', best.x(1), 'c', best.x(2), 'gamma', best.x(3), 'centre_deg', best.x(4) / d2r, ...
               'rms_deg', rmsC, 'visc_wg2', xv(1), 'visc_gamma', xv(3), 'visc_Q', sqrt(xv(1)) / xv(3), 'visc_rms_deg', rmsV, ...
               'stick_band_deg', best.x(2) / best.x(1) / d2r, 'arm_moved_deg', armMoved, 'n', n);

    % ---- B: large swings in R05 --------------------------------------------------------
    E = odyssix.data.loadRun('EXP024_20261021-161554_pendulum-090_R05');
    h = mod(E.psi + 180, 360) - 180; win = [12 17.5; 25 30; 44 48.5]; B = [];
    for i = 1:size(win, 1)
        s = E.t > win(i, 1) & E.t < win(i, 2); tt = E.t(s); y = h(s);
        j = find(y(1:end-1) < 0 & y(2:end) >= 0); z = tt(j) + (0 - y(j)) ./ (y(j+1) - y(j)) .* (tt(j+1) - tt(j));
        Tp = median(diff(z));
        pk = []; for q = 2:numel(y) - 1, if abs(y(q)) >= abs(y(q-1)) && abs(y(q)) > abs(y(q+1)) && abs(y(q)) > 45, pk(end+1) = abs(y(q)); end, end %#ok<AGROW>
        Am = median(pk); Kc = ellipke(sin(Am * d2r / 2)^2);
        B = [B; win(i, :) Am Tp (4 * Kc / Tp)^2 max(E.rotor(s)) - min(E.rotor(s))]; %#ok<AGROW>
    end

    % ---- C: energy balance at the 92 deg swing ------------------------------------------
    wr2 = 0.803; p = unwrap(E.psi * d2r); pd = gradient(p, E.t); C = [];
    for i = 1:size(win, 1)
        s = E.t > win(i, 1) & E.t < win(i, 2); j = find(s(1:end-1) & h(1:end-1) < 0 & h(2:end) >= 0);
        k = j(1):j(end); Tw = E.t(j(end)) - E.t(j(1)); wg2 = B(i, 5);
        pin = trapz(E.t(k), pd(k) / wg2 * wr2 .* cos(p(k)) .* E.u(k) * d2r) / Tw;
        pc = trapz(E.t(k), A.c * abs(pd(k)) / wg2) / Tw;
        g = (pin - pc) / (trapz(E.t(k), pd(k).^2 / wg2) / Tw);
        C = [C; pin pc g sqrt(wg2) / g]; %#ok<AGROW>
    end

    % ---- table -------------------------------------------------------------------------
    src = ["A EXP010 R01 free decay (arm still), Coulomb + viscous fit"; "A same stretch, viscous-only fit"; ...
           compose("B+C EXP024 R05 %.1f-%.1f s, amplitude %.1f deg: elliptic period; energy balance with c from A", B(:, 1), B(:, 2), B(:, 3))];
    R = table(src, [A.wg2; A.visc_wg2; B(:, 5)], [A.c; 0; A.c * ones(3, 1)], [A.gamma; A.visc_gamma; C(:, 3)], ...
              [A.rms_deg; A.visc_rms_deg; nan(3, 1)], [A.arm_moved_deg; A.arm_moved_deg; B(:, 6)], ...
              'VariableNames', {'source', 'wg2_rad2_s2', 'coulomb_rad_s2', 'gamma_1_s', 'fit_rms_deg', 'arm_moved_deg'});
    R.Properties.UserData = struct('A', A, 'B', B, 'C', C);
    writetable(R, fullfile(outDir, 'results', 'tables', 'PEND_identification_20261021.csv'));
    fprintf('A  Coulomb fit:  wg2 %.1f  c %.3f rad/s^2  gamma %.3f 1/s  centre %+.2f deg  rms %.3f deg (n %d, arm moved %.3f deg)\n', ...
            A.wg2, A.c, A.gamma, A.centre_deg, A.rms_deg, A.n, A.arm_moved_deg);
    fprintf('A  viscous only: wg2 %.1f  gamma %.3f 1/s (Q %.1f)  rms %.3f deg\n', A.visc_wg2, A.visc_gamma, A.visc_Q, A.visc_rms_deg);
    fprintf('   stick band c/wg2 = +-%.2f deg\n', A.stick_band_deg);
    for i = 1:size(B, 1), fprintf('B  %4.1f-%4.1f s  amplitude %.1f deg  period %.3f s  wg2 %.1f  (arm %.1f deg pk-pk)\n', B(i, :)); end
    for i = 1:size(C, 1), fprintf('C  input %.4f /s, dry friction %.4f /s (x%.1f): extra gamma %.3f 1/s (Q %.0f)\n', C(i, 1), C(i, 2), C(i, 1) / C(i, 2), C(i, 3), C(i, 4)); end

    % ---- figure ------------------------------------------------------------------------
    f = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 1400 480]);
    if exist('theme', 'file'), theme(f, 'light'); end
    tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    tf = (0:0.001:T(end))';
    plot(ax, T, Y / d2r, 'o', 'Color', [0.85 0.33 0.10], 'MarkerSize', 3.5, 'MarkerFaceColor', [0.85 0.33 0.10]);
    plot(ax, tf, decay(best.x, tf, Y(1), ENC) / d2r, 'Color', [0.10 0.35 0.80], 'LineWidth', 1.6);
    plot(ax, tf, decay(xv, tf, Y(1), ENC) / d2r, '--', 'Color', [0.55 0.55 0.58], 'LineWidth', 1.4);
    legend(ax, {'rig (T10, arm still)', sprintf('dry friction: c %.2f rad/s^2, \\omega_g^2 %.1f, rms %.2f°', A.c, A.wg2, A.rms_deg), ...
                sprintf('viscous only: Q %.1f, rms %.2f°', A.visc_Q, A.visc_rms_deg)}, 'Location', 'northeast');
    xlabel(ax, 't after the peak (s)'); ylabel(ax, '\psi (deg)');
    title(ax, 'Free decay: dry friction fits, viscous damping does not');
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    v = [A.wg2; B(:, 5)]; cat_ = categorical({'T10 decay (5.7°)', 'R05 12-17 s (92°)', 'R05 25-30 s (92°)', 'R05 44-48 s (92°)'}, ...
        {'T10 decay (5.7°)', 'R05 12-17 s (92°)', 'R05 25-30 s (92°)', 'R05 44-48 s (92°)'});
    bar(ax, cat_, v, 'FaceColor', [0.10 0.35 0.80], 'EdgeColor', 'none');
    yline(ax, 57.01, '--', 'used by the firmware on 2026-10-21: 57.01 (Tutorial geometry)', 'Color', [0.80 0.13 0.13], ...
          'LabelHorizontalAlignment', 'left', 'LineWidth', 1.4);
    ylim(ax, [0 65]); ylabel(ax, '\omega_g^2 (rad^2/s^2)');
    title(ax, sprintf('The pendulum constant measured two ways: %.0f-%.0f, not 57', min(v), max(v)));
    exportgraphics(f, fullfile(outDir, 'results', 'figures', '2026-10-21b_pendulum_identification.png'), 'Resolution', 150);
    close(f);
end

function x = guard(x)
    x(1) = max(x(1), 20); x(2) = max(x(2), 0); x(3) = max(x(3), 0);
end

function y = decay(x, T, y0, ENC)
% free pendulum with dry and viscous friction, stick-slip, 0.5 ms Euler steps,
% sampled at T and quantised like the encoder
    wg2 = x(1); c = x(2); g = x(3); pc = x(4); dt = 5e-4; n = ceil(T(end) / dt) + 2;
    p = y0; v = 0; out = zeros(n, 1);
    for i = 1:n
        out(i) = p;
        drive = -wg2 * sin(p - pc) - g * v;
        if v == 0 && abs(drive) <= c, continue; end
        if v ~= 0, s = sign(v); else, s = sign(drive); end
        vn = v + (drive - c * s) * dt;
        if v ~= 0 && vn * v < 0, vn = 0; end
        v = vn; p = p + v * dt;
    end
    q = ENC * pi / 180;
    y = interp1((0:n-1)' * dt, round(out / q) * q, T);
end

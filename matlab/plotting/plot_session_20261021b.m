function plot_session_20261021b(outDir)
%PLOT_SESSION_20261021B  Figures of the evening rig session of 2026-10-21 (firmware 2.3.0).
%
%   plot_session_20261021b()     writes results/figures/2026-10-21b_*.png
%   Sources: data/raw/EXP0nn/*20261021-1[4-6]*.csv and their metadata, and
%   odyssix.sim.runCtrl / runTutorial for the simulations (labelled as such).
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = fullfile(repo, 'results', 'figures'); end
    C = struct('rig', [0.10 0.35 0.80], 'sim', [0.55 0.55 0.58], 'pend', [0.85 0.33 0.10], ...
               'ok', [0.13 0.55 0.30], 'bad', [0.80 0.13 0.13], 'ref', [0.25 0.25 0.25], 'old', [0.55 0.35 0.75]);
    hang = @(p) mod(p + 180, 360) - 180;  up = @(p) mod(180 - p + 180, 360) - 180;
    ld = @(id) odyssix.data.loadRun(id);

    % ---- 1. why 2.3.0 did not catch: every pass over the top ---------------------------
    am = ["EXP024_20261021-141233_swing-up_R01", "EXP024_20261021-141322_swing-up_R02", "EXP024_20261021-141455_swing-up_R03"];
    pm = ["EXP024_20261021-161431_swing-up_R04", "EXP024_20261021-163022_swing-up_R06", "EXP024_20261021-163243_swing-up_R07"];
    f = fig(1400, 520); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    for set_ = {am, pm}
        ids = set_{1}; isPm = isequal(ids, pm);
        for i = 1:numel(ids)
            [D, ~] = ld(ids(i)); h = hang(D.psi); kc = find(D.phase == 8, 1); if isempty(kc), kc = height(D); end
            cr = find(abs(h(1:end-1)) > 165 & abs(h(2:end)) > 165 & sign(h(1:end-1)) ~= sign(h(2:end)));
            cr = cr(cr < kc);
            v = abs((D.psi(cr + 1) - D.psi(max(cr - 1, 1))) ./ (D.t(cr + 1) - D.t(max(cr - 1, 1))));
            if isPm, col = C.bad; else, col = C.old; end
            plot(ax, D.t(cr), v, 'o', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 5, 'HandleVisibility', 'off');
        end
    end
    yline(ax, 60, '--', '2.3.0 catch limit 60 deg/s', 'Color', C.bad, 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    yline(ax, 100, '--', '2.2.0 and 2.3.1 (approaching) 100 deg/s', 'Color', C.ok, 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    h1 = plot(ax, nan, nan, 'o', 'Color', C.old, 'MarkerFaceColor', C.old); h2 = plot(ax, nan, nan, 'o', 'Color', C.bad, 'MarkerFaceColor', C.bad);
    legend(ax, [h1 h2], {'2.2.0: R01-R03 (caught at the first chance)', '2.3.0: R04, R06, R07'}, 'Location', 'northeast');
    xlabel(ax, 't since the swing started (s)'); ylabel(ax, 'speed over the top (deg/s)'); ylim(ax, [0 250]); xlim(ax, [0 42]);
    title(ax, 'Every pass over the top before a catch: 2.3.0 waited for < 60 deg/s, which the rig rarely gave');
    ax = nexttile(tl); prep(ax);
    for i = 1:numel(am), D = ld(am(i)); plotCatch(ax, D, C); end
    D = ld(pm(1)); plotCatch(ax, D, C);
    xlabel(ax, '\alpha at the catch (deg)'); ylabel(ax, '\alpha rate at the catch (deg/s)');
    xline(ax, [-7 7], ':'); xline(ax, [-2 2], ':'); yline(ax, 0, ':');
    title(ax, 'State at each catch (filled: held, open: fell). R02 was already crossing the top');
    save_(f, outDir, '2026-10-21b_swingup_passes_and_catches.png');

    % ---- 2. the fix, in simulation: 2.3.2 on the identified pendulum ------------------
    % plant from matlab/identification/identify_pendulum_20261021.m and the R05 energy
    % balance; the firmware is told 57.01, as on the rig
    c = odyssix.sim.defaults(24); c.wg2 = 57.01; c.seconds = 30;
    p = odyssix.sim.plant(5); p.wg2 = 47.6; p.Q = 65; p.coulomb = 0.48; p.bias = 0.5;
    S1 = odyssix.sim.runCtrl(c, p);
    f = fig(1400, 430); ax = axes(f); prep(ax);
    plot(ax, S1.t, abs(hang(S1.psi)), 'Color', C.ok, 'LineWidth', 1.4);
    k = find(S1.phase == 8, 1); if ~isempty(k), xline(ax, S1.t(k), '-', sprintf('caught %.1f s', S1.t(k)), 'Color', C.ok, 'LabelVerticalAlignment', 'bottom'); end
    yline(ax, 180, ':'); ylim(ax, [0 190]); xlabel(ax, 't (s)'); ylabel(ax, '|\psi| (deg)');
    title(ax, ['SIMULATION, firmware 2.3.2, on the pendulum identified from the rig data: \omega_g^2 47.6, dry friction ' ...
               '0.48 rad/s^2, Q 65, 0.5° encoder offset; the firmware told \omega_g^2 57.01, as on the rig']);
    save_(f, outDir, '2026-10-21b_swingup_fix_simulated.png');

    % ---- 3. dry friction: the T10 free decay and the T3/T4 offsets ----------------------
    f = fig(1400, 460); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    D = ld("EXP010_20261021-162833_t10-q-i-r-1-k-1-1-7321_R01"); [~, k] = max(abs(hang(D.psi)));
    w = D.t >= D.t(k) - 0.2 & D.t <= D.t(k) + 3;
    ax = nexttile(tl); prep(ax);
    plot(ax, D.t(w) - D.t(k), hang(D.psi(w)), '-o', 'Color', C.pend, 'MarkerSize', 3, 'LineWidth', 1.2);
    tt = linspace(0, 3, 600); A0 = abs(hang(D.psi(k))); wn = sqrt(54);
    plot(ax, tt, A0 * exp(-wn / (2 * 27) * tt) .* cos(wn * tt) * sign(hang(D.psi(k))), 'Color', C.sim, 'LineWidth', 1.2);
    xlabel(ax, 't after the swing peak (s)'); ylabel(ax, '\psi (deg)'); legend(ax, {'rig (arm still)', 'viscous model, Q 27'});
    title(ax, 'T10: a 5.7° swing dies in about 1.5 cycles; viscous damping alone would ring for ~20 s');
    ax = nexttile(tl); prep(ax);
    pr = [2 + 10 / 6 * 0.15, 2 + 10 / 6 * 0.9]; ms = [2.25 3.49];
    b = bar(ax, categorical({'T3 (rest -0.15°)', 'T4 (rest -0.90°)'}), [pr; ms]', 'EdgeColor', 'none'); b(1).FaceColor = C.sim; b(2).FaceColor = C.rig;
    ylabel(ax, 'arm after the 2° step (deg)'); ylim(ax, [0 4.2]); legend(ax, {'2 + Kpp/Kp \times rest angle', 'rig'}, 'Location', 'northwest');
    title(ax, 'The pendulum rests where friction leaves it; the PD then holds the arm off by Kpp/Kp\cdot\psi');
    save_(f, outDir, '2026-10-21b_dry_friction.png');

    % ---- 4. tutorials, rig over simulation ------------------------------------------------
    ids = ["EXP001_20261021-161628_t1-larger-move-20-deg_R01", "EXP002_20261021-161719_t2-kp-6-55-kd-4_R01", ...
           "EXP003_20261021-161823_t3-design-1-kp-6-kd-4-8_R01", "EXP004_20261021-161902_t4-reference-kp-6-kd-4-8_R01", ...
           "EXP009_20261021-162735_t9-n-1-1-k-1-2_R02", "EXP010_20261021-162833_t10-q-i-r-1-k-1-1-7321_R01"];
    names = {'T1 open-loop move', 'T2 rotor PD, step and load', 'T3 dual PD, hanging', 'T4 same gains (pendulum at rest -0.9°)', ...
             'T9 pole placement K = [1 2]', 'T10 LQR K = [1 1.73]'};
    f = fig(1500, 760); tl = tiledlayout(f, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:numel(ids)
        [D, M] = ld(ids(i)); c = M.config; c = clean(c);
        if c.exp >= 6, S = odyssix.sim.runCtrl(c, odyssix.sim.plant(3)); else, S = odyssix.sim.runTutorial(c, odyssix.sim.plant(max(c.exp, 2))); end
        ax = nexttile(tl); prep(ax);
        if c.exp == 1                                   % the rig log starts at the move; the simulation idles 1 s first
            k0 = find(abs(S.rotor) > 0.05, 1); S.t = S.t - S.t(max(k0 - 1, 1));
        end
        plot(ax, S.t, S.rotor, 'Color', C.sim, 'LineWidth', 2.2); plot(ax, D.t, D.rotor, 'Color', C.rig, 'LineWidth', 1.1);
        xlim(ax, [0 max(D.t(end), 1)]); title(ax, names{i}); xlabel(ax, 't (s)'); ylabel(ax, 'arm (deg)');
        if i == 1, legend(ax, {'simulation', 'rig'}, 'Location', 'southeast'); end
    end
    save_(f, outDir, '2026-10-21b_tutorials_rig_vs_sim.png');

    % ---- 5. Tutorial 7: live gain changes into the predicted failure region --------------
    f = fig(1400, 520); tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    for id = ["EXP007_20261021-162356_t7-300-30_R02", "EXP007_20261021-162501_t7-300-30_R03"]
        [D, M] = ld(id); ax = nexttile(tl); prep(ax);
        plot(ax, D.t, up(D.psi), 'Color', C.pend, 'LineWidth', 1.0);
        ev = M.events; if isstruct(ev), for e = 1:numel(ev), if startsWith(ev(e).what, 'live')
            xline(ax, ev(e).t, '--', sprintf('%s = %g', extractAfter(ev(e).what, 'live '), ev(e).value), 'LabelVerticalAlignment', 'bottom'); end, end, end
        ylim(ax, [-16 16]); ylabel(ax, '\alpha (deg)'); xlim(ax, [0 D.t(end)]);
        title(ax, sprintf('%s: %s', strrep(extractBefore(id, '_t7'), '_', ' '), M.result), 'Interpreter', 'none');
    end
    xlabel(ax, 't (s)');
    title(tl, ['Tutorial 7 on the rig: both losses follow a live gain change into the range the gain sweep ' ...
               'predicted to fail (pendulum Kd \geq 150; rotor Kd 30)']);
    save_(f, outDir, '2026-10-21b_t7_live_gains.png');

    % ---- 6. pendulum target 90 on the rig --------------------------------------------------
    [D, M] = ld("EXP024_20261021-161554_pendulum-090_R05");
    f = fig(1400, 430); ax = axes(f); prep(ax);
    plot(ax, D.t, hang(D.psi), 'Color', C.pend, 'LineWidth', 1.0); yline(ax, [-90 90], '--', 'HandleVisibility', 'off');
    % swing height = median of the peaks in the undisturbed stretches (it was held or
    % pushed around 18 s, 31-35 s and 36-42.5 s: arm still, u 0, pendulum at -89 deg)
    hh = hang(D.psi); w = (D.t > 12 & D.t < 17.5) | (D.t > 25 & D.t < 30) | (D.t > 44 & D.t < 48.5);
    pkk = []; for k = 2:height(D) - 1, if w(k) && abs(hh(k)) >= abs(hh(k - 1)) && abs(hh(k)) > abs(hh(k + 1)) && abs(hh(k)) > 45, pkk(end + 1) = abs(hh(k)); end, end %#ok<AGROW>
    pk = median(pkk);
    xregion(ax, 36, 42.5, 'FaceColor', [0.9 0.9 0.9], 'HandleVisibility', 'off');
    text(ax, 36.3, 120, {'held near -90° (arm still, u = 0):', 'it has exactly the target energy'}, 'FontSize', 9);
    xlabel(ax, 't (s)'); ylabel(ax, '\psi from hanging (deg)'); xlim(ax, [0 D.t(end)]);
    title(ax, sprintf('Pendulum target 90° on the rig (firmware 2.3.0): swing height %.1f° (median of the undisturbed peaks); target 0 at %.0f s stops it', ...
        pk, M.events(end).t));
    save_(f, outDir, '2026-10-21b_pendulum_target_90_rig.png');
end

function plotCatch(ax, D, C)
    a = mod(180 - D.psi + 180, 360) - 180; k = find(D.phase == 8, 1); if isempty(k), return; end
    ad = (a(k + 1) - a(k - 1)) / (D.t(k + 1) - D.t(k - 1));
    held = (find(D.phase == 13 | D.phase == -1, 1, 'last') - k) * 0.02 > 3 || D.t(end) - D.t(k) > 3;
    if held, mf = C.ok; else, mf = 'none'; end
    plot(ax, a(k), ad, 'o', 'MarkerSize', 10, 'LineWidth', 1.6, 'Color', C.ok, 'MarkerFaceColor', mf, 'HandleVisibility', 'off');
end
function c = clean(c), for f = {'target', 'target_t'}, if isfield(c, f{1}) && isempty(c.(f{1})), c.(f{1}) = NaN; end, end, end
function f = fig(w, h)
    f = figure('Color', 'w', 'Position', [60 60 w h], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
end
function prep(ax), hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); ax.FontSize = 10; end
function save_(f, d, name), exportgraphics(f, fullfile(d, name), 'Resolution', 140); close(f); end

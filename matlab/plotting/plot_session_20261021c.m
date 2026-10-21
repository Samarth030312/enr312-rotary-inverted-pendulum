function plot_session_20261021c(outDir)
%PLOT_SESSION_20261021C  Figures of the late rig session of 2026-10-21 (firmware 2.3.2).
%
%   plot_session_20261021c()     writes results/figures/2026-10-21c_*.png
%   Sources: data/raw/EXP001/*20261021-19*.csv (free swings) and
%   data/raw/EXP024/EXP024_20261021-192231_swing-up_R08.csv, and
%   odyssix.sim.runCtrl for the simulation of the same swing-up (labelled).
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = fullfile(repo, 'results', 'figures'); end
    C = struct('rig', [0.10 0.35 0.80], 'sim', [0.55 0.55 0.58], 'pend', [0.85 0.33 0.10], ...
               'ok', [0.13 0.55 0.30], 'bad', [0.80 0.13 0.13]);
    hang = @(p) mod(p + 180, 360) - 180;  up = @(p) mod(180 - p + 180, 360) - 180;

    % ---- 1. the two free swings, with the dry-friction fit ---------------------------
    ids = ["EXP001_20261021-191934_free-swing_R03", "EXP001_20261021-192117_free-swing_R06"];
    f = fig(1400, 460); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:2
        D = odyssix.data.loadRun(ids(i)); r = pendulum_free_swing_fit(D.t, D.psi);
        ax = nexttile(tl); prep(ax);
        plot(ax, D.t, D.psi, 'Color', [0.8 0.8 0.8], 'LineWidth', 1);
        plot(ax, r.t + r.tStart, r.yDeg, '.', 'Color', C.pend, 'MarkerSize', 7);
        plot(ax, r.t + r.tStart, r.yFitDeg, 'Color', C.rig, 'LineWidth', 1.5);
        xregion(ax, r.tStart, r.tEnd, 'FaceColor', [0.93 0.95 1.0], 'HandleVisibility', 'off');
        legend(ax, {'whole record (hand on, releases)', 'free decay used', ...
            sprintf('fit: \\omega_g^2 %.1f, dry friction %.2f rad/s^2, rms %.2f°', r.wg2, r.coulomb, r.rmsDeg)}, 'Location', 'southwest');
        xlabel(ax, 't (s)'); ylabel(ax, '\psi (deg)');
        title(ax, sprintf('Free swing %s, motor off: release found at %.2f s', extractAfter(ids(i), 'swing_'), r.tStart), 'Interpreter', 'none');
    end
    save_(f, outDir, '2026-10-21c_free_swings.png');

    % ---- 2. the swing-up on 2.3.2 with the measured wg2, against its simulation ------
    D = odyssix.data.loadRun("EXP024_20261021-192231_swing-up_R08");
    c = odyssix.sim.defaults(24); c.wg2 = 48.5; c.seconds = 23;
    p = odyssix.sim.plant(5); p.wg2 = 47.1; p.Q = 60; p.coulomb = 0.37; p.bias = 0;
    S = odyssix.sim.runCtrl(c, p);
    f = fig(1400, 760); tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    kR = find(D.phase == 8, 1); kS = find(S.phase == 8, 1);
    ax = nexttile(tl); prep(ax);
    plot(ax, S.t, abs(hang(S.psi)), 'Color', C.sim, 'LineWidth', 2.0);
    plot(ax, D.t, abs(hang(D.psi)), 'Color', C.pend, 'LineWidth', 1.2);
    xline(ax, D.t(kR), '-', sprintf('rig caught %.2f s', D.t(kR)), 'Color', C.ok, 'LabelVerticalAlignment', 'bottom');
    if ~isempty(kS), xline(ax, S.t(kS), '--', sprintf('simulation %.2f s', S.t(kS)), 'Color', C.sim, 'LabelVerticalAlignment', 'middle'); end
    ylim(ax, [0 190]); ylabel(ax, '|\psi| from hanging (deg)'); legend(ax, {'simulation (identified pendulum)', 'rig'}, 'Location', 'southeast');
    title(ax, 'Swing-up on the rig, firmware 2.3.2 told the measured \omega_g^2 = 48.5: caught at the first try');
    ax = nexttile(tl); prep(ax);
    plot(ax, D.t, up(D.psi), 'Color', C.pend, 'LineWidth', 1.1); yline(ax, 0, ':');
    xline(ax, 19.62, '-', 'push 1 (recovered)', 'Color', [0.9 0.6 0.1], 'LabelVerticalAlignment', 'bottom');
    xline(ax, 22.66, '-', 'push 2 (lost)', 'Color', C.bad, 'LabelVerticalAlignment', 'bottom');
    ylim(ax, [-8 8]); xlim(ax, [D.t(kR) - 0.5, D.t(end)]); ylabel(ax, '\alpha from upright (deg)');
    title(ax, 'Balancing 18.8 s, \alpha rms 0.66°, then two deliberate pushes by hand: the first recovered, the second (larger, sustained) not');
    ax = nexttile(tl); prep(ax);
    plot(ax, D.t, D.rotor, 'Color', C.rig, 'LineWidth', 1.2); plot(ax, D.t, D.ref, '--', 'Color', [0.3 0.3 0.3]);
    xlim(ax, [D.t(kR) - 0.5, D.t(end)]); ylabel(ax, 'arm \theta (deg)'); xlabel(ax, 't (s)');
    legend(ax, {'arm', 'set-point'}, 'Location', 'northwest');
    title(ax, 'Arm: held where it caught for 2 s, then walked home while the upright trim learnt the offset');
    save_(f, outDir, '2026-10-21c_swingup_232_rig.png');

    % ---- 3. the pushes against the simulated recovery limit ---------------------------
    % simulation: the same firmware (2.3.2, exp 24 HOLD LQR) on the identified pendulum,
    % an instantaneous tap added to the pendulum rate 12 s after the catch
    p2 = odyssix.sim.plant(5); p2.wg2 = 48.4; p2.Q = 60; p2.coulomb = 0.37;
    c2 = odyssix.sim.defaults(24); c2.wg2 = 48.5; c2.seconds = 30;
    S0 = odyssix.sim.runCtrl(c2, p2); tc = S0.t(find(S0.phase == 8, 1));
    vs = 10:10:150; [pk, arm, kept] = deal(nan(size(vs)));
    for i = 1:numel(vs)
        Sx = odyssix.sim.runCtrl(c2, p2, struct('taps', [tc + 12, -vs(i)]));
        w = Sx.t > tc + 12; kept(i) = Sx.phase(end) == 8;
        pk(i) = max(abs(Sx.alpha(w))); arm(i) = max(Sx.rotor(w)) - min(Sx.rotor(w));
    end
    writetable(table(vs(:), kept(:), pk(:), arm(:), 'VariableNames', {'tap_deg_per_s', 'still_balancing', 'alpha_peak_deg', 'arm_excursion_deg'}), ...
        fullfile(fileparts(outDir), 'tables', 'PEND_sim_taps_swingup_lqr.csv'));
    a = up(D.psi); ad = gradient(a, D.t);
    P = [19.55 22.62]; rate = zeros(1, 2); apk = rate; armx = rate;
    for i = 1:2
        w = D.t >= P(i) & D.t <= P(i) + 0.3; rate(i) = max(abs(ad(w)));
        w = D.t >= P(i) & D.t <= P(i) + 3; apk(i) = max(abs(a(w))); armx(i) = max(D.rotor(w)) - min(D.rotor(w));
    end
    f = fig(1400, 520); tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl, 1, [2 1]); prep(ax);
    ok = kept == 1; lim = max(vs(ok));
    plot(ax, vs(ok), pk(ok), '-o', 'Color', C.sim, 'LineWidth', 1.6, 'MarkerFaceColor', C.sim);
    xregion(ax, lim + 5, 160, 'FaceColor', [1 0.9 0.9], 'HandleVisibility', 'off');
    text(ax, lim + 8, 2, {'simulation:', 'pendulum lost'}, 'Color', C.bad, 'FontSize', 9);
    plot(ax, rate(1), apk(1), 'o', 'MarkerSize', 11, 'LineWidth', 2, 'Color', C.ok, 'MarkerFaceColor', C.ok);
    plot(ax, rate(2), min(apk(2), 15), '^', 'MarkerSize', 11, 'LineWidth', 2, 'Color', C.bad, 'MarkerFaceColor', C.bad);
    text(ax, rate(1) + 3, apk(1), 'push 1: recovered', 'FontSize', 9, 'Color', C.ok);
    text(ax, rate(2) - 3, min(apk(2), 15), 'push 2: sustained 0.14 s, lost ', 'FontSize', 9, 'Color', C.bad, 'HorizontalAlignment', 'right');
    xlim(ax, [0 160]); ylim(ax, [0 16]); xlabel(ax, 'pendulum rate given by the push (deg/s)'); ylabel(ax, 'peak \alpha (deg)');
    legend(ax, {'simulation: instantaneous tap, same firmware and pendulum'}, 'Location', 'northwest');
    title(ax, sprintf('The balancing LQR recovers taps up to %d deg/s in simulation', lim));
    w = D.t > 19.3 & D.t < 23.1;
    ax = nexttile(tl, 2); prep(ax);
    plot(ax, D.t(w), a(w), '.-', 'Color', C.pend, 'MarkerSize', 8); ylabel(ax, '\alpha (deg)'); xlim(ax, [19.3 23.1]);
    title(ax, 'The two pushes on the rig, 50 Hz stream (2.3.3 records such events at 500 Hz)');
    ax = nexttile(tl, 4); prep(ax);
    plot(ax, D.t(w), D.u(w), '.-', 'Color', C.rig, 'MarkerSize', 6); yline(ax, [-1500 1500], ':');
    ylabel(ax, 'u (deg/s^2)'); xlabel(ax, 't (s)'); xlim(ax, [19.3 23.1]);
    save_(f, outDir, '2026-10-21c_pushes.png');
end

function f = fig(w, h)
    f = figure('Color', 'w', 'Position', [60 60 w h], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
end
function prep(ax), hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); ax.FontSize = 10; end
function save_(f, d, name), exportgraphics(f, fullfile(d, name), 'Resolution', 140); close(f); end

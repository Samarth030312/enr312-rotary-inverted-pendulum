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
    xline(ax, 19.62, '-', 'kick 1 (recovered)', 'Color', [0.9 0.6 0.1], 'LabelVerticalAlignment', 'bottom');
    xline(ax, 22.66, '-', 'kick 2 (lost)', 'Color', C.bad, 'LabelVerticalAlignment', 'bottom');
    ylim(ax, [-8 8]); xlim(ax, [D.t(kR) - 0.5, D.t(end)]); ylabel(ax, '\alpha from upright (deg)');
    title(ax, 'Balancing 18.8 s, \alpha rms 0.66°: a sudden kick at 19.6 s was recovered, a larger one at 22.7 s was not (|u| at its 1500 deg/s^2 limit)');
    ax = nexttile(tl); prep(ax);
    plot(ax, D.t, D.rotor, 'Color', C.rig, 'LineWidth', 1.2); plot(ax, D.t, D.ref, '--', 'Color', [0.3 0.3 0.3]);
    xlim(ax, [D.t(kR) - 0.5, D.t(end)]); ylabel(ax, 'arm \theta (deg)'); xlabel(ax, 't (s)');
    legend(ax, {'arm', 'set-point'}, 'Location', 'northwest');
    title(ax, 'Arm: held where it caught for 2 s, then walked home while the upright trim learnt the offset');
    save_(f, outDir, '2026-10-21c_swingup_232_rig.png');

    % ---- 3. the kick, sample by sample ------------------------------------------------
    w = D.t > 22.3 & D.t < 23.1; a = up(D.psi);
    f = fig(1100, 420); ax = axes(f); prep(ax);
    yyaxis(ax, 'left'); plot(ax, D.t(w), a(w), '.-', 'Color', C.pend, 'MarkerSize', 10); ylabel(ax, '\alpha (deg)');
    yyaxis(ax, 'right'); plot(ax, D.t(w), D.u(w), '.-', 'Color', C.rig, 'MarkerSize', 8); ylabel(ax, 'u (deg/s^2)');
    xline(ax, 22.66, ':'); xlabel(ax, 't (s)');
    title(ax, '\alpha goes from -0.15° to -7.35° in 0.14 s: about 60 rad/s^2, while gravity at that tilt gives < 1 rad/s^2. Smooth, so not an encoder glitch.');
    save_(f, outDir, '2026-10-21c_kick_detail.png');
end

function f = fig(w, h)
    f = figure('Color', 'w', 'Position', [60 60 w h], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
end
function prep(ax), hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); ax.FontSize = 10; end
function save_(f, d, name), exportgraphics(f, fullfile(d, name), 'Resolution', 140); close(f); end

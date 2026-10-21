function plot_session_20261021(outDir)
%PLOT_SESSION_20261021  Figures of the rig session of 2026-10-21 (firmware 2.2.0),
%   each against the simulation of the same configuration, and the 2.3.0
%   changes that the data motivated (simulated, labelled as such).
%
%   plot_session_20261021()          writes results/figures/2026-10-21_*.png
%   Sources: data/raw/EXP0nn/*20261021*.csv and their metadata; odyssix.sim.runCtrl.
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = fullfile(repo, 'results', 'figures'); end
    C = struct('rig', [0.10 0.35 0.80], 'sim', [0.55 0.55 0.58], 'pend', [0.85 0.33 0.10], ...
               'ok', [0.13 0.55 0.30], 'bad', [0.80 0.13 0.13], 'ref', [0.20 0.20 0.20]);
    runs = ["EXP024_20261021-141233_swing-up_R01", "EXP024_20261021-141322_swing-up_R02", ...
            "EXP024_20261021-141455_swing-up_R03"];
    hang = @(p) mod(p + 180, 360) - 180;  up = @(p) mod(180 - p + 180, 360) - 180;

    % ---- 1. swing-up: rig x3 vs simulation ----------------------------------------
    [D1, M1] = odyssix.data.loadRun(runs(1));
    pl = M1.plant_model; pl.nonlinear = true; pl.quant = true;
    c = M1.config; c.amp = 180; c.seconds = 25;
    S = odyssix.sim.runCtrl(c, pl);
    f = fig(1400, 760); tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    plot(ax, S.t, abs(hang(S.psi)), 'Color', C.sim, 'LineWidth', 2.4);
    for i = 1:3
        D = odyssix.data.loadRun(runs(i)); k = find(D.phase == 11, 1); D.t = D.t - D.t(k);
        plot(ax, D.t, abs(hang(D.psi)), 'LineWidth', 1.2);
    end
    yline(ax, 180, ':', 'upright', 'Color', C.ref); xlim(ax, [0 22]); ylim(ax, [0 190]);
    ylabel(ax, '|\psi| from hanging (deg)');
    legend(ax, {'simulation (same gains, Tutorial plant)', 'rig R01', 'rig R02', 'rig R03'}, 'Location', 'southeast');
    kS = find(S.phase == 8, 1);
    title(ax, sprintf(['Energy swing-up on the rig, 2026-10-21 (firmware 2.2.0): caught upright 3 of 3 at 7.1 / 7.1 / 8.0 s ' ...
        '(simulation of 2.3.0, stricter catch: %.1f s)'], S.t(kS)));
    ax = nexttile(tl); prep(ax);
    plot(ax, S.t, S.rotor, 'Color', C.sim, 'LineWidth', 2.4);
    for i = 1:3
        D = odyssix.data.loadRun(runs(i)); k = find(D.phase == 11, 1); D.t = D.t - D.t(k);
        plot(ax, D.t, D.rotor, 'LineWidth', 1.2);
    end
    xlim(ax, [0 22]); xlabel(ax, 't since the swing started (s)'); ylabel(ax, 'arm \theta (deg)');
    title(ax, 'Arm: pumping, the catch, then holding (R02 caught a pendulum still moving at 75 deg/s and fell)');
    save_(f, outDir, '2026-10-21_swingup_rig_vs_sim.png');

    % ---- 2. the kick (R01) and recovery in 2.3.0 ------------------------------------
    D = D1; k = find(D.t >= 20.6, 1); w = k:height(D);
    f = fig(1400, 520); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    yyaxis(ax, 'left'); plot(ax, D.t(w), up(D.psi(w)), '-o', 'MarkerSize', 3, 'LineWidth', 1.3); ylabel(ax, '\alpha from upright (deg)');
    yyaxis(ax, 'right'); plot(ax, D.t(w), D.u(w), 'LineWidth', 1.1); ylabel(ax, 'plant input u (deg/s^2)'); ylim(ax, [-1700 1700]);
    xline(ax, 21.10, '--', 'kick: +1.35° in 40 ms, arm still', 'LabelVerticalAlignment', 'bottom');
    xline(ax, 21.32, '-', 'abort: 200 ms saturated', 'Color', C.bad, 'LabelVerticalAlignment', 'top');
    xlabel(ax, 't (s)'); title(ax, 'Rig R01 after 14 s balanced: an external kick, then the 200 ms rule aborts a recovery');
    % simulation of firmware 2.3.0 holding upright, the same kind of kick
    c3 = odyssix.sim.defaults(23); c3.seq = 0; c3.seconds = 20;
    pb = odyssix.sim.plant(5); pb.bias = 0.5;
    Sk = odyssix.sim.runCtrl(c3, pb, struct('taps', [12 70]));
    ax = nexttile(tl); prep(ax); wk = Sk.t >= 11.5 & Sk.t <= 15;
    yyaxis(ax, 'left'); plot(ax, Sk.t(wk), Sk.alpha(wk), 'LineWidth', 1.3); ylabel(ax, '\alpha (deg)');
    yyaxis(ax, 'right'); plot(ax, Sk.t(wk), Sk.u(wk), 'LineWidth', 1.1); ylabel(ax, 'u (deg/s^2)'); ylim(ax, [-1700 1700]);
    xlabel(ax, 't (s)'); title(ax, sprintf('SIMULATION, firmware 2.3.0: a 70 deg/s tap in HOLD is recovered (%s)', ...
        ternary(strcmp(Sk.Properties.UserData.abort, 'NONE'), 'no abort', Sk.Properties.UserData.abort)));
    save_(f, outDir, '2026-10-21_kick_and_recovery.png');

    % ---- 3. the upright offset and the auto-trim -------------------------------------
    D3 = odyssix.data.loadRun(runs(3)); w = D3.phase == 8;
    a3 = up(D3.psi);
    f = fig(1400, 520); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    yyaxis(ax, 'left'); plot(ax, D3.t(w), movmean(a3(w), 100), 'LineWidth', 1.4); ylabel(ax, 'mean \alpha, 2 s window (deg)'); ylim(ax, [-0.5 1.5]);
    yyaxis(ax, 'right'); plot(ax, D3.t(w), D3.rotor(w), 'LineWidth', 1.2); ylabel(ax, 'arm \theta (deg), set-point 0'); ylim(ax, [-40 40]);
    xlabel(ax, 't (s)');
    am = mean(a3(w & D3.t > 12 & D3.t < 40)); th = mean(D3.rotor(w & D3.t > 12 & D3.t < 40));
    title(ax, sprintf('Rig R03 balancing: mean \\alpha %+.2f°, arm %+.1f° (LQR: \\theta = -k_3/k_1 \\cdot \\alpha = %+.1f°)', am, th, -382.789 / -10 * am));
    ax = nexttile(tl); prep(ax);
    cb = odyssix.sim.defaults(23); cb.seq = 0; cb.seconds = 60; pb = odyssix.sim.plant(5); pb.bias = 0.6;
    St = odyssix.sim.runCtrl(cb, pb);
    plot(ax, St.t, St.rotor, 'Color', C.ok, 'LineWidth', 1.6);
    yline(ax, -382.789 / -10 * -0.6, '--', 'without trim: k_3/k_1 \cdot 0.6° = 23°', 'Color', C.bad);
    yline(ax, 0, ':'); xlabel(ax, 't (s)'); ylabel(ax, 'arm \theta (deg)'); ylim(ax, [-30 30]);
    title(ax, 'SIMULATION, firmware 2.3.0: 0.6° encoder offset, the auto-trim (\tau 8 s) brings the arm home');
    save_(f, outDir, '2026-10-21_upright_offset_and_trim.png');

    % ---- 4. pendulum target ----------------------------------------------------------
    f = fig(1400, 520); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax); amps = [45 90 135]; lg = {};
    for a = amps
        c = odyssix.sim.defaults(24); c.amp = a; c.seconds = 20;
        Sa = odyssix.sim.runCtrl(c, odyssix.sim.plant(3));
        plot(ax, Sa.t, hang(Sa.psi), 'LineWidth', 1.1); lg{end+1} = sprintf('target %d°', a); %#ok<AGROW>
    end
    for a = amps, yline(ax, [-a a], ':', 'HandleVisibility', 'off'); end
    xlabel(ax, 't (s)'); ylabel(ax, '\psi from hanging (deg)'); legend(ax, lg, 'Location', 'southeast');
    title(ax, 'SIMULATION, firmware 2.3.0: pendulum target, swing to ±45 / ±90 / ±135° and hold that height');
    ax = nexttile(tl); prep(ax);
    c = odyssix.sim.defaults(24); c.amp = 0; c.seconds = 20; c0 = c;
    S0 = odyssix.sim.runCtrl(c, odyssix.sim.plant(3), struct('psi0', 40));
    c0.uon = 0; c0.kp = 0; c0.kd = 0;                           % no control: free decay
    Sf = odyssix.sim.runCtrl(c0, odyssix.sim.plant(3), struct('psi0', 40));
    plot(ax, Sf.t, hang(Sf.psi), 'Color', C.sim, 'LineWidth', 1.4);
    plot(ax, S0.t, hang(S0.psi), 'Color', C.pend, 'LineWidth', 1.4);
    xlabel(ax, 't (s)'); ylabel(ax, '\psi (deg)'); legend(ax, {'free decay (pivot friction only)', 'target 0: energy removed'});
    title(ax, 'Target 0 stops a 40° swing (inside 4° in ~9 s; free decay ~19 s)');
    save_(f, outDir, '2026-10-21_pendulum_target.png');

    % ---- 5. lab state feedback: step to 90 deg, rig vs sim ------------------------------
    [D5, M5] = odyssix.data.loadRun("EXP009_20261021-141841_lab-hang-statefeedback_R01");
    c = M5.config; c.seconds = 26; ev = M5.events; tS = ev(strcmp({ev.what}, 'step')).t;
    S5 = odyssix.sim.runCtrl(c, odyssix.sim.plant(3), struct('events', struct('t', tS, 'key', {'rrate', 'ref'}, 'val', {0, 90})));
    f = fig(1400, 460); ax = axes(f); prep(ax);
    plot(ax, S5.t, S5.ref, '--', 'Color', C.ref); plot(ax, S5.t, S5.rotor, 'Color', C.sim, 'LineWidth', 2.4);
    w5 = D5.t <= 26; plot(ax, D5.t(w5), D5.rotor(w5), 'Color', C.rig, 'LineWidth', 1.3);
    xlabel(ax, 't (s)'); ylabel(ax, 'arm \theta (deg)'); legend(ax, {'set-point', 'simulation', 'rig'}, 'Location', 'southeast');
    title(ax, sprintf('LAB, hanging, state feedback K = [%g %g]: STEP to 90° on the rig (final %.2f°) and in simulation (%.2f°)', ...
        c.k1, c.k2, mean(D5.rotor(D5.t > 15 & D5.t < 24)), mean(S5.rotor(S5.t > 15))));
    save_(f, outDir, '2026-10-21_lab_step90_rig_vs_sim.png');

    % ---- 6. Tutorial 7 impulses, rig vs sim -------------------------------------------
    [D7, M7] = odyssix.data.loadRun("EXP007_20261021-142025_t7-300-30_R01");
    S7 = odyssix.sim.runCtrl(M7.config, odyssix.sim.plant(5));
    r = odyssix.sim.impulseAverage(S7.t, S7.alpha, S7.rotor, S7.phase);
    q = odyssix.sim.impulseAverage(D7.t, up(D7.psi), D7.rotor, D7.phase);
    f = fig(1400, 460); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    plot(ax, r.t, r.alpha - mean(r.alpha(r.t < 0)), 'Color', C.sim, 'LineWidth', 2.4);
    plot(ax, q.t, q.alpha - mean(q.alpha(q.t < 0)), 'Color', C.pend, 'LineWidth', 1.4);
    xlabel(ax, 't after the impulse (s)'); ylabel(ax, '\alpha (deg)'); legend(ax, {sprintf('simulation (median of %d)', r.n), sprintf('rig (median of %d; 2 held a disturbance)', q.n)});
    title(ax, 'Tutorial 7: pendulum response to a 10° x 4 ms reference impulse (median over the impulses)');
    ax = nexttile(tl); prep(ax);
    plot(ax, r.t, r.rotor, 'Color', C.sim, 'LineWidth', 2.4); plot(ax, q.t, q.rotor, 'Color', C.rig, 'LineWidth', 1.4);
    xlabel(ax, 't after the impulse (s)'); ylabel(ax, 'arm \Delta\theta (deg)');
    title(ax, 'Arm response (median)');
    save_(f, outDir, '2026-10-21_t7_impulse_rig_vs_sim.png');
end

function f = fig(w, h)
    f = figure('Color', 'w', 'Position', [60 60 w h], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
end
function prep(ax), hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); ax.FontSize = 10; end
function save_(f, d, name), exportgraphics(f, fullfile(d, name), 'Resolution', 140); close(f); end
function s = ternary(c, a, b), if c, s = a; else, s = b; end, end

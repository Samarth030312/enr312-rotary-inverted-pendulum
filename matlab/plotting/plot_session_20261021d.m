function plot_session_20261021d(outDir)
%PLOT_SESSION_20261021D  Figures and tables of the last rig session of 2026-10-21 (firmware 2.3.3).
%
%   plot_session_20261021d()   writes results/figures/2026-10-21d_*.png and
%                              results/tables/PEND_free_swings.csv, PEND_pushes_20261021.csv
%   Sources: every free swing in data/raw/EXP001 (R03, R06-R10), the swing-ups
%   EXP024 R08, R09, R10, R15 and their 500 Hz records, and odyssix.sim.runCtrl
%   for the simulations (labelled as such).
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = fullfile(repo, 'results', 'figures'); end
    tDir = fullfile(repo, 'results', 'tables');
    C = struct('rig', [0.10 0.35 0.80], 'sim', [0.55 0.55 0.58], 'pend', [0.85 0.33 0.10], ...
               'ok', [0.13 0.55 0.30], 'bad', [0.80 0.13 0.13], 'k500', [0.50 0.20 0.70]);
    hang = @(p) mod(p + 180, 360) - 180;

    % ---- 1. six free swings ------------------------------------------------------------
    fs = ["EXP001_20261021-191934_free-swing_R03", "EXP001_20261021-192117_free-swing_R06", ...
          "EXP001_20261021-205447_free-swing_R07", "EXP001_20261021-205720_free-swing_R08", ...
          "EXP001_20261021-205757_free-swing_R09", "EXP001_20261021-205831_free-swing_R10"];
    f = fig(1500, 720); tl = tiledlayout(f, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    rows = {};
    for i = 1:numel(fs)
        D = odyssix.data.loadRun(fs(i)); r = pendulum_free_swing_fit(D.t, D.psi);
        T = periodFromPeaks(r.t, r.yDeg - r.offsetDeg);
        rows(end+1, :) = {char(fs(i)), r.tRelease, r.yDeg(1) - r.offsetDeg, r.wg2, r.coulomb, r.Q, r.rmsDeg, T, (2 * pi / T)^2}; %#ok<AGROW>
        ax = nexttile(tl); prep(ax);
        plot(ax, r.t, r.yDeg - r.offsetDeg, '.', 'Color', C.pend, 'MarkerSize', 6);
        plot(ax, r.t, r.yFitDeg - r.offsetDeg, 'Color', C.rig, 'LineWidth', 1.3);
        xlabel(ax, 't from the start of the decay (s)'); ylabel(ax, '\psi - rest (deg)');
        title(ax, sprintf('%s: \\omega_g^2 %.1f, rms %.2f°', extractAfter(fs(i), 'swing_'), r.wg2, r.rmsDeg), 'Interpreter', 'tex');
    end
    title(tl, 'Six free swings, motor off: the model (blue) fitted to each decay (orange dots, 50 Hz)');
    save_(f, outDir, '2026-10-21d_free_swings.png');
    FS = cell2table(rows, 'VariableNames', {'run_id', 't_release_s', 'start_deg', 'wg2_fit', 'coulomb_fit_rad_s2', ...
        'Q_fit', 'fit_rms_deg', 'period_peaks_s', 'wg2_from_period'});
    writetable(FS, fullfile(tDir, 'PEND_free_swings.csv'));

    % ---- 2. four swing-ups with the measured wg2 -----------------------------------------
    su = ["EXP024_20261021-192231_swing-up_R08", "EXP024_20261021-205318_swing-up_R09", ...
          "EXP024_20261021-205559_swing-up_R10", "EXP024_20261021-210043_swing-up_R15"];
    c = odyssix.sim.defaults(24); c.wg2 = 48.5; c.seconds = 12;
    p = odyssix.sim.plant(5); p.wg2 = 48.0; p.Q = 60; p.coulomb = 0.37;
    S = odyssix.sim.runCtrl(c, p); kS = find(S.phase == 8, 1);
    f = fig(1400, 480); ax = axes(f); prep(ax);
    plot(ax, S.t, abs(hang(S.psi)), 'Color', C.sim, 'LineWidth', 2.4);
    cols = lines(4); tc = zeros(1, 4);
    for i = 1:4
        D = odyssix.data.loadRun(su(i)); k = find(D.phase == 8, 1); tc(i) = D.t(k);
        w = D.t <= D.t(k) + 4;
        plot(ax, D.t(w), abs(hang(D.psi(w))), 'Color', cols(i, :), 'LineWidth', 1.1);
        plot(ax, D.t(k), abs(hang(D.psi(k))), 'o', 'Color', cols(i, :), 'MarkerFaceColor', cols(i, :), 'HandleVisibility', 'off');
    end
    yline(ax, 180, ':', 'HandleVisibility', 'off'); xlim(ax, [0 10]); ylim(ax, [0 190]);
    xlabel(ax, 't (s)'); ylabel(ax, '|\psi| from hanging (deg)');
    legend(ax, [{sprintf('simulation (caught %.2f s)', S.t(kS))}, arrayfun(@(i) sprintf('rig %s (caught %.2f s)', extractAfter(su(i), 'swing-up_'), tc(i)), 1:4, 'UniformOutput', false)], 'Location', 'southeast');
    title(ax, 'Swing-up with the measured \omega_g^2: four tries on the rig, four catches (dots: the moment of the catch)');
    save_(f, outDir, '2026-10-21d_swingups.png');

    % ---- 3. every push against the simulated recovery limit ------------------------------
    p2 = odyssix.sim.plant(5); p2.wg2 = 48.0; p2.Q = 60; p2.coulomb = 0.37;
    c2 = odyssix.sim.defaults(24); c2.wg2 = 48.5; c2.seconds = 30;
    S0 = odyssix.sim.runCtrl(c2, p2); t0 = S0.t(find(S0.phase == 8, 1));
    vs = 10:10:150; [pk, kept] = deal(nan(size(vs)));
    for i = 1:numel(vs)
        Sx = odyssix.sim.runCtrl(c2, p2, struct('taps', [t0 + 12, vs(i)]));
        w = Sx.t > t0 + 12; kept(i) = Sx.phase(end) == 8; pk(i) = max(abs(Sx.alpha(w)));
    end
    P = pushes50(su, hang);
    K = pushes500(fullfile(repo, 'data', 'raw', 'EXP024'));
    writetable(P, fullfile(tDir, 'PEND_pushes_20261021.csv'));
    f = fig(1200, 560); ax = axes(f); prep(ax);
    ok = kept == 1; lim = max(vs(ok));
    xregion(ax, lim + 5, 160, 'FaceColor', [1 0.9 0.9], 'HandleVisibility', 'off');
    plot(ax, vs(ok), pk(ok), '-', 'Color', C.sim, 'LineWidth', 2.4);
    rec = P.recovered == 1;
    plot(ax, abs(P.rate_deg_s(rec)), P.alpha_peak_deg(rec), 'o', 'Color', C.ok, 'MarkerFaceColor', C.ok, 'MarkerSize', 7);
    plot(ax, abs(P.rate_deg_s(~rec)), min(P.alpha_peak_deg(~rec), 15), '^', 'Color', C.bad, 'MarkerFaceColor', C.bad, 'MarkerSize', 10);
    plot(ax, abs(K.rate_deg_s), K.alpha_peak_deg, 's', 'Color', C.k500, 'MarkerSize', 10, 'LineWidth', 1.6);
    text(ax, lim + 8, 1.5, {'simulation:', 'lost'}, 'Color', C.bad, 'FontSize', 9);
    xlim(ax, [0 160]); ylim(ax, [0 16]);
    xlabel(ax, 'pendulum rate given by the push (deg/s)'); ylabel(ax, 'peak |\alpha| after the push (deg)');
    legend(ax, {'simulation: instantaneous tap, same firmware and pendulum', ...
        sprintf('rig: push recovered (%d)', nnz(rec)), sprintf('rig: push lost (%d)', nnz(~rec)), ...
        sprintf('the same pushes from the 500 Hz records (%d)', height(K))}, 'Location', 'northwest');
    title(ax, sprintf('Pushing the balanced pendulum: %d of %d recovered. Lost: a push held for 0.14 s (86 deg/s) and a 115 deg/s push, beyond the simulated %d', nnz(rec), height(P), lim));
    save_(f, outDir, '2026-10-21d_pushes.png');

    % ---- 4. one push at 500 Hz -----------------------------------------------------------
    R5 = readtable(fullfile(repo, 'data', 'raw', 'EXP024', 'EXP024_20261021-210043_swing-up_R15_500Hz_5.csv'));
    f = fig(1200, 560); tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    plot(ax, R5.t_s, R5.alpha_deg, '.', 'Color', C.k500, 'MarkerSize', 5);
    plot(ax, R5.t_s(1:10:end), R5.alpha_deg(1:10:end), 'o-', 'Color', C.pend, 'MarkerSize', 4);
    ylabel(ax, '\alpha (deg)'); legend(ax, {'500 Hz record (every control tick)', 'what the 50 Hz stream shows'}, 'Location', 'northeast');
    title(ax, 'The largest recorded push (R15, record 5) at 500 Hz. It began just before the window: PUSH MARK came 1.5 s later');
    ax = nexttile(tl); prep(ax);
    plot(ax, R5.t_s, R5.u, '-', 'Color', C.rig); yline(ax, [-1500 1500], ':');
    xlabel(ax, 't from the PUSH MARK (s)'); ylabel(ax, 'u (deg/s^2)');
    save_(f, outDir, '2026-10-21d_push_500hz.png');
end

function T = periodFromPeaks(t, y)
% median full period between crossings of the rest level, each crossing
% interpolated between the two samples around it (0.3 deg dead band)
    s = sign(y); s(abs(y) < 0.3) = 0; nz = find(s ~= 0); cr = nz([false; diff(s(nz)) ~= 0]);
    T = NaN; if numel(cr) < 3, return; end
    pr = nz(find(ismember(nz, cr)) - 1);                    % the sample before each crossing
    tz = t(pr) + (0 - y(pr)) ./ (y(cr) - y(pr)) .* (t(cr) - t(pr));
    T = median(tz(3:end) - tz(1:end-2));
end

function P = pushes50(ids, hang)
% every push after the catch: pendulum rate above 30 deg/s, events 0.5 s apart;
% the size of a push = peak rate within 200 ms of the onset. This underestimates
% the equivalent instantaneous tap: the controller starts braking the pendulum
% within about 50 ms, while the hand is still pushing.
    rows = {};
    for id = ids
        D = odyssix.data.loadRun(id); a = mod(180 - D.psi + 180, 360) - 180; r = gradient(a, D.t);
        k8 = find(D.phase == 8, 1); i = find(D.t > D.t(k8) + 3 & abs(r) > 30);
        if isempty(i), continue; end
        g = [1; find(diff(D.t(i)) > 0.5) + 1; numel(i) + 1];
        for j = 1:numel(g) - 1
            e = i(g(j):g(j + 1) - 1);
            % the push: peak rate within 200 ms of its onset (a hand push lasts about
            % 50-150 ms; later, a lost pendulum is falling)
            on = e(1); ee = on:min(on + 10, numel(r)); [~, m] = max(abs(r(ee))); k = ee(m);
            w = D.t >= D.t(e(1)) & D.t <= D.t(e(1)) + 2;
            lost = D.t(end) - D.t(k) < 2;                 % the run ended within 2 s of the push (an abort)
            rows(end+1, :) = {char(id), D.t(k), r(k), max(abs(a(w))), max(D.rotor(w)) - min(D.rotor(w)), ~lost}; %#ok<AGROW>
        end
    end
    P = cell2table(rows, 'VariableNames', {'run_id', 't_s', 'rate_deg_s', 'alpha_peak_deg', 'arm_swing_deg', 'recovered'});
    P.recovered = double(P.recovered);
end

function K = pushes500(dirR)
% the pushes inside the 500 Hz records: rate over 20 ms windows (one encoder
% count per tick would read as 75 deg/s)
    f = dir(fullfile(dirR, '*_500Hz_*.csv')); rows = {};
    for i = 1:numel(f)
        R = readtable(fullfile(f(i).folder, f(i).name)); a = R.alpha_deg; t = R.t_s;
        r = nan(size(a)); r(6:end-5) = (a(11:end) - a(1:end-10)) ./ (t(11:end) - t(1:end-10));
        on = find(abs(r) > 30, 1);
        if isempty(on), continue; end
        ee = on:min(on + 100, numel(r)); [~, m] = max(abs(r(ee))); k = ee(m);    % within 200 ms of the onset
        w = t >= t(k) - 0.1 & t <= t(k) + 1.5;
        rows(end+1, :) = {f(i).name, t(k), r(k), max(abs(a(w)))}; %#ok<AGROW>
    end
    K = cell2table(rows, 'VariableNames', {'record', 't_s', 'rate_deg_s', 'alpha_peak_deg'});
end

function f = fig(w, h)
    f = figure('Color', 'w', 'Position', [60 60 w h], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
end
function prep(ax), hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); ax.FontSize = 10; end
function save_(f, d, name), exportgraphics(f, fullfile(d, name), 'Resolution', 140); close(f); end

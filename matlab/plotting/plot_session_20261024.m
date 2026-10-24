function R = plot_session_20261024(outDir)
%PLOT_SESSION_20261024  Figures and tables of the rig session of 2026-10-24 (firmware 2.3.3).
%
%   R = plot_session_20261024()            writes results/figures/2026-10-24_*.png and
%                                          results/tables/2026-10-24_*.csv
%   R = plot_session_20261024(tempdir)     the same, somewhere else
%
%   Every rig trace is read from data/raw unchanged. Every simulation is
%   odyssix.sim.runTutorial / runCtrl (the firmware's control code) with the run's
%   own recorded configuration and live commands, on the rig's measured pendulum
%   (odyssix.rigParams: wg2 48.0, wr2 0.685, Q 60; dry friction 0.37 rad/s^2 for the
%   hanging runs and the swing-up, 0.12 for balancing, and the motor axis tilted 0.57 deg
%   for the upright runs, as the report finds).
%   Metrics are odyssix.sim.metrics on both, so rig and simulation are scored alike.
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = repo; end
    fig_ = fullfile(outDir, 'results', 'figures'); tab = fullfile(outDir, 'results', 'tables');
    if ~isfolder(fig_), mkdir(fig_); end
    if ~isfolder(tab), mkdir(tab); end
    C = struct('rig', [0.85 0.33 0.10], 'sim', [0.55 0.55 0.6], 'pend', [0.10 0.35 0.80], 'bad', [0.80 0.13 0.13], 'k', [0.15 0.15 0.15]);
    rp = odyssix.rigParams().pendulum;
    PM = struct('wg2', rp.wg2, 'wr2', rp.wr2, 'Q', mean(rp.QLargeSwing), 'coulomb', rp.coulomb, 'nonlinear', true, 'quant', true);
    up = @(p) mod(180 - p + 180, 360) - 180;  hang = @(p) mod(p + 180, 360) - 180;
    L = odyssix.data.listRuns('hardware'); L = L(startsWith(L.run_id, "EXP") & contains(L.run_id, "_20261024-"), :);
    L = sortrows(L, 'date_utc');
    R = struct();

    % ---- 1. every run: rig against simulation, same metric code ----------------------------
    rows = {}; SIMS = struct();
    for i = 1:height(L)
        id = char(L.run_id(i)); [D, M] = odyssix.data.loadRun(id);
        if ~isfield(M, 'config') || isempty(fieldnames(M.config)), continue; end    % free swing
        c = clean(M.config); D = fillCols(D);
        [S, note] = simulate(c, plantFor(c.exp, PM, rp), D, M);
        SIMS.(matlab.lang.makeValidName(id)) = S;
        mr = odyssix.sim.metrics(D, c); ms = odyssix.sim.metrics(S, c);
        for f = keyMetrics(c.exp)
            if isfield(mr, f{1})
                rows(end+1, :) = {id, c.exp, f{1}, num(mr.(f{1})), num(getf(ms, f{1})), note}; %#ok<AGROW>
            end
        end
    end
    R.metrics = cell2table(rows, 'VariableNames', {'run_id', 'experiment', 'metric', 'rig', 'simulation', 'simulation_note'});
    writetable(R.metrics, fullfile(tab, '2026-10-24_rig_vs_sim.csv'));

    % ---- 2. the hanging tutorials, arm traces ------------------------------------------------
    ids = pick(L, ["EXP001_20261024-104308", "EXP002_", "EXP003_", "EXP004_", "EXP009_20261024-105328", "EXP010_"]);
    names = {'T1 open-loop move (+5°)', 'T2 rotor PD: step, load, load off', 'T3 dual PD, hanging (2° step)', ...
             'T4 same gains', 'T9 pole placement K = [1 2]', 'T10 LQR K = [1 1.73]'};
    f = mkfig(1500, 760); tl = tiledlayout(f, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:numel(ids)
        [D, M] = odyssix.data.loadRun(char(ids(i))); S = SIMS.(matlab.lang.makeValidName(char(ids(i))));
        ax = nexttile(tl); prep(ax);
        if M.config.exp == 1, k0 = find(abs(S.rotor) > 0.05, 1); S.t = S.t - S.t(max(k0 - 1, 1)); end
        plot(ax, S.t, S.rotor, 'Color', C.sim, 'LineWidth', 2.2); plot(ax, D.t, D.rotor, 'Color', C.rig, 'LineWidth', 1.1);
        xlim(ax, [0 max(D.t(end), 1)]); title(ax, names{i}); xlabel(ax, 't (s)'); ylabel(ax, 'arm \theta (deg)');
        if i == 1, legend(ax, {'simulation (measured pendulum)', 'rig'}, 'Location', 'southeast'); end
    end
    title(tl, '2026-10-24, hanging tutorials: rig against the simulation of the same firmware and settings');
    save_(f, fig_, '2026-10-24_hanging_rig_vs_sim.png');

    % ---- 3. dry friction: the arm offset follows where the pendulum came to rest -------------
    rows = {};
    for day = ["20261021", "20261024"]
        for e = ["EXP003", "EXP004"]
            k = find(startsWith(L.run_id, e + "_" + day) | false, 1);
            Lall = odyssix.data.listRuns('hardware');
            k = find(startsWith(Lall.run_id, e + "_" + day + "-"), 1);
            if isempty(k), continue; end
            [D, M] = odyssix.data.loadRun(char(Lall.run_id(k))); c = M.config;
            for win = [7 9.5 2; 17 19 0]'
                w = D.t > win(1) & D.t < win(2); prest = mean(hang(D.psi(w)));
                rows(end+1, :) = {char(Lall.run_id(k)), win(3), prest, win(3) - c.kpp / c.kp * prest, mean(D.rotor(w))}; %#ok<AGROW>
            end
        end
    end
    R.friction = cell2table(rows, 'VariableNames', {'run_id', 'reference_deg', 'pendulum_rest_deg', 'predicted_arm_deg', 'measured_arm_deg'});
    writetable(R.friction, fullfile(tab, '2026-10-24_friction_offsets.csv'));
    f = mkfig(760, 560); ax = axes(f); prep(ax);
    is24 = contains(R.friction.run_id, '20261024');
    plot(ax, [-1.5 4], [-1.5 4], ':', 'Color', C.sim);
    plot(ax, R.friction.predicted_arm_deg(~is24), R.friction.measured_arm_deg(~is24), 'o', 'MarkerSize', 9, 'MarkerFaceColor', C.pend, 'MarkerEdgeColor', 'none');
    plot(ax, R.friction.predicted_arm_deg(is24), R.friction.measured_arm_deg(is24), 's', 'MarkerSize', 9, 'MarkerFaceColor', C.rig, 'MarkerEdgeColor', 'none');
    xlabel(ax, 'predicted arm angle: reference - (Kpp/Kp) \times pendulum rest angle (deg)'); ylabel(ax, 'measured arm angle (deg)');
    legend(ax, {'equal', '2026-10-21 (pendulum rested at -0.15 to -0.89°)', '2026-10-24 (rested at +0.30 to +0.52°)'}, 'Location', 'northwest');
    title(ax, {'T3 and T4 on two days: where friction leaves the pendulum sets where the PD holds the arm', ...
        sprintf('rms difference %.2f°', sqrt(mean((R.friction.predicted_arm_deg - R.friction.measured_arm_deg).^2)))});
    axis(ax, 'equal'); xlim(ax, [-1.5 4]); ylim(ax, [-1.5 4]);
    save_(f, fig_, '2026-10-24_friction_two_days.png');

    % ---- 4. first rig runs of on-off (EXP022) and the hand-released LQR (EXP023) ------------
    f = mkfig(1500, 760); tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    id = pick(L, "EXP022_"); [D, M] = odyssix.data.loadRun(id); S = SIMS.(matlab.lang.makeValidName(id));
    ax = nexttile(tl); prep(ax); plot(ax, S.t, S.rotor, 'Color', C.sim, 'LineWidth', 2); plot(ax, D.t, D.rotor, 'Color', C.rig);
    stairs(ax, D.t, D.ref, '--', 'Color', C.k); ylabel(ax, 'arm \theta (deg)'); legend(ax, {'simulation', 'rig', 'reference'}, 'Location', 'northwest');
    title(ax, 'On-off control (EXP022), first rig run: the arm never settles, as predicted (it swings about every set-point)');
    ax = nexttile(tl); prep(ax); plot(ax, S.t, hang(S.psi), 'Color', C.sim, 'LineWidth', 2); plot(ax, D.t, hang(D.psi), 'Color', C.pend);
    ylabel(ax, '\psi from hanging (deg)'); xlabel(ax, 't (s)');
    t1 = M.events(find(strcmp({M.events.what}, 'goto'), 1)).t;                      % on-off starts acting here
    R.onoff = [max(abs(hang(D.psi(D.t > t1)))), max(abs(hang(S.psi(S.t > t1 + S.t(1)))))];
    xline(ax, t1, ':', 'first set-point', 'Color', C.k);
    title(ax, sprintf(['pendulum: the 37° swing before %.0f s is a hand pluck (arm still, u = 0); ' ...
        'while on-off acts, peak %.1f° on the rig, %.1f° simulated'], t1, R.onoff(1), R.onoff(2)));
    id = pick(L, "EXP023_"); [D, M] = odyssix.data.loadRun(id); S = SIMS.(matlab.lang.makeValidName(id));
    ax = nexttile(tl); prep(ax); plot(ax, S.t, S.rotor, 'Color', C.sim, 'LineWidth', 2); plot(ax, D.t, D.rotor, 'Color', C.rig);
    stairs(ax, D.t, D.ref, '--', 'Color', C.k); ylabel(ax, 'arm \theta (deg)');
    title(ax, 'Upright LQR from a hand release (EXP023), first rig run: arm set-points while balancing');
    ax = nexttile(tl); prep(ax); hb = D.phase == 8;
    plot(ax, S.t, up(S.psi), 'Color', C.sim, 'LineWidth', 2); plot(ax, D.t, up(D.psi), 'Color', C.pend);
    ylim(ax, [-4 4]); ylabel(ax, '\alpha from upright (deg)'); xlabel(ax, 't (s)');
    title(ax, sprintf('pendulum while balancing: %.2f° rms on the rig, %.2f° simulated', ...
        sqrt(mean(up(D.psi(hb)).^2)), sqrt(mean(up(S.psi(S.phase == 8)).^2))));
    save_(f, fig_, '2026-10-24_onoff_and_lqr.png');

    % ---- 5. swing-up, and the arm creeping to a new set-point while balancing ---------------
    id = pick(L, "EXP024_"); [D, M] = odyssix.data.loadRun(id); S = SIMS.(matlab.lang.makeValidName(id));
    f = mkfig(1500, 700); tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    plot(ax, S.t, abs(hang(S.psi)), 'Color', C.sim, 'LineWidth', 2); plot(ax, D.t, abs(hang(D.psi)), 'Color', C.pend);
    ylabel(ax, 'pendulum height |\psi| (deg, 180 = upright)'); legend(ax, {'simulation', 'rig'}, 'Location', 'southeast');
    title(ax, sprintf('Swing-up: caught upright at %.2f s on the rig, %.2f s in the simulation (first sample of HOLD); balanced until STOP', catchTime(D), catchTime(S)));
    ax = nexttile(tl); prep(ax);
    plot(ax, S.t, S.rotor, 'Color', C.sim, 'LineWidth', 2); plot(ax, D.t, D.rotor, 'Color', C.rig); stairs(ax, D.t, D.ref, '--', 'Color', C.k);
    ylabel(ax, 'arm \theta (deg)'); xlabel(ax, 't (s)'); legend(ax, {'simulation', 'rig', 'arm set-point'}, 'Location', 'southwest');
    k = D.t > 67 & D.t < D.t(end) - 0.3; e = abs(D.rotor(k) - D.ref(k)); tk = D.t(k);
    pf = polyfit(tk(e > 1), log(e(e > 1)), 1); R.armTau = -1 / pf(1);
    title(ax, sprintf(['While balancing, the rig''s arm creeps to a new set-point (time constant %.0f s); ' ...
        'the simulation with the motor axis tilted %.2f° creeps the same way (section 5)'], R.armTau, odyssix.rigParams().rotor.tiltDeg));
    save_(f, fig_, '2026-10-24_swingup.png');

    % ---- 6. the lost PID run: arm steps, then the rotor Kd raised live ---------------------
    id = pick(L, "EXP006_20261024-110155"); [D, M] = odyssix.data.loadRun(id); K = odyssix.data.loadRecords(id, D);
    S = SIMS.(matlab.lang.makeValidName(id));
    f = mkfig(1500, 700); tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax);
    plot(ax, D.t, up(D.psi), 'Color', C.pend); plot(ax, S.t, up(S.psi), 'Color', C.sim, 'LineWidth', 1.6);
    for r = K, plot(ax, r.D.t, up(r.D.psi), '.', 'Color', C.k, 'MarkerSize', 3); end
    ev = M.events; for j = 1:numel(ev)
        if startsWith(ev(j).what, 'live'), xline(ax, ev(j).t, '-', sprintf('%s %g', ev(j).what, ev(j).value), 'Color', C.bad); end
    end
    ylim(ax, [-20 20]); ylabel(ax, '\alpha from upright (deg)');
    legend(ax, {'rig', 'simulation, same commands', '500 Hz record of the loss'}, 'Location', 'northwest');
    title(ax, sprintf('LAB upright PID: %s (simulation started with the preset rotor Kd 7.5, then the same live change)', lower(strrep(M.result, '_', ' '))));
    ax = nexttile(tl); prep(ax);
    plot(ax, D.t, D.rotor, 'Color', C.rig); plot(ax, S.t, S.rotor, 'Color', C.sim, 'LineWidth', 1.6); stairs(ax, D.t, D.ref, '--', 'Color', C.k);
    ylabel(ax, 'arm \theta (deg)'); xlabel(ax, 't (s)');
    title(ax, 'Arm: set-points of -30, 75 (several STEPs) and 50°, then rotor Kd 7.5 \rightarrow 20');
    save_(f, fig_, '2026-10-24_pid_lost.png');
    % the same run without the live gain change, in simulation: does it balance with Kd 7.5?
    c = clean(M.config); c.kd = odyssix.sim.defaults(6).kd; c.seconds = D.t(end) + 5;
    evs = toEvents(M, D, odyssix.sim.runCtrl(c, plantFor(6, PM, rp)), false);   % on the simulation's own clock
    S2 = odyssix.sim.runCtrl(c, plantFor(6, PM, rp), struct('events', evs));
    R.pidLostWithoutKd = any(S2.phase == 13);
    c.kd = 20; S3 = odyssix.sim.runCtrl(c, plantFor(6, PM, rp)); R.pidLostKd20 = any(S3.phase == 13); R.pidLostKd20At = S3.t(find(S3.phase == 13, 1));

    % ---- 8. balancing needs less friction than a free swing shows ---------------------------
    sw = {"EXP006_20261024-104854", "EXP007_20261024-105046", "EXP008_20261024-105226"; ...
          "EXP006_20261021-162252", "EXP007_20261021-142025", "EXP008_20261021-162641"};
    cs = [0 0.05 0.1 0.15 0.2 0.3 0.37]; nm = {'T6', 'T7', 'T8'}; Lall = odyssix.data.listRuns('hardware');
    rig = nan(2, 3); sim_ = nan(numel(cs), 3); ldr = nan(2, 1); lds = nan(numel(cs), 1);
    for j = 1:3
        for d = 1:2
            id = char(Lall.run_id(find(startsWith(Lall.run_id, sw{d, j}), 1))); [D, M] = odyssix.data.loadRun(id); c = clean(M.config);
            w = D.phase >= 2 & D.phase <= 8; rig(d, j) = sqrt(mean(up(D.psi(w)).^2));
            if j == 3, ldr(d) = getf(odyssix.sim.metrics(fillCols(D), c), 'ld_peak_deg'); end
        end
        for i = 1:numel(cs)
            pm = PM; pm.coulomb = cs(i); S = odyssix.sim.runCtrl(c, pm); w = S.phase >= 2 & S.phase <= 8;
            sim_(i, j) = sqrt(mean(up(S.psi(w)).^2));
            if j == 3, lds(i) = getf(odyssix.sim.metrics(S, c), 'ld_peak_deg'); end
        end
    end
    R.frictionSweep = array2table([cs' sim_ lds], 'VariableNames', {'coulomb', 'T6_alpha_rms', 'T7_alpha_rms', 'T8_alpha_rms', 'T8_load_peak'});
    writetable(R.frictionSweep, fullfile(tab, '2026-10-24_friction_sweep.csv'));
    f = mkfig(1500, 520); tl = tiledlayout(f, 1, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
    for j = 1:3
        ax = nexttile(tl); prep(ax); plot(ax, cs, sim_(:, j), 'o-', 'Color', C.sim, 'LineWidth', 1.6);
        yline(ax, rig(1, j), '-', '24 Oct', 'Color', C.rig, 'LineWidth', 1.4);
        if j ~= 2, yline(ax, rig(2, j), '--', '21 Oct (before the mechanics work)', 'Color', C.pend); end   % 21 Oct T7: live gain changes, lost
        xlabel(ax, 'dry friction in the simulation (rad/s^2)'); ylabel(ax, 'pendulum rms while balancing (deg)'); title(ax, nm{j});
    end
    ax = nexttile(tl); prep(ax); plot(ax, cs, lds, 'o-', 'Color', C.sim, 'LineWidth', 1.6);
    yline(ax, ldr(1), '-', '24 Oct', 'Color', C.rig, 'LineWidth', 1.4); yline(ax, ldr(2), '--', '21 Oct', 'Color', C.pend);
    xlabel(ax, 'dry friction in the simulation (rad/s^2)'); ylabel(ax, 'arm peak under the 60 deg/s^2 load (deg)'); title(ax, 'T8 load');
    title(tl, 'Balancing on 24 Oct is matched by 0.05-0.2 rad/s^2 of dry friction; on 21 Oct, before the mechanics were gone over, by about 0.3-0.37');
    save_(f, fig_, '2026-10-24_friction_balancing.png');

    % ---- 9. today's free swing: one fast cycle, then a straight-line decay -------------------
    f = mkfig(1500, 480); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); prep(ax); id = pick(L, "EXP001_20261024-104242"); D = odyssix.data.loadRun(id);
    plot(ax, D.t, hang(D.psi), 'Color', C.pend); xlabel(ax, 't (s)'); ylabel(ax, '\psi from hanging (deg)');
    title(ax, 'Free swing, motor off (released at 26°)');
    ax = nexttile(tl); prep(ax); mk = {'o', 's', 'd', '^'};
    fs = ["EXP001_20261021-205720", "EXP001_20261021-205757", "EXP001_20261021-205831", "EXP001_20261024-104242"];
    for i = 1:numel(fs)
        id = char(Lall.run_id(find(startsWith(Lall.run_id, fs(i)), 1))); D = odyssix.data.loadRun(id);
        [a, dec] = cycleDecay(D.t, hang(D.psi));
        plot(ax, a, dec, ['-' mk{i}], 'LineWidth', 1.1, 'DisplayName', regexprep(id, '^EXP001_(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2}).*_(R\d+)$', '$3 Oct $4:$5 $6'));
    end
    xlabel(ax, 'amplitude at the start of the cycle (deg)'); ylabel(ax, 'amplitude lost in that cycle (deg)'); legend(ax, 'Location', 'northwest');
    title(ax, 'The first cycle after release loses 7-10°; every later cycle about 2° (dry friction about 0.44 rad/s^2)');
    save_(f, fig_, '2026-10-24_free_swing_decay.png');

    % steady lean against arm angle, within each upright run of the day (HOLD, set-point
    % unchanged for > 6 s, last 3 s); the slope gives the tilt: lean = c_run - beta*sin(theta)
    [R.leans, R.tiltFit] = leanSlope(L, up);
    writetable(R.leans, fullfile(tab, '2026-10-24_steady_lean.csv'));
    % ---- 10. the slow arm while balancing: a tilted motor axis? ------------------------------
    % the steady lean in HOLD falls about 0.008 deg per degree of arm in every upright run of
    % the day; a motor axis tilted by beta moves the balance point by beta*sin(theta) (plant
    % option tiltDeg in odyssix.sim.runCtrl, not in the firmware)
    id = pick(L, "EXP023_"); [D, M] = odyssix.data.loadRun(id); c = clean(M.config);
    f = mkfig(1500, 520); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    axA = nexttile(tl); prep(axA); axB = nexttile(tl); prep(axB);
    plot(axA, D.t, D.rotor, 'Color', C.rig, 'LineWidth', 1.4); stairs(axA, D.t, D.ref, '--', 'Color', C.k);
    hb = D.phase == 8; plot(axB, D.t(hb), movmean(up(D.psi(hb)), 50), 'Color', C.rig, 'LineWidth', 1.4);
    rows = {}; col = {C.sim, C.pend};
    for tilt = [0 R.tiltFit]
        pp = plantFor(23, PM, rp); pp.tiltDeg = tilt;          % level (0) against the fitted tilt
        S0 = odyssix.sim.runCtrl(c, pp); [evs, sh] = toEvents(M, D, S0, true); cc = c; cc.seconds = D.t(end) + 1 + max(sh, 0);
        S = odyssix.sim.runCtrl(cc, pp, struct('events', evs)); S.t = S.t - sh;
        plot(axA, S.t, S.rotor, 'Color', col{1 + (tilt > 0)}, 'LineWidth', 1.6);
        hs = S.phase == 8; plot(axB, S.t(hs), movmean(up(S.psi(hs)), 50), 'Color', col{1 + (tilt > 0)}, 'LineWidth', 1.6);
        k = S.t > max(D.t(end) - 34, 0) & S.t < D.t(end) - 30; rows(end+1, :) = {tilt, mean(S.rotor(k))}; %#ok<AGROW>
    end
    legend(axA, {'rig', 'set-point', 'simulation, level base', sprintf('simulation, motor axis tilted %.2f°', R.tiltFit)}, 'Location', 'southeast');
    xlabel(axA, 't (s)'); ylabel(axA, 'arm \theta (deg)'); title(axA, 'Upright LQR (EXP023): the arm creeps to each new set-point');
    xlabel(axB, 't (s)'); ylabel(axB, '\alpha, 1 s mean (deg)'); title(axB, 'the steady lean changes with the arm angle');
    save_(f, fig_, '2026-10-24_tilt.png');

    % ---- 7. real time: the 50 Hz stream ------------------------------------------------------
    dts = [];
    for i = 1:height(L), D = odyssix.data.loadRun(char(L.run_id(i))); dts = [dts; diff(D.t)]; end %#ok<AGROW>
    R.stream = struct('samples', numel(dts) + height(L), 'median_ms', 1e3 * median(dts), 'max_ms', 1e3 * max(dts), ...
        'over_25ms', mean(dts > 0.025));
    f = mkfig(900, 420); ax = axes(f); prep(ax);
    histogram(ax, 1e3 * dts, 0:1:40, 'FaceColor', C.pend, 'EdgeColor', 'none'); set(ax, 'YScale', 'log');
    xlabel(ax, 'time between samples of the 50 Hz stream (ms)'); ylabel(ax, 'count');
    title(ax, sprintf('Real time, all %d runs of the day: median %.1f ms, longest %.0f ms, %.2f %% over 25 ms; no sample lost', ...
        height(L), R.stream.median_ms, R.stream.max_ms, 100 * R.stream.over_25ms));
    save_(f, fig_, '2026-10-24_stream_timing.png');
end

% ======================================================================================
function p = plantFor(e, PM, rp)
% balancing (small, slow motion) uses the friction that reproduces it (section 4)
    p = PM; if any(e == [5 6 7 8 23 24]), p.tiltDeg = odyssix.rigParams().rotor.tiltDeg; end   % the rig as it was today
    if any(e == [5 6 7 8 23]), p.coulomb = rp.coulombUpright; end
end

function tc = catchTime(S)
% first time the swing-up hands over to balancing (phase 8 HOLD)
    k = find(S.phase == 8, 1); tc = NaN; if ~isempty(k), tc = S.t(k); end
end

function [T, beta] = leanSlope(L, up)
    rows = {};
    for i = 1:height(L)
        id = char(L.run_id(i)); if ~any(startsWith(id, ["EXP006", "EXP007", "EXP008", "EXP023", "EXP024"])), continue; end
        D = odyssix.data.loadRun(id); if ~ismember('ref', D.Properties.VariableNames), continue; end
        k = 1;
        while k <= height(D)
            j = k; while j < height(D) && D.ref(j + 1) == D.ref(k) && D.phase(j + 1) == D.phase(k), j = j + 1; end
            if D.phase(k) == 8 && D.t(j) - D.t(k) > 6
                w = D.t >= D.t(j) - 3 & D.t <= D.t(j);
                rows(end+1, :) = {id, D.ref(k), mean(D.rotor(w)), mean(up(D.psi(w)))}; %#ok<AGROW>
            end
            k = j + 1;
        end
    end
    T = cell2table(rows, 'VariableNames', {'run_id', 'setpoint_deg', 'arm_deg', 'lean_deg'});
    % one offset per run (each run has its own datum), one common slope
    [g, ~] = findgroups(T.run_id); X = [-sind(T.arm_deg), double(g == unique(g)')];
    keep = arrayfun(@(q) nnz(g == q) >= 2, g);            % a run with one set-point says nothing about the slope
    b = X(keep, [true, any(X(keep, 2:end), 1)]) \ T.lean_deg(keep); beta = b(1);
end

function [a, dec] = cycleDecay(t, y)
% amplitude at each peak and what is lost by the next peak on the same side, after release
    k = find(abs(y) > 1 & [false; abs(y(2:end-1)) >= abs(y(1:end-2)) & abs(y(2:end-1)) > abs(y(3:end)); false]);
    a = []; dec = [];
    for i = 1:numel(k) - 2
        if sign(y(k(i))) == sign(y(k(i + 2))) && t(k(i + 2)) - t(k(i)) < 1.2 && abs(y(k(i))) - abs(y(k(i + 2))) > 0.6
            a(end+1) = abs(y(k(i))); dec(end+1) = abs(y(k(i))) - abs(y(k(i + 2))); %#ok<AGROW>
        end
    end
end

function [S, note] = simulate(c, PM, D, M)
% the firmware's code with this run's settings and live commands, on the measured pendulum
    note = '';
    if c.exp <= 5
        S = odyssix.sim.runTutorial(c, PM);
        if c.exp == 5, note = 'operator pushes not simulated'; end
        return
    end
    % align the live commands: the rig's clock starts at RUN, and an upright run waits
    % for the operator's release; the simulation releases at once
    % runs saved before 2026-10-24 evening keep the gains of the END of the run in
    % config; a gain changed live started at the app's preset (odyssix.sim.defaults)
    if isfield(M, 'events') && isstruct(M.events)
        d0 = odyssix.sim.defaults(c.exp);
        for e = M.events(:)'
            g = ''; if startsWith(e.what, 'live '), g = extractAfter(e.what, 'live '); end
            if ~isempty(g) && isfield(d0, g) && ~isfield(M, 'config_at_end'), c.(g) = d0.(g); note = ['start ' g ' from the preset; ']; end
        end
    end
    S0 = odyssix.sim.runCtrl(c, PM);
    [evs, sh] = toEvents(M, D, S0, true);
    c.seconds = max(c.seconds, D.t(end) + 1 + max(sh, 0));
    S = odyssix.sim.runCtrl(c, PM, struct('events', evs));
    S.t = S.t - sh;                                  % drawn on the rig's clock
    if ~isempty(evs), note = [note sprintf('%d live commands replayed', numel(evs))]; end
end

function [evs, sh] = toEvents(M, D, S, withGains)
% the run's live commands on the simulation's clock. A hand-released run (5-8, 23) is
% aligned at the release, because the operator holds the pendulum for a different
% time; every other run starts both clocks at RUN (sh = 0).
    evs = struct('t', {}, 'key', {}, 'val', {}); sh = 0;
    capture = any(getfield(M.config, 'exp') == [5 6 7 8 23]); %#ok<GFLD>
    kr = find(D.phase >= 2 & D.phase <= 8, 1); ks = find(S.phase >= 2 & S.phase <= 8, 1);
    if capture && ~isempty(kr) && ~isempty(ks), sh = S.t(ks) - D.t(kr); end
    if ~isfield(M, 'events') || ~isstruct(M.events), return; end
    for e = M.events(:)'
        key = '';
        switch e.what
            case {'goto', 'step'}, key = 'ref';
            otherwise
                if withGains && startsWith(e.what, 'live '), key = extractAfter(e.what, 'live '); end
        end
        if ~isempty(key), evs(end+1) = struct('t', e.t + sh, 'key', key, 'val', e.value); end %#ok<AGROW>
    end
end

function k = keyMetrics(e)
    switch e
        case 1, k = {'rotor_after_move_deg', 'pend_swing_pp_deg'};
        case 2, k = {'overshoot_pct', 'settling_s', 'dist_offset_deg'};
        case {3, 4}, k = {'overshoot_pct', 'pend_peak_deg'};
        case 5, k = {'alpha_peak_deg', 'balanced'};
        case 6, k = {'overshoot_pct', 'settling_s', 'alpha_rms_deg', 'balanced'};
        case 7, k = {'pend_peak_deg', 'rotor_peak_deg', 'alpha_rms_deg'};
        case 8, k = {'overshoot_pct', 'ld_peak_deg', 'ld_final_deg', 'alpha_rms_deg'};
        case {9, 10}, k = {'overshoot_pct', 'settling_s', 'final_value_deg', 'pend_peak_deg'};   % LAB R02: plucked by hand
        case 22, k = {};                                   % pend_peak counts a hand pluck: see the figure
        case 23, k = {'alpha_rms_deg', 'balanced'};
        case 24, k = {'t_catch_s', 'arm_max_deg', 'alpha_rms_up_deg'};
        otherwise, k = {};
    end
end

function id = pick(L, prefix)
    id = strings(size(prefix));
    for i = 1:numel(prefix), id(i) = L.run_id(find(startsWith(L.run_id, prefix(i)), 1)); end
    if numel(prefix) == 1, id = char(id); end
end
function D = fillCols(D)
    for f = {'ref', 'u', 'phase'}, if ~ismember(f{1}, D.Properties.VariableNames), D.(f{1}) = zeros(height(D), 1); end, end
end
function c = clean(c)
    for f = {'target', 'target_t', 'target_end'}, if isfield(c, f{1}) && isempty(c.(f{1})), c.(f{1}) = NaN; end, end
end
function v = num(x), if isempty(x), v = NaN; elseif islogical(x), v = double(x); else, v = double(x); end, end
function v = getf(s, f), if isfield(s, f), v = s.(f); else, v = NaN; end, end
function f = mkfig(w, h)
    f = figure('Color', 'w', 'Position', [40 40 w h], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
end
function prep(ax), hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); ax.FontSize = 10; end
function save_(f, d, name), exportgraphics(f, fullfile(d, name), 'Resolution', 140); close(f); end

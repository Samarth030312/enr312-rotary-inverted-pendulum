function P = pend_predictions(outDir)
%PEND_PREDICTIONS  Every simulated number quoted in docs/PEND_ANSWER_GUIDE.md and
%   experiments/EXP006..EXP023, computed in one place, written to CSV.
%
%   P = pend_predictions()                 % writes results/tables/
%   P = pend_predictions(outDir)
%
%   EXECUTION STATUS: simulation of the firmware (odyssix.sim.runCtrl,
%   identical to the C code, matlab/tests/test_sim_matches_firmware.m) with
%   the TUTORIAL plant values, NOT this rig's measured ones. These are
%   predictions to be compared with the rig, never results.
%   Base MATLAB only. About 2 minutes.
    if nargin < 1, outDir = fullfile(odyssix.repoRoot(), 'results', 'tables'); end
    if ~isfolder(outDir), mkdir(outDir); end
    rev = gitRev();
    plInv = odyssix.sim.plant(5); plSus = odyssix.sim.plant(3);

    % ---- 1. default metrics of every new experiment ---------------------------
    rows = {};
    for e = [6 7 8 9 10 21 22 23]
        c = odyssix.sim.defaults(e); pl = plSus; if any(e == [6 7 8 23]), pl = plInv; end
        o = struct(); if e == 21, o.psi0 = 20; end
        S = odyssix.sim.runCtrl(c, pl, o); m = odyssix.sim.metrics(S, c);
        f = fieldnames(m);
        for i = 1:numel(f), rows(end+1, :) = {sprintf('EXP%03d', e), f{i}, double(m.(f{i}))}; end %#ok<AGROW>
        lp = odyssix.sim.loop(c, pl);
        if ~isempty(lp)
            rows(end+1, :) = {sprintf('EXP%03d', e), 'slowest_cl_pole_per_s', -max(real(lp.cl))}; %#ok<AGROW>
            if isfield(lp, 'margins') && ~isempty(lp.margins)
                rows(end+1, :) = {sprintf('EXP%03d', e), 'phase_margin_deg', lp.margins.phiMdeg}; %#ok<AGROW>
                rows(end+1, :) = {sprintf('EXP%03d', e), 'ms_db', lp.margins.MsdB}; %#ok<AGROW>
            end
        end
    end
    M = cell2table(rows, 'VariableNames', {'experiment', 'metric', 'value'});
    P.metrics = M;

    % ---- 2. PEND sweeps ----------------------------------------------------------
    o = struct('seconds', 20);
    P.kpp = odyssix.pend.gainSweep(6, 'kpp', [0 50 100 150 160 170 180 200 300 600 1000], plInv, o);
    P.kdp = odyssix.pend.gainSweep(6, 'kdp', [0 5 10 15 20 30 60 100 150 200], plInv, o);
    P.kp  = odyssix.pend.gainSweep(6, 'kp',  [0 2 5 10 15 25 40 60], plInv, o);
    P.kd  = odyssix.pend.gainSweep(6, 'kd',  [0 2 5 7.5 15 30], plInv, o);
    P.ki  = odyssix.pend.gainSweep(6, 'ki',  [0 3 7.5 15 30], plInv, o);
    P.div = odyssix.pend.gainSweep(6, 'div', [1 5 10 20 25 30 35 40 50], plInv, o);
    % suspended swing stop (A5): three gain sets of P21
    base = odyssix.sim.defaults(21);
    sets = {'set 1 (6/4.8, 10/5)', struct(); 'set 2 (pendulum Kd 15)', struct('kdp', 15); ...
            'set 3 (rotor only)', struct('kpp', 0, 'kdp', 0); 'no control (free decay)', struct('kp', 0, 'kd', 0, 'kpp', 0, 'kdp', 0)};
    st = nan(size(sets, 1), 1);
    for i = 1:size(sets, 1)
        c = base; f = fieldnames(sets{i, 2}); for j = 1:numel(f), c.(f{j}) = sets{i, 2}.(f{j}); end
        c.seconds = 30;
        m = odyssix.sim.metrics(odyssix.sim.runCtrl(c, plSus, struct('psi0', 20)), c);
        st(i) = m.stop_time_s;
    end
    P.swingStop = table(sets(:, 1), st, 'VariableNames', {'gains', 'stop_time_s'});
    % taps (A7): add v deg/s to the pendulum rate once balancing in HOLD
    vs = [20 40 60 80 100 120 150];
    [peak, rec, kept, armMove] = deal(nan(numel(vs), 1));
    c = odyssix.sim.defaults(6); c.seconds = 45;
    for i = 1:numel(vs)
        S = odyssix.sim.runCtrl(c, plInv, struct('taps', [38 vs(i)]));
        r = odyssix.pend.recovery(S.t, S.alpha, 38, 1, 45);
        peak(i) = r.peakDeg; rec(i) = r.recoverS;
        kept(i) = strcmp(S.Properties.UserData.abort, 'NONE');
        w = S.t >= 38; armMove(i) = max(abs(S.rotor(w) - S.rotor(find(w, 1))));
    end
    P.taps = table(vs(:), kept, peak, rec, armMove, 'VariableNames', ...
        {'tap_deg_per_s', 'still_balancing', 'alpha_peak_deg', 'recovery_s', 'arm_excursion_deg'});
    % quantisation and the D filter (C11, Q8)
    S = odyssix.sim.runCtrl(odyssix.sim.defaults(6), plInv);
    w = S.phase >= 2 & S.phase <= 8;
    d = odyssix.pend.derivativeNoise(S.t(w), S.alpha(w), 10, 8);
    P.dnoise = table(d.countRateDegS, d.rmsRaw, d.rmsFilt, d.rmsMA, 1e3 * d.lagFiltS, 1e3 * d.lagMAS, ...
        'VariableNames', {'one_count_deg_s', 'raw_rms_deg_s', 'filtered_rms_deg_s', 'ma8_rms_deg_s', 'filter_lag_ms', 'ma8_lag_ms'});
    % unstable pole (C9) and swing-up (C12)
    u = odyssix.pend.unstablePole(plInv);
    P.pole = table(u.p, u.doublingS, u.Lsimple, 'VariableNames', {'p_rad_s', 'doubling_s', 'L_simple_m'});
    P.swingup = pend_swingup_study(plInv, struct('plot', false));
    % LQR Q/R trade-off (C10)
    [A, B] = odyssix.ctrl.pendulumModel('inverted', plInv);
    qr = {[1 1 10 1], 0.01; [1 1 10 1], 0.1; [1 1 10 1], 0.001; [1 1 100 1], 0.01; [10 1 10 1], 0.01};
    lq = {};
    for i = 1:size(qr, 1)
        K = odyssix.ctrl.lqr(A, B, diag(qr{i, 1}), qr{i, 2});
        c = odyssix.sim.defaults(23); c.k1 = K(1); c.k2 = K(2); c.k3 = K(3); c.k4 = K(4);
        S = odyssix.sim.runCtrl(c, plInv); m = odyssix.sim.metrics(S, c);
        w = S.phase >= 2 & S.phase <= 8;
        lq(end+1, :) = {mat2str(qr{i, 1}), qr{i, 2}, mat2str(round(K, 3)), m.settling_s, m.alpha_rms_deg, ...
                        max(abs(S.u(w))), strcmp(S.Properties.UserData.abort, 'NONE')}; %#ok<AGROW>
    end
    P.lqr = cell2table(lq, 'VariableNames', {'Q_diag', 'R', 'K', 'settling_s', 'alpha_rms_deg', 'u_peak', 'balanced'});

    % ---- write --------------------------------------------------------------------
    hdr = sprintf('# SIMULATION (firmware-exact, Tutorial plant values; NOT measured). rev %s, %s', ...
        rev, char(datetime('now', 'Format', 'yyyy-MM-dd')));
    writeT(fullfile(outDir, 'EXP006-023_sim_metrics.csv'), M, hdr);
    f = {'kpp', 'kdp', 'kp', 'kd', 'ki', 'div', 'swingStop', 'taps', 'dnoise', 'pole', 'swingup', 'lqr'};
    for i = 1:numel(f)
        writeT(fullfile(outDir, sprintf('PEND_sim_%s.csv', f{i})), P.(f{i}), hdr);
    end
    P.rev = rev;
    fprintf('pend_predictions: wrote %d tables to %s (rev %s)\n', numel(f) + 1, outDir, rev);
end

function writeT(path, T, hdr)
    tmp = [tempname '.csv']; writetable(T, tmp);
    fid = fopen(path, 'w'); fprintf(fid, '%s\n', hdr); fprintf(fid, '%s', fileread(tmp)); fclose(fid);
    delete(tmp);
end

function r = gitRev()
    [st, r] = system(sprintf('git -C "%s" rev-parse --short HEAD', odyssix.repoRoot()));
    if st ~= 0, r = 'unknown'; end
    r = strtrim(r);
end

function ok = e2e_lab()
%E2E_LAB  enr312_lab end to end: every mission in simulation, then the rig
%   EMULATOR (the firmware's own C code behind the serial protocol) driven
%   through the app: runs, live set-points and gains, swing-up, free swing,
%   automatic recording and replay. SYNTHETIC: no hardware. About 4 minutes.
    R = {};
    app = enr312_lab(); c0 = onCleanup(@() delete(app.fig));
    % ---- simulation: every mission and preset, LAB combinations -------------------
    for k = 1:10
        app.select(k);
        for p = app.ui.preset.Items
            app.preset(p{1}); S = app.result();
            okS = ~isempty(S) && (~strcmp(S.Properties.UserData.state, 'ABORTED') || contains(p{1}, 'falls'));
            c = S.Properties.UserData.cfg;                      % the simulated run used the preset as written
            okS = okS && ~contains(app.ui.say.Text, 'outside its slider') && c.step == app.ui.step.Value;
            R(end+1, :) = {sprintf('sim T%d  %s', k, p{1}), okS, S.Properties.UserData.state}; %#ok<AGROW>
        end
    end
    combos = {'hanging', 'PID'; 'hanging', 'State feedback'; 'hanging', 'On-off'; 'upright', 'PID'; 'upright', 'LQR'};
    for i = 1:size(combos, 1)
        app.lab(combos{i, :}); S = app.result();
        R(end+1, :) = {sprintf('sim LAB %s %s', combos{i, :}), ~strcmp(S.Properties.UserData.abort, 'PENDULUM_LOST'), S.Properties.UserData.state}; %#ok<AGROW>
    end
    app.swingUp(); S = app.result();
    R(end+1, :) = {'sim SWING UP caught and balancing', any(S.phase == 8) && S.phase(end) == 8, sprintf('caught %.1f s', S.t(find(S.phase == 8, 1)))};

    % ---- emulator ----------------------------------------------------------------
    app.startEmulator(); L = app.link;
    waitFor(@() L.n > 20 && L.protocol == 5, 8);
    R(end+1, :) = {'emulator speaks protocol 5', L.protocol == 5, sprintf('protocol %d', L.protocol)};
    app.armNoPrompt(); waitFor(@() strcmp(L.state, 'ARMED'), 3);
    app.send('s'); waitFor(@() strcmp(L.state, 'RUNNING'), 3);
    R(end+1, :) = {'ARM, START -> RUNNING', strcmp(L.state, 'RUNNING'), L.state};
    truth = @() setPlant(app);

    % T2: run, auto-saved, rig = sim
    app.select(2); truth(); before = app.lastSaved();
    app.runRig(); waitFor(@() ~strcmp(app.lastSaved(), before), 30);
    id = app.lastSaved(); [D, M] = odyssix.data.loadRun(id);
    ms = odyssix.sim.metrics(app.result(), odyssix.sim.defaults(2));
    R(end+1, :) = {'T2 run saved automatically (csv + json)', ~strcmp(id, before) && height(D) > 100 && isfield(M, 'config'), id};
    R(end+1, :) = {'T2 rig overshoot = sim (3 %)', abs(M.metrics.overshoot_pct - ms.overshoot_pct) < 3, ...
                   sprintf('rig %.1f %%, sim %.1f %%', M.metrics.overshoot_pct, ms.overshoot_pct)};

    % T9: state feedback
    app.select(9); truth(); before = app.lastSaved();
    app.runRig(); waitFor(@() ~strcmp(app.lastSaved(), before), 45);
    [~, M] = odyssix.data.loadRun(app.lastSaved()); ms = odyssix.sim.metrics(app.result(), odyssix.sim.defaults(9));
    R(end+1, :) = {'T9 rig settling = sim (0.3 s)', abs(M.metrics.settling_s - ms.settling_s) < 0.3, ...
                   sprintf('rig %.2f s, sim %.2f s', M.metrics.settling_s, ms.settling_s)};

    % LAB hanging PID: pluck, stop the swing, go to 20, live gain, stop
    app.lab('hanging', 'PID'); truth(); before = app.lastSaved();
    app.send('!'); pause(0.8); app.runRig(); waitFor(@() ~isempty(app.rigData()) && height(app.rigData()) > 60, 6);
    if isempty(app.rigData())                           % the run did not start: say why, do not crash
        R(end+1, :) = {'LAB hanging: run started', false, app.ui.say.Text}; ok = report(R); return;
    end
    pauseUI(6); app.gotoAngle(20); pauseUI(5);
    app.set('kdp', 8); waitFor(@() isfield(L.cfg, 'kdp') && L.cfg.kdp == 8, 2);
    R(end+1, :) = {'LAB hanging: live gain echoed', isfield(L.cfg, 'kdp') && L.cfg.kdp == 8, sprintf('kdp %g', L.cfg.kdp)};
    H = app.rigData();
    R(end+1, :) = {'LAB hanging: arm holds 20 deg', abs(mean(H.rotor(end-25:end)) - 20) < 0.5, sprintf('%.3f deg', mean(H.rotor(end-25:end)))};
    % PUSH MARK: the firmware's 500 Hz crash record (2.3.3) comes back and is kept with the run
    app.pushMark(); pauseUI(3);
    app.stopRun(); waitFor(@() ~strcmp(app.lastSaved(), before), 6);
    [~, M] = odyssix.data.loadRun(app.lastSaved());
    ev = M.events; if isstruct(ev), ev = {ev.what}; end
    R(end+1, :) = {'LAB hanging: saved with its events', any(strcmp(ev, 'goto')) && any(strcmp(ev, 'live kdp')) && any(strcmp(ev, 'push (operator)')), strjoin(ev, ', ')};
    kf = dir(fullfile(odyssix.repoRoot(), 'matlab', 'data', 'synthetic', 'EXP021', [app.lastSaved() '_500Hz_*.csv']));
    okK = numel(kf) == 1; msgK = 'no 500 Hz file';
    if okK
        K = readtable(fullfile(kf(1).folder, kf(1).name));
        okK = height(K) == 1000 && all(diff(K.tick) == 1) && abs(K.t_s(1) + 1.498) < 1e-9 && abs(K.t_s(end) - 0.5) < 1e-9;
        msgK = sprintf('%d samples, %.3f .. %.3f s', height(K), K.t_s(1), K.t_s(end));
    end
    R(end+1, :) = {'PUSH MARK: 500 Hz record, -1.5..0.5 s, saved with the run', okK, msgK};

    % pendulum target: swing to 90, then live target 0 stops it
    waitFor(@() abs(L.table().psi_deg(end)) < 3 && abs(L.table().psi_deg(end - 25)) < 3, 40);
    before = app.lastSaved(); app.pendulumTarget(90, true);
    pauseUI(14); H = app.rigData(); w = H.t > H.t(end) - 4;
    pk = max(abs(mod(H.psi(w) + 180, 360) - 180));
    R(end+1, :) = {'PENDULUM target 90: swings to 90 (6)', abs(pk - 90) < 6, sprintf('%.1f deg, arm max %.1f', pk, max(abs(H.rotor)))};
    app.pendulumTarget(0, true); pauseUI(14); H = app.rigData(); w = H.t > H.t(end) - 3;
    pk = max(abs(mod(H.psi(w) + 180, 360) - 180));
    R(end+1, :) = {'PENDULUM target 0 (live): the swing stops (< 5)', pk < 5, sprintf('%.1f deg', pk)};
    app.stopRun(); waitFor(@() ~strcmp(app.lastSaved(), before), 6);
    [~, M] = odyssix.data.loadRun(app.lastSaved());
    ev = M.events; if isstruct(ev), ev = {ev.what}; end
    R(end+1, :) = {'PENDULUM run saved with the live target change', any(strcmp(ev, 'pendulum target')), strjoin(ev, ', ')};

    % LAB upright LQR: hand capture, balance, go to -20
    app.lab('upright', 'LQR'); truth(); waitFor(@() abs(L.table().psi_deg(end)) < 3, 20);
    app.send('^'); waitFor(@() any(contains(L.lines, 'held upright')), 2); pause(0.8); before = app.lastSaved();
    app.runRig(); waitFor(@() ~isempty(app.rigData()) && app.rigData().phase(end) == 8, 15);
    H = app.rigData();
    R(end+1, :) = {'LAB upright LQR: released into HOLD', ~isempty(H) && H.phase(end) == 8, sprintf('phases %s', mat2str(unique(H.phase)'))};
    app.gotoAngle(-20); pauseUI(6); H = app.rigData();
    R(end+1, :) = {'LAB upright LQR: arm holds -20 deg (1.5)', abs(mean(H.rotor(end-25:end)) + 20) < 1.5 && H.phase(end) == 8, sprintf('%.2f deg', mean(H.rotor(end-25:end)))};
    app.stopRun(); waitFor(@() ~strcmp(app.lastSaved(), before), 6);

    % swing-up
    % after the upright run the pendulum falls; Q 24 needs ~30 s to settle below 2 deg
    waitFor(@() abs(L.table().psi_deg(end)) < 2 && abs(L.table().psi_deg(end - 25)) < 2, 70);
    before = app.lastSaved(); app.swingUp(true);
    waitFor(@() ~isempty(app.rigData()) && app.rigData().phase(end) == 8, 35); pauseUI(9);   % 2 s hold + walk home
    H = app.rigData(); a = mod(180 - H.psi(end - 25:end) + 180, 360) - 180;
    R(end+1, :) = {'SWING UP caught, balancing, arm home', H.phase(end) == 8 && max(abs(a)) < 3 && abs(H.rotor(end)) < 10, ...
                   sprintf('caught %.1f s, alpha %.2f, arm %.1f', H.t(find(H.phase == 8, 1)), max(abs(a)), H.rotor(end))};
    app.stopRun(); waitFor(@() ~strcmp(app.lastSaved(), before), 8);
    [~, M] = odyssix.data.loadRun(app.lastSaved());
    R(end+1, :) = {'SWING UP saved with t_catch', isfield(M.metrics, 't_catch_s') && isfinite(M.metrics.t_catch_s), app.lastSaved()};

    % free swing (SAFE), saved with the fit
    app.abort(); waitFor(@() strcmp(L.state, 'SAFE'), 3);
    waitFor(@() abs(L.table().psi_deg(end)) < 3, 30);
    before = app.lastSaved(); app.send('!'); pause(0.2); app.record();
    waitFor(@() ~strcmp(app.lastSaved(), before), 20);
    [~, M] = odyssix.data.loadRun(app.lastSaved());
    R(end+1, :) = {'FREE SWING saved: wg2 within 2 % of the emulator', isfield(M.metrics, 'wg2_fit') && abs(M.metrics.wg2_fit / 56.4 - 1) < 0.02, ...
                   sprintf('wg2 %.2f, L %.3f m, zeta %.4f', M.metrics.wg2_fit, M.metrics.L_simple_m, M.metrics.zeta)};

    % replay
    try, app.replay(app.lastSaved()); okR = true; msg = 'loaded'; catch e, okR = false; msg = e.message; end
    R(end+1, :) = {'REPLAY of a saved run', okR, msg};
    R(end+1, :) = {'state SAFE at the end', strcmp(L.state, 'SAFE'), L.state};

    ok = report(R);
end
function ok = report(R)
    fprintf('\nenr312_lab end to end (simulation + EMULATOR, synthetic)\n%s\n', repmat('-', 1, 96));
    for i = 1:size(R, 1), fprintf('  %-52s %-5s %s\n', R{i, 1}, pf(R{i, 2}), R{i, 3}); end
    n = sum([R{:, 2}]); fprintf('%s\n  %d / %d passed\n\n', repmat('-', 1, 96), n, size(R, 1));
    ok = n == size(R, 1);
end
function setPlant(app)
    app.set('L', 9.81 / (56.4 * 0.6805)); app.set('Q', 24); app.set('r', 0.803 * 9.81 / 56.4);
end
function waitFor(cond, tmax), t0 = tic; while toc(t0) < tmax, try, if cond(), return; end, catch, end, pause(0.05); drawnow; end, end
function pauseUI(s), t0 = tic; while toc(t0) < s, pause(0.05); drawnow; end, end
function s = pf(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end

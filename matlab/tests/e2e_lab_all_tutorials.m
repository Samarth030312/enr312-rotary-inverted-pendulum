function ok = e2e_lab_all_tutorials()
%E2E_LAB_ALL_TUTORIALS  enr312_lab end to end: every tutorial in simulation AND
%   on the rig EMULATOR (the firmware's control code), compared with the same
%   metrics. SYNTHETIC: no hardware. About 2 minutes, real time.
    R = {};
    app = enr312_lab(); c = onCleanup(@() close(app.fig));
    % --- simulation: every tutorial and preset runs and is sane ---------------
    for k = 1:5
        app.select(k);
        for p = app.ui.preset.Items
            app.preset(p{1}); S = app.result();
            ok = ~isempty(S) && ~strcmp(S.Properties.UserData.state, 'ABORTED');
            R(end+1, :) = {sprintf('sim T%d %s', k, p{1}), ok, S.Properties.UserData.state}; %#ok<AGROW>
        end
    end
    % --- T5 aborted before balancing (rig 2026-10-12): metrics must not throw,
    %     an error there stopped the app's timer and froze the display
    A = table((0:0.02:0.1)', zeros(6, 1), 180 * ones(6, 1), zeros(6, 1), zeros(6, 1), [0 0 0 5 5 5]', ...
              'VariableNames', {'t', 'rotor', 'psi', 'u', 'ref', 'phase'});
    try, mA = odyssix.sim.metrics(A, odyssix.sim.defaults(5)); okA = ~mA.balanced; msgA = 'ok';
    catch e, okA = false; msgA = e.message; end
    R(end+1, :) = {'metrics survive a T5 abort before balancing', okA, msgA};
    % --- emulator: connect, arm, start ------------------------------------------
    app.startEmulator(); L = app.link;
    waitFor(@() L.n > 20 && L.protocol == 2, 8);
    R(end+1, :) = {'emulator speaks protocol 2', L.protocol == 2, sprintf('%d samples', L.n)};
    app.armNoPrompt(); waitFor(@() strcmp(L.state, 'ARMED'), 3);
    app.send('s'); waitFor(@() strcmp(L.state, 'RUNNING'), 3);
    R(end+1, :) = {'ARM, START -> RUNNING', strcmp(L.state, 'RUNNING'), L.state};
    % datum gate: a pendulum far from its datum must not start a run
    app.select(1); app.send('!'); waitFor(@() max(abs(L.table().psi_deg(end-5:end))) > 15, 3);
    rot0 = L.table().rotor_deg(end);
    app.runRig(); t0 = tic; while toc(t0) < 1, pause(0.05); drawnow; end
    refused = contains(app.ui.link.Text, 'Pendulum reads') && L.table().rotor_deg(end) == rot0;
    R(end+1, :) = {'Run refused while pendulum is off its datum', refused, app.ui.link.Text};
    waitFor(@() L.n > 0 && abs(L.table().psi_deg(end)) < 3 && abs(L.table().psi_deg(end-25)) < 3, 25);
    app.select(5); rot0 = L.table().rotor_deg(end); app.runRig(); pause(0.5);
    R(end+1, :) = {'T5 refused while the pendulum hangs', contains(app.ui.link.Text, 'UPRIGHT') && ...
                   L.table().rotor_deg(end) == rot0 && ~contains(L.runEvent, 'GO'), app.ui.link.Text};
    % plant sliders = emulator truth, so sim and "rig" should agree
    for k = [1 2 3 5]
        app.select(k); app.set('L', 9.81 / (56.4 * 0.6805)); app.set('Q', 24); app.set('r', 0.803 * 9.81 / 56.4);
        waitFor(@() strcmp(L.state, 'RUNNING') && ~contains(char(app.ui.stopRun.Enable), 'on'), 10);
        if k == 5, app.send('^'); waitFor(@() any(contains(L.lines, 'held upright')), 2); pause(0.8); end   % gate: upright 0.5 s
        app.runRig();
        waitFor(@() contains(L.runEvent, 'GO') || contains(L.runEvent, 'RUN') || k == 1, 3);
        dur = struct('d1', 9, 'd2', 21, 'd3', 21, 'd5', 22); tmax = dur.(sprintf('d%d', k));
        t0 = tic; while toc(t0) < tmax, pause(0.1); drawnow; end
        if k == 5, L.stopRun(); waitFor(@() contains(L.runEvent, 'FINISHED'), 5); pause(0.5); end
        H = app.rigData(); S = app.result(); cfg = odyssix.sim.defaults(k);
        cfg.kp = app.ui.kp.Value; cfg.kd = app.ui.kd.Value; cfg.step = app.ui.step.Value;
        if isempty(H), H = table(0, 0, 0, 0, 0, -1, 'VariableNames', {'t', 'rotor', 'psi', 'u', 'ref', 'phase'}); end
        fprintf('  [T%d] rig rows %d, t %.1f s, phases %s, last event [%s], state %s, status [%s]\n', k, height(H), H.t(end), mat2str(unique(H.phase)'), L.runEvent, L.state, app.ui.link.Text);
        mh = odyssix.sim.metrics(H, cfg); ms = odyssix.sim.metrics(S, cfg);
        switch k
            case 1
                R(end+1, :) = {'T1 rig: arm reaches the move', abs(mh.rotor_after_move_deg - 4.95) < 0.02, sprintf('%.3f deg', mh.rotor_after_move_deg)}; %#ok<AGROW>
            case 2
                R(end+1, :) = {'T2 rig overshoot = sim', abs(mh.overshoot_pct - ms.overshoot_pct) < 3, sprintf('rig %.1f%% sim %.1f%%', mh.overshoot_pct, ms.overshoot_pct)}; %#ok<AGROW>
                R(end+1, :) = {'T2 rig disturbance offset = D/Kp', abs(mh.dist_offset_deg - 0.2) < 0.06, sprintf('%.3f deg', mh.dist_offset_deg)}; %#ok<AGROW>
            case 3
                R(end+1, :) = {'T3 rig overshoot = sim', abs(mh.overshoot_pct - ms.overshoot_pct) < 3, sprintf('rig %.1f%% sim %.1f%%', mh.overshoot_pct, ms.overshoot_pct)}; %#ok<AGROW>
            case 5
                fprintf('T5 rig phases %s, events: %s\n', mat2str(unique(H.phase)'), L.runEvent);
                R(end+1, :) = {'T5 rig balanced and showed wrong-way motion', mh.balanced && mh.undershoot_pct < -5, sprintf('undershoot %.1f%%, peak alpha %.2f deg', mh.undershoot_pct, mh.alpha_peak_deg)}; %#ok<AGROW>
        end
        waitFor(@() strcmp(L.state, 'RUNNING'), 2);
    end
    app.abort(); waitFor(@() strcmp(L.state, 'SAFE'), 3);
    R(end+1, :) = {'ABORT -> SAFE', strcmp(L.state, 'SAFE'), L.state};
    fprintf('\nenr312_lab end to end (simulation + EMULATOR, synthetic)\n%s\n', repmat('-', 1, 90));
    for i = 1:size(R, 1), fprintf('  %-52s %-5s %s\n', R{i, 1}, pf(R{i, 2}), R{i, 3}); end
    n = sum([R{:, 2}]); fprintf('%s\n  %d / %d passed\n\n', repmat('-', 1, 90), n, size(R, 1));
    ok = n == size(R, 1);
end
function waitFor(cond, tmax), t0 = tic; while ~cond() && toc(t0) < tmax, pause(0.05); drawnow; end, end
function s = pf(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end

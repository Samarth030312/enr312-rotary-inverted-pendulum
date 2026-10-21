function ok = e2e_lab_new_experiments()
%E2E_LAB_NEW_EXPERIMENTS  enr312_lab end to end for Tutorials 6-10 and PEND on the
%   rig EMULATOR (the firmware's own C control code, protocol 3). SYNTHETIC.
%   Checks: protocol 3 detection; configuration echo of the extended C line;
%   a suspended state-feedback run (T9) against the simulation; P21 stops a
%   plucked swing and goes to a commanded angle; T6 balances upright, holds,
%   goes to a commanded angle and accepts a live gain change. About 2 min.
    R = {};
    app = enr312_lab(); c = onCleanup(@() delete(app.fig));
    app.startEmulator(); L = app.link;
    waitFor(@() L.n > 20 && L.protocol == 3, 8);
    R(end+1, :) = {'emulator speaks protocol 3', L.protocol == 3, sprintf('protocol %d', L.protocol)};
    app.armNoPrompt(); waitFor(@() strcmp(L.state, 'ARMED'), 3);
    app.send('s'); waitFor(@() strcmp(L.state, 'RUNNING'), 3);
    R(end+1, :) = {'ARM, START -> RUNNING', strcmp(L.state, 'RUNNING'), L.state};
    % plant sliders = emulator truth
    truth = @() setPlant(app);

    % --- T9 state feedback, suspended -----------------------------------------
    app.select(9); truth();
    app.runRig(); waitFor(@() contains(L.runEvent, 'GO'), 3);
    c9 = L.cfg;
    R(end+1, :) = {'T9 configuration echoed (k1, k2)', isfield(c9, 'k2') && c9.k1 == 1 && c9.k2 == 2, sprintf('k1 %g k2 %g', c9.k1, c9.k2)};
    waitFor(@() contains(L.runEvent, 'FINISHED') || contains(L.runEvent, 'ABORTED'), 40); pause(0.5);
    H = app.rigData(); S = app.result(); cfg = app.rigCfg();
    mh = odyssix.sim.metrics(H, cfg); ms = odyssix.sim.metrics(S, cfg);
    R(end+1, :) = {'T9 rig settling = sim (within 0.3 s)', abs(mh.settling_s - ms.settling_s) < 0.3, ...
                   sprintf('rig %.2f s, sim %.2f s, event %s', mh.settling_s, ms.settling_s, L.runEvent)};

    % --- P21: stop a plucked swing, then go to 20 deg --------------------------
    app.select(21); truth();
    app.send('!'); pause(1.0);
    app.runRig(); waitFor(@() contains(L.runEvent, 'GO'), 3);
    t0 = tic; while toc(t0) < 12, pause(0.1); drawnow; end
    H = app.rigData(); mh = odyssix.sim.metrics(H, app.rigCfg());
    R(end+1, :) = {'P21 stops the swing (inside 1 deg)', isfinite(mh.stop_time_s), ...
                   sprintf('start %.1f deg, stopped after %.2f s', mh.swing_start_deg, mh.stop_time_s)};
    app.gotoAngle(20);
    R(end+1, :) = {'P21 set-point accepted (REF)', abs(L.lastRef - 20) < 1e-6, app.ui.link.Text};
    t0 = tic; while toc(t0) < 8, pause(0.1); drawnow; end
    H = app.rigData(); mh = odyssix.sim.metrics(H, app.rigCfg());
    R(end+1, :) = {'P21 arm holds 20 deg', abs(mh.hold_error_deg) < 0.5, ...
                   sprintf('reached in %.2f s, error %.3f deg', mh.hold_reach_s, mh.hold_error_deg)};
    L.stopRun(); waitFor(@() contains(L.runEvent, 'FINISHED'), 5); pause(0.5);
    waitFor(@() strcmp(L.state, 'RUNNING') && ~hwBusy(app), 5);

    % --- T6 upright: balance, HOLD, go to angle, live gain change ---------------
    app.select(6); truth();
    waitFor(@() abs(L.table().psi_deg(end)) < 3, 20);
    app.send('^'); waitFor(@() any(contains(L.lines, 'held upright')), 2); pause(0.8);
    app.runRig(); waitFor(@() contains(L.runEvent, 'GO'), 3);
    waitFor(@() ~isempty(app.rigData()) && app.rigData().phase(end) == 8, 45);
    H = app.rigData();
    R(end+1, :) = {'T6 balanced through the sequence into HOLD', H.phase(end) == 8, sprintf('t %.1f s, phases %s', H.t(end), mat2str(unique(H.phase)'))};
    app.gotoAngle(-25);
    t0 = tic; while toc(t0) < 8, pause(0.1); drawnow; end
    H = app.rigData(); mh = odyssix.sim.metrics(H, app.rigCfg());
    R(end+1, :) = {'T6 upright arm holds -25 deg', abs(mh.hold_error_deg) < 1.5 && H.phase(end) == 8, ...
                   sprintf('reached in %.2f s, error %.3f deg', mh.hold_reach_s, mh.hold_error_deg)};
    app.set('kpp', 400); app.live();
    R(end+1, :) = {'T6 live gain change echoed (kpp 400)', isfield(L.cfg, 'kpp') && L.cfg.kpp == 400 && isempty(L.lastError), ...
                   sprintf('kpp %g %s', L.cfg.kpp, L.lastError)};
    t0 = tic; while toc(t0) < 3, pause(0.1); drawnow; end
    H = app.rigData();
    R(end+1, :) = {'T6 still balancing after the change', H.phase(end) == 8, sprintf('phase %d', H.phase(end))};
    L.stopRun(); waitFor(@() contains(L.runEvent, 'FINISHED'), 5);
    app.abort(); waitFor(@() strcmp(L.state, 'SAFE'), 3);
    R(end+1, :) = {'ABORT -> SAFE', strcmp(L.state, 'SAFE'), L.state};

    fprintf('\nenr312_lab end to end, Tutorials 6-10 + PEND (EMULATOR, synthetic)\n%s\n', repmat('-', 1, 90));
    for i = 1:size(R, 1), fprintf('  %-46s %-5s %s\n', R{i, 1}, pf(R{i, 2}), R{i, 3}); end
    n = sum([R{:, 2}]); fprintf('%s\n  %d / %d passed\n\n', repmat('-', 1, 90), n, size(R, 1));
    ok = n == size(R, 1);
end
function setPlant(app)
    app.set('L', 9.81 / (56.4 * 0.6805)); app.set('Q', 24); app.set('r', 0.803 * 9.81 / 56.4);
end
function b = hwBusy(app), b = strcmp(char(app.ui.stopRun.Enable), 'on'); end
function waitFor(cond, tmax), t0 = tic; while ~cond() && toc(t0) < tmax, pause(0.05); drawnow; end, end
function s = pf(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end

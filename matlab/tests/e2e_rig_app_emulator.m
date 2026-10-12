function ok = e2e_rig_app_emulator()
%E2E_RIG_APP_EMULATOR  End-to-end test of enr312_rig against the rig EMULATOR.
%
%   ok = e2e_rig_app_emulator()
%
%   Drives the real app the way an operator would: connect, ARM, START, +5 deg,
%   ABORT, pluck, record 15 s, fit, save, close. Also exercises the flash
%   safety gates without a board. Everything here is SYNTHETIC: the emulator
%   (firmware/enr312/host/enr312_host_rig.c (the firmware's control code on the PC)) is not the firmware and not hardware.
%   Linux/macOS only (the emulator uses a pty).

    R = {};
    T = odyssix.stm32.tools();

    % ---- flash gates, no board needed ------------------------------------
    % any image without the ENR312 banner (e.g. another application built for the
    % same Nucleo) must be refused before the programmer is even started
    foreign = [tempname '.elf']; fid = fopen(foreign, 'w'); fwrite(fid, uint8([127 'ELF' zeros(1, 60)])); fclose(fid);
    r = odyssix.stm32.flash('Image', foreign); delete(foreign);
    R(end+1, :) = {'flash REFUSES an image without the ENR312 banner', ~r.ok && contains(r.message, 'REFUSED'), r.message};
    % GatesOnly: a test must never program a board that happens to be plugged in
    r = odyssix.stm32.flash('Image', 'release', 'GatesOnly', true);
    gatesPassed = r.ok && contains(r.log, 'release hash matches MANIFEST.txt');
    R(end+1, :) = {'release image passes banner + hash gates', gatesPassed, r.message};
    R(end+1, :) = {'GatesOnly never reaches SWD', ~contains(r.log, 'Device ID'), r.message};

    % ---- app against the emulator -----------------------------------------
    app = enr312_rig();
    c = onCleanup(@() closeApp(app));
    app.startEmulator();
    L = app.link;
    waitFor(@() L.n > 20, 5);
    R(end+1, :) = {'emulator streams at ~50 Hz', L.n > 20, sprintf('%d samples', L.n)};
    R(end+1, :) = {'boots SAFE', strcmp(L.state, 'SAFE'), L.state};

    app.armNoPrompt();  waitFor(@() strcmp(L.state, 'ARMED'), 3);
    R(end+1, :) = {'ARM -> ARMED', strcmp(L.state, 'ARMED'), L.state};
    app.send('s');      waitFor(@() strcmp(L.state, 'RUNNING'), 3);
    R(end+1, :) = {'START -> RUNNING', strcmp(L.state, 'RUNNING'), L.state};
    app.send('+');      pause(1.5);
    D = L.table();
    R(end+1, :) = {'+5 deg move: rotor 4.95 deg (44 microsteps)', abs(D.rotor_deg(end) - 4.95) < 0.01, ...
                   sprintf('%.3f deg', D.rotor_deg(end))};
    swing = max(D.psi_deg(end-60:end)) - min(D.psi_deg(end-60:end));
    R(end+1, :) = {'move kicks the pendulum (2-8 deg p-p)', swing > 2 && swing < 8, sprintf('%.2f deg p-p', swing)};
    app.abort();        waitFor(@() strcmp(L.state, 'SAFE'), 3);
    R(end+1, :) = {'ABORT -> SAFE', strcmp(L.state, 'SAFE'), L.state};

    app.send('z'); pause(0.3); app.send('!'); pause(0.2);      % zero, pluck 30 deg
    app.record();
    waitFor(@() ~isempty(app.fit()), 25);
    f = app.fit();
    R(end+1, :) = {'free-swing fit produced', ~isempty(f), ''};
    if ~isempty(f)
        R(end+1, :) = {'fit wg2 = emulator truth 56.4 (+-1 %)', abs(f.wg2 / 56.4 - 1) < 0.01, sprintf('%.3f', f.wg2)};
        R(end+1, :) = {'fit Q = emulator truth 24 (+-15 %)', abs(f.Q / 24 - 1) < 0.15, sprintf('%.2f', f.Q)};
        before = dir(fullfile(T.repo, 'matlab', 'data', 'synthetic', '*_emulator_synthetic.csv'));
        rawBefore = numel(dir(fullfile(T.repo, 'data', 'raw', 'EXP001', '*.csv')));   % real rig data may exist
        app.save(); pause(0.5);
        after = dir(fullfile(T.repo, 'matlab', 'data', 'synthetic', '*_emulator_synthetic.csv'));
        R(end+1, :) = {'emulator run saved as SYNTHETIC, not data/raw', numel(after) == numel(before) + 1 && ...
                       numel(dir(fullfile(T.repo, 'data', 'raw', 'EXP001', '*.csv'))) == rawBefore, sprintf('%d file(s)', numel(after))};
        closeAllAlerts(app.fig);
    end
    logFile = L.logFile;
    closeApp(app);
    R(end+1, :) = {'closing sends ABORT (in raw log)', contains(fileread(logFile), '>> x'), logFile};

    fprintf('\nenr312_rig end-to-end test (EMULATOR, synthetic)\n%s\n', repmat('-', 1, 86));
    for i = 1:size(R, 1)
        fprintf('  %-48s %-6s %s\n', R{i, 1}, pf(R{i, 2}), R{i, 3});
    end
    n = sum([R{:, 2}]);
    fprintf('%s\n  %d / %d passed\n\n', repmat('-', 1, 86), n, size(R, 1));
    ok = n == size(R, 1);
end

function waitFor(cond, tmax)
    t0 = tic;
    while ~cond() && toc(t0) < tmax, pause(0.05); drawnow; end
end

function closeApp(app)
    if isvalid(app.fig), closeAllAlerts(app.fig); close(app.fig); end
end

function closeAllAlerts(fig)
    % uialert dialogs are modal-less in tests; nothing to do but keep drawing
    drawnow;
end

function s = pf(b)
    if b, s = 'PASS'; else, s = 'FAIL'; end
end

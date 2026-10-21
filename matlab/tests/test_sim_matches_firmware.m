function ok = test_sim_matches_firmware()
%TEST_SIM_MATCHES_FIRMWARE  The MATLAB tutorial engine reproduces the firmware.
%
%   Runs each closed-loop tutorial in odyssix.sim.runTutorial and in the C
%   emulator's batch mode (firmware/enr312/build/enr312_host_rig: the real
%   runner, cores and PD), same plant, and compares the trajectories.
%   Requires gcc + make (builds the emulator if missing). Linux/macOS.
    T = odyssix.stm32.tools();
    exe = odyssix.stm32.emulatorBinary();
    R = {};
    for e = [2 3 4 5]
        cfg = odyssix.sim.defaults(e);
        pl = struct('wg2', 56.4, 'Q', 24, 'wr2', 0.803, 'nonlinear', true, 'quant', true);  % emulator truth
        S = odyssix.sim.runTutorial(cfg, pl);
        f = [tempname '.csv'];
        st = system(sprintf('"%s" --batch exp=%d seconds=%g > "%s"', exe, e, cfg.seconds, f));
        C = readtable(f); delete(f);
        n = min(height(C), height(S));
        dr = max(abs(C.rotor_deg(1:n) - S.rotor(1:n)));
        dp = max(abs(C.psi_deg(1:n) - S.psi(1:n)));
        du = max(abs(C.u(2:n) - S.u(1:n-1)));      % batch prints u one tick late
        if e ~= 5
            R(end+1, :) = {sprintf('EXP00%d rotor |MATLAB - firmware| max', e), st == 0 && dr < 1e-6, sprintf('%.2e deg over %d samples', dr, n)}; %#ok<AGROW>
            R(end+1, :) = {sprintf('EXP00%d pendulum', e), dp < 1e-6, sprintf('%.2e deg', dp)}; %#ok<AGROW>
            R(end+1, :) = {sprintf('EXP00%d plant input u (C prints 3 dp)', e), du < 1e-3, sprintf('%.2e deg/s^2', du)}; %#ok<AGROW>
        else
            % Balancing upright sits in an encoder-quantisation limit cycle: a
            % last-bit floating-point difference (FMA vs none) eventually flips
            % one encoder count and the two runs part ways. Require identity up
            % to that flip, then the same physical outcome.
            d = abs(C.rotor_deg(1:n) - S.rotor(1:n)) + abs(C.psi_deg(1:n) - S.psi(1:n));
            k = find(d > 1e-9, 1); if isempty(k), k = n; end
            stepStart = find(S.phase >= 2, 1);
            R(end+1, :) = {'EXP005 identical through capture and balance', k > stepStart, sprintf('identical for %.2f s (step starts %.2f s)', S.t(k), S.t(stepStart))}; %#ok<AGROW>
            aC = 180 - C.psi_deg(end - 500:end); aM = S.alpha(end - 500:end);
            R(end+1, :) = {'EXP005 both still balancing at the end (|alpha| < 2)', max(abs(aC)) < 2 && max(abs(aM)) < 2, sprintf('C %.2f, MATLAB %.2f deg', max(abs(aC)), max(abs(aM)))}; %#ok<AGROW>
            w = S.phase == 2; uC = min(C.rotor_deg(find(w, 1):find(w, 1) + 400)); uM = min(S.rotor(w));
            R(end+1, :) = {'EXP005 wrong-way undershoot agrees (0.1 deg)', abs(uC - uM) < 0.1, sprintf('C %.3f, MATLAB %.3f deg', uC, uM)}; %#ok<AGROW>
        end
    end
    % ---- general core (enr312_ctrl.c) vs odyssix.sim.runCtrl ------------------
    pl = struct('wg2', 56.4, 'Q', 24, 'wr2', 0.803, 'nonlinear', true, 'quant', true);
    cases = {9, '', struct(); 10, '', struct(); 22, '', struct(); 21, 'psi0=30', struct('psi0', 30); ...
             21, 'psi0=20 at=5:ref=15 at=10:kp=10 tap=12:30 div=5 ma=4', ...
                 struct('psi0', 20, 'events', struct('t', {5, 10}, 'key', {'ref', 'kp'}, 'val', {15, 10}), ...
                        'taps', [12 30], 'div', 5, 'ma', 4)};
    for i = 1:size(cases, 1)
        e = cases{i, 1}; cfg = odyssix.sim.defaults(e); o = cases{i, 3};
        if isfield(o, 'div'), cfg.div = o.div; cfg.ma = o.ma; end
        [C, S, st] = both(exe, cfg, pl, cases{i, 2}, o);
        n = min(height(C), height(S));
        d = max(abs(C.rotor_deg(1:n) - S.rotor(1:n)) + abs(C.psi_deg(1:n) - S.psi(1:n)));
        label = sprintf('exp %d %s', e, cases{i, 2});
        R(end+1, :) = {sprintf('%-40s identical', label), st == 0 && d < 1e-6, sprintf('%.1e deg over %d samples', d, n)}; %#ok<AGROW>
    end
    for e = [6 7 8 23]
        cfg = odyssix.sim.defaults(e);
        [C, S] = both(exe, cfg, pl, '', struct());
        n = min(height(C), height(S));
        d = abs(C.rotor_deg(1:n) - S.rotor(1:n)) + abs(C.psi_deg(1:n) - S.psi(1:n));
        k = find(d > 1e-9, 1); if isempty(k), k = n; end
        b = find(S.phase == 2, 1);
        aC = 180 - C.psi_deg(end - 500:end); aM = S.alpha(end - 500:end);
        R(end+1, :) = {sprintf('exp %d identical through capture, release, balance start', e), k > b, ...
                       sprintf('%.2f s (balance from %.2f s)', S.t(k), S.t(b))}; %#ok<AGROW>
        R(end+1, :) = {sprintf('exp %d both balancing at the end, same phase', e), ...
                       max(abs(aC)) < 2 && max(abs(aM)) < 2 && C.phase(n) == S.phase(n), ...
                       sprintf('|alpha| C %.2f, MATLAB %.2f; phase %d', max(abs(aC)), max(abs(aM)), S.phase(n))}; %#ok<AGROW>
    end

    fprintf('\nMATLAB engine vs firmware control code (C emulator, batch)\n%s\n', repmat('-', 1, 80));
    for i = 1:size(R, 1), fprintf('  %-58s %-5s %s\n', R{i, 1}, pf(R{i, 2}), R{i, 3}); end
    n = sum([R{:, 2}]); fprintf('%s\n  %d / %d passed\n\n', repmat('-', 1, 80), n, size(R, 1));
    ok = n == size(R, 1);
    %#ok<*NASGU> T kept for symmetry with other tests
end
function s = pf(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end

function [C, S, st] = both(exe, cfg, pl, args, o)
    S = odyssix.sim.runCtrl(cfg, pl, o);
    f = [tempname '.csv'];
    st = system(sprintf('"%s" --batch exp=%d seconds=%g %s > "%s"', exe, cfg.exp, cfg.seconds, args, f));
    C = readtable(f); delete(f);
end

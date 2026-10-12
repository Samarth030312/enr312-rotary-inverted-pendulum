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
    fprintf('\nMATLAB engine vs firmware control code (C emulator, batch)\n%s\n', repmat('-', 1, 80));
    for i = 1:size(R, 1), fprintf('  %-42s %-5s %s\n', R{i, 1}, pf(R{i, 2}), R{i, 3}); end
    n = sum([R{:, 2}]); fprintf('%s\n  %d / %d passed\n\n', repmat('-', 1, 80), n, size(R, 1));
    ok = n == size(R, 1);
    %#ok<*NASGU> T kept for symmetry with other tests
end
function s = pf(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end

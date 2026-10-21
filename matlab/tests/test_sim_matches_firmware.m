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
                        'taps', [12 30], 'div', 5, 'ma', 4); ...
             9, 'seq=0 at=2:ref=25 at=12:ref=-10', ...
                 struct('seq', 0, 'events', struct('t', {2, 12}, 'key', {'ref', 'ref'}, 'val', {25, -10})); ...
             22, 'seq=0 at=1:ref=15', struct('seq', 0, 'events', struct('t', 1, 'key', 'ref', 'val', 15))};
    for i = 1:size(cases, 1)
        e = cases{i, 1}; cfg = odyssix.sim.defaults(e); o = cases{i, 3};
        if isfield(o, 'div'), cfg.div = o.div; cfg.ma = o.ma; end
        if isfield(o, 'seq'), cfg.seq = o.seq; cfg.seconds = 25; end
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

    % ---- swing-up (exp 24): energy pumping is sensitive to the last bit, like
    %      balancing; require identity through the pumping, then the same outcome
    cfg = odyssix.sim.defaults(24);
    [C, S] = both(exe, cfg, pl, '', struct());
    n = min(height(C), height(S));
    d = abs(C.rotor_deg(1:n) - S.rotor(1:n)) + abs(C.psi_deg(1:n) - S.psi(1:n));
    k = find(d > 1e-9, 1); if isempty(k), k = n; end
    cC = find(C.phase == 8, 1); cM = find(S.phase == 8, 1);
    R(end+1, :) = {'exp 24 swing-up identical while pumping (>= 2 s)', S.t(k) >= 2, sprintf('identical for %.2f s', S.t(k))}; %#ok<AGROW>
    aC = mod(180 - C.psi_deg(end - 500:end) + 180, 360) - 180; aM = abs(S.alpha(end - 500:end));
    R(end+1, :) = {'exp 24 both caught upright and balancing at the end', ~isempty(cC) && ~isempty(cM) && ...
                   max(abs(aC)) < 2 && max(aM) < 2 && C.phase(n) == 8 && S.phase(n) == 8, ...
                   sprintf('caught C %.2f s, MATLAB %.2f s', C.t_s(max([cC 1])), S.t(max([cM 1])))}; %#ok<AGROW>

    % ---- pendulum target (exp 24, amp 90): a stable regulation, so identical throughout
    cfg = odyssix.sim.defaults(24); cfg.amp = 90; cfg.seconds = 25;
    [C, S] = both(exe, cfg, pl, 'amp=90', struct());
    n = min(height(C), height(S)); d = max(abs(C.rotor_deg(1:n) - S.rotor(1:n)) + abs(C.psi_deg(1:n) - S.psi(1:n)));
    pk = max(abs(mod(S.psi(S.t > 15) + 180, 360) - 180));
    R(end+1, :) = {'exp 24 amp 90: identical, swings to 90 (6)', d < 1e-6 && abs(pk - 90) < 6, sprintf('%.1e deg; swings to %.1f deg', d, pk)}; %#ok<AGROW>
    % ---- pivot dry friction (stick-slip), hanging PID: identical
    cfg = odyssix.sim.defaults(21); cfg.seconds = 15;
    plc = pl; plc.coulomb = 0.9;
    [C, S] = both(exe, cfg, plc, 'psi0=20 plant_coulomb=0.9', struct('psi0', 20));
    n = min(height(C), height(S)); d = max(abs(C.rotor_deg(1:n) - S.rotor(1:n)) + abs(C.psi_deg(1:n) - S.psi(1:n)));
    R(end+1, :) = {'exp 21 with pivot dry friction 0.9: identical', d < 1e-6, sprintf('%.1e deg over %d samples', d, n)}; %#ok<AGROW>
    % ---- swing-up on a realistic pendulum: friction, offset, wg2 50 vs firmware 57.01
    cfg = odyssix.sim.defaults(24); cfg.wg2 = 57.01;
    plr = pl; plr.wg2 = 50; plr.coulomb = 0.9; plr.bias = 0.5;
    [C, S] = both(exe, cfg, plr, 'wg2=57.01 plant_wg2=50 plant_coulomb=0.9 plant_bias=0.5', struct());
    cC = find(C.phase == 8, 1); cM = find(S.phase == 8, 1);
    R(end+1, :) = {'exp 24, friction + offset + wg2 error: both catch, same time', ~isempty(cC) && ~isempty(cM) && abs(C.t_s(cC) - S.t(cM)) < 0.01, ...
                   sprintf('C %.2f s, MATLAB %.2f s', C.t_s(max([cC 1])), S.t(max([cM 1])))}; %#ok<AGROW>

    % ---- upright auto-trim with a 0.6 deg encoder offset (exp 23, lab mode)
    cfg = odyssix.sim.defaults(23); cfg.seq = 0; cfg.seconds = 60;
    plb = pl; plb.bias = 0.6;
    [C, S] = both(exe, cfg, plb, 'seq=0 plant_bias=0.6', struct());
    n = min(height(C), height(S));
    armC = mean(C.rotor_deg(C.t_s > 50)); armM = mean(S.rotor(S.t > 50));
    R(end+1, :) = {'exp 23 + 0.6 deg datum offset: both trim the arm home', abs(armC) < 3 && abs(armM) < 3 && C.phase(n) == 8 && S.phase(n) == 8, ...
                   sprintf('arm C %.2f, MATLAB %.2f deg (23 without trim)', armC, armM)}; %#ok<AGROW>

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

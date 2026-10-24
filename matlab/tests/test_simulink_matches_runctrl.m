function ok = test_simulink_matches_runctrl()
%TEST_SIMULINK_MATCHES_RUNCTRL  The Simulink model agrees with the firmware twin, every experiment.
%
%   For each experiment 1-10 and 21-24, with its default settings on the measured
%   pendulum, the Simulink model (matlab/simulink, rebuilt from its script) and the
%   firmware's own control code in MATLAB (odyssix.sim.runTutorial / runCtrl, which
%   test_sim_matches_firmware ties to the C) are run, and compared:
%     every experiment   the same final phase (finished, holding, aborted)
%     deterministic      1 2 3 4 9 10 21 24: the arm trace, rms difference
%                        within max(0.5 deg, 5 % of the largest arm angle)
%     hunting            5 6 7 8 22 23: these settle into a limit cycle (dry friction,
%                        integral action, on-off switching; 23 holds upright with a
%                        +-2 deg arm wobble on the pivot's friction) whose phase drifts
%                        between any two simulations, so the traces are not compared
%                        point by point; instead the largest arm angle within 15 %,
%                        and the rms of the arm and of the pendulum about their means
%                        within 30 %
%   Plus the tap check: the LQR, a tap of 30, 60 and 90 deg/s while balanced, the
%   same outcome, the peak tilt within 25 % and the arm swing within 20 %.
%
%   Two known, deliberate differences, both small at these settings:
%   - dry pivot friction: the model smooths it (c tanh(psidot/0.01)) and cannot
%     hold the pendulum stuck at a small angle, where the twin's stick-slip can;
%   - odyssix.sim.runTutorial (experiments 1-5) has no dry friction, so for those
%     the model is run with P.coulomb = 0 here (the model itself keeps it).
%   Skipped (returns true) when Simulink is not installed.
    ok = true;
    if ~(license('test', 'Simulink') && ~isempty(ver('simulink')))
        fprintf('test_simulink_matches_runctrl: SKIPPED (no Simulink)\n'); return;
    end
    here = fullfile(odyssix.repoRoot(), 'matlab', 'simulink');
    onPath = contains([pathsep path pathsep], [pathsep here pathsep]); addpath(here);
    mdl = 'enr312_pendulum'; tmp = tempname; mkdir(tmp);
    w0 = warning('off', 'all');                 % the fresh copy shadows the committed .slx: expected
    build_enr312_simulink(tmp);                 % from the script, so the test checks the source
    load_system(fullfile(tmp, [mdl '.slx'])); c0 = onCleanup(@() close_system(mdl, 0));
    warning(w0);

    fprintf('%-4s %-12s %-44s %s\n', 'exp', 'end phase', 'arm / pendulum', 'verdict');
    for e = [1:10 21:24]
        P = enr312_simulink_params(e);
        if e <= 5, P.coulomb = 0; end
        [o, S] = both(mdl, P);
        th = interp1(o.theta_deg.Time, o.theta_deg.Data, S.t, 'previous');
        ps = interp1(o.psi_deg.Time, o.psi_deg.Data, S.t, 'previous');
        phS = o.phase.Data(find(o.phase.Time <= S.t(end) + 1e-9, 1, 'last'));
        good = phS == S.phase(end);
        if any(e == [5 6 7 8 22 23])
            r1 = [max(abs(S.rotor)), sd(S.rotor), sd(S.psi)];
            r2 = [max(abs(th)), sd(th), sd(ps)];
            good = good && abs(r2(1) / r1(1) - 1) < 0.15 && all(abs(r2(2:3) ./ r1(2:3) - 1) < 0.30);
            txt = sprintf('peak %.1f/%.1f, rms %.2f/%.2f, pend %.2f/%.2f', r1(1), r2(1), r1(2), r2(2), r1(3), r2(3));
        else
            d = sqrt(mean((th - S.rotor).^2, 'omitnan')); tol = max(0.5, 0.05 * max(abs(S.rotor)));
            good = good && d <= tol;
            txt = sprintf('arm rms diff %.3f deg (tol %.2f)', d, tol);
        end
        fprintf('%-4d %-12s %-44s %s\n', e, sprintf('%g / %g', S.phase(end), phS), txt, ternary(good, 'ok', 'DIFFERENT'));
        ok = ok && good;
    end

    % ---- taps while balanced (LQR) ----------------------------------------------------
    al = @(ps) mod(180 - ps + 180, 360) - 180;
    for v = [30 60 90]
        P = enr312_simulink_params(23); P.seq = 0; P.stopTime = 14; P.psi0 = 179.4;
        P.tapRate = -v; P.tapTime = 8;           % runCtrl's tap is in psi, the model's in alpha
        pl = plantOf(P); c = enr312_simulink_cfg(P);
        S = odyssix.sim.runCtrl(c, pl, struct('taps', [8 v], 'psi0', P.psi0));
        assignin('base', 'P', P); o = sim(mdl, 'SrcWorkspace', 'base');
        w = S.t > 8; a2 = al(o.psi_deg.Data); w2 = o.psi_deg.Time > 8; th = o.theta_deg;
        lost1 = max(abs(S.alpha(w))) > 15 || S.phase(end) == 13; lost2 = max(abs(a2(w2))) > 15;
        if lost1 || lost2
            good = lost1 == lost2; s1 = ternary(lost1, 'lost', '-'); s2 = ternary(lost2, 'lost', '-');
        else
            pk1 = max(abs(S.alpha(w))); arm1 = max(S.rotor(w)) - min(S.rotor(w));
            pk2 = max(abs(a2(w2))); arm2 = max(th.Data(th.Time > 8)) - min(th.Data(th.Time > 8));
            good = abs(pk2 / pk1 - 1) < 0.25 && abs(arm2 / arm1 - 1) < 0.20;
            s1 = sprintf('%.2f/%.1f', pk1, arm1); s2 = sprintf('%.2f/%.1f', pk2, arm2);
        end
        fprintf('tap %-3d twin %-12s Simulink %-12s %s\n', v, s1, s2, ternary(good, 'ok', 'DIFFERENT'));
        ok = ok && good;
    end
    if ~onPath, rmpath(here); end
    fprintf('test_simulink_matches_runctrl: %s\n', ternary(ok, 'PASS', 'FAIL'));
end

function [o, S] = both(mdl, P)
    assignin('base', 'P', P); o = sim(mdl, 'SrcWorkspace', 'base');
    pl = plantOf(P); c = enr312_simulink_cfg(P);
    if P.exp >= 6, S = odyssix.sim.runCtrl(c, pl, struct('psi0', P.psi0));
    else, S = odyssix.sim.runTutorial(c, pl); end
end

function pl = plantOf(P)
    pl = struct('wg2', P.wg2, 'Q', P.Q, 'wr2', P.wr2, 'coulomb', P.coulomb, ...
                'nonlinear', true, 'quant', true, 'bias', P.bias);
end

function s = sd(x), x = x(~isnan(x)); s = sqrt(mean((x - mean(x)).^2)); end
function v = ternary(c, a, b), if c, v = a; else, v = b; end, end

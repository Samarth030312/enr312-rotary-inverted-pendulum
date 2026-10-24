function ok = test_simulink_matches_runctrl()
%TEST_SIMULINK_MATCHES_RUNCTRL  The Simulink model agrees with the firmware twin.
%
%   The LQR of experiment 23 on the measured pendulum, a tap of 30, 60 and 90 deg/s
%   while balanced, in both odyssix.sim.runCtrl (the firmware's control code, which
%   test_sim_matches_firmware ties to the C) and matlab/simulink/enr312_pendulum.slx.
%   Pass: the same outcome (recovered or lost) for every tap, and, when recovered,
%   the peak tilt within 25 % and the arm swing within 20 %.
%   The two differ on purpose in one place: Simulink integrates the arm acceleration
%   continuously, the firmware changes the arm velocity in 2 ms steps. That is worth
%   about 10-15 % on the peak tilt.
%   Skipped (returns true) when Simulink is not installed.
    ok = true;
    if ~(license('test', 'Simulink') && ~isempty(ver('simulink')))
        fprintf('test_simulink_matches_runctrl: SKIPPED (no Simulink)\n'); return;
    end
    here = fullfile(odyssix.repoRoot(), 'matlab', 'simulink'); addpath(here);
    mdl = 'enr312_pendulum'; tmp = tempname; mkdir(tmp);
    w0 = warning('off', 'all');                 % the fresh copy shadows the committed .slx: expected
    build_enr312_simulink(tmp);                 % from the script, so the test checks the source
    warning(w0);
    load_system(fullfile(tmp, [mdl '.slx'])); c0 = onCleanup(@() close_system(mdl, 0));
    pl = odyssix.sim.plant(5); rp = odyssix.rigParams().pendulum;
    pl.wg2 = rp.wg2; pl.wr2 = rp.wr2; pl.coulomb = rp.coulomb; pl.Q = mean(rp.QLargeSwing);
    al = @(ps) mod(180 - ps + 180, 360) - 180;
    fprintf('%-6s %-22s %-22s %s\n', 'tap', 'runCtrl peak / arm', 'Simulink peak / arm', 'verdict');
    for v = [30 60 90]
        c = odyssix.sim.defaults(23); c.seq = 0; c.seconds = 14;
        S = odyssix.sim.runCtrl(c, pl, struct('taps', [8 v]));
        w = S.t > 8;
        lost1 = max(abs(S.alpha(w))) > 15 || any(S.phase(w) ~= S.phase(find(w, 1)));
        pk1 = max(abs(S.alpha(w))); arm1 = max(S.rotor(w)) - min(S.rotor(w));

        P = enr312_simulink_params('measured', 'lqr'); P.alpha0 = 0.6; P.tapRate = -v; P.tapTime = 8; P.stopTime = 14;
        assignin('base', 'P', P); o = sim(mdl, 'SrcWorkspace', 'base');
        a2 = al(o.psi_deg.Data); w2 = o.psi_deg.Time > 8; th = o.theta_deg;
        lost2 = max(abs(a2(w2))) > 15;
        pk2 = max(abs(a2(w2))); arm2 = max(th.Data(th.Time > 8)) - min(th.Data(th.Time > 8));

        if lost1 || lost2
            good = lost1 == lost2; s1 = ternary(lost1, 'lost', '-'); s2 = ternary(lost2, 'lost', '-');
        else
            good = abs(pk2 / pk1 - 1) < 0.25 && abs(arm2 / arm1 - 1) < 0.20;
            s1 = sprintf('%.2f° / %.1f°', pk1, arm1); s2 = sprintf('%.2f° / %.1f°', pk2, arm2);
        end
        fprintf('%-6d %-22s %-22s %s\n', v, s1, s2, ternary(good, 'ok', 'DIFFERENT'));
        ok = ok && good;
    end
    rmpath(here);
    fprintf('test_simulink_matches_runctrl: %s\n', ternary(ok, 'PASS', 'FAIL'));
end

function v = ternary(c, a, b), if c, v = a; else, v = b; end, end

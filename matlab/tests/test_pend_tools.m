function ok = test_pend_tools()
%TEST_PEND_TOOLS  The PEND analysis tools recover known answers from synthetic data.
%
%   Free swing: a quantised (0.15 deg) nonlinear swing of the Tutorial 3
%   plant must give back wg2 and the damping. Unstable pole: sqrt(wg2) for
%   gamma = 0. Recovery: a known decaying trace. Derivative noise: one
%   encoder count at 500 Hz is 75 deg/s.
    R = {};
    pl = odyssix.sim.plant(3); g = sqrt(pl.wg2) / pl.Q;
    h = 0.002; t = (0:h:20)'; p = deg2rad(15); v = 0; y = zeros(size(t));
    for k = 1:numel(t)
        y(k) = round(rad2deg(p) / 0.15) * 0.15;
        for s = 1:4, a = -pl.wg2 * sin(p) - g * v; v = v + h / 4 * a; p = p + h / 4 * v; end
    end
    r = odyssix.pend.freeSwing(t, y);
    R(end+1, :) = {'free swing: wg2 from 10 periods within 1 %', abs(r.wg2 / pl.wg2 - 1) < 0.01, sprintf('%.2f vs %.2f', r.wg2, pl.wg2)};
    R(end+1, :) = {'free swing: damping ratio within 5 %', abs(r.zeta * 2 * pl.Q - 1) < 0.05, sprintf('%.4f vs %.4f', r.zeta, 1 / (2 * pl.Q))};
    R(end+1, :) = {'free swing: Lsimple = g/wg2 within 1 %', abs(r.Lsimple * pl.wg2 / 9.81 - 1) < 0.01, sprintf('%.4f m', r.Lsimple)};
    R(end+1, :) = {'free swing: nonlinear fit wg2 within 1 %', abs(r.fit.wg2 / pl.wg2 - 1) < 0.01, sprintf('%.2f', r.fit.wg2)};
    u = odyssix.pend.unstablePole(56.25, 'wg2');
    R(end+1, :) = {'unstable pole sqrt(wg2)', abs(u.p - 7.5) < 1e-12, sprintf('%.4f rad/s', u.p)};
    tt = (0:0.02:10)'; a = 5 * exp(-(tt - 2)) .* (tt >= 2);
    q = odyssix.pend.recovery(tt, a, 2, 1);
    R(end+1, :) = {'recovery time of 5 e^-t into 1 deg = ln 5', abs(q.recoverS - log(5)) < 0.021, sprintf('%.3f s', q.recoverS)};
    d = odyssix.pend.derivativeNoise((0:0.002:1)', 0.15 * mod(0:500, 2)');
    R(end+1, :) = {'one count at 500 Hz = 75 deg/s', abs(d.countRateDegS - 75) < 1e-9 && abs(max(abs(d.dRaw)) - 75) < 1e-9, sprintf('%.1f', max(abs(d.dRaw)))};
    S = pend_swingup_study([], struct('umax', 1500, 'plot', false));
    R(end+1, :) = {'swing-up study (sim): 1500 deg/s^2 reaches and catches', S.caught(1) == 1, sprintf('t %.2f s, arm %.0f deg', S.t_reach_s(1), S.max_arm_deg(1))};
    fprintf('%s\n', repmat('-', 1, 80));
    for i = 1:size(R, 1)
        fprintf('  %-58s %s  %s\n', R{i, 1}, tern(R{i, 2}), R{i, 3});
    end
    ok = all([R{:, 2}]);
    fprintf('%s\n  %d / %d passed\n', repmat('-', 1, 80), sum([R{:, 2}]), size(R, 1));
end
function s = tern(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end

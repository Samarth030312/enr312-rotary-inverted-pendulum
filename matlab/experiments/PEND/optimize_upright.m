function R = optimize_upright(opts)
%OPTIMIZE_UPRIGHT  Robust tuning of the upright dual PID (and LQR weights) in simulation.
%
%   R = optimize_upright()
%
%   EXECUTION STATUS: simulation of the firmware (odyssix.sim.runCtrl, identical
%   to the C code) on plants around the Tutorial values. The result is a
%   MODEL-OPTIMAL design to be checked on the rig, not a measured optimum.
%
%   Scenario (LAB, upright, lab mode): released from the hand, hold, go to
%   +20 deg at 6 s (slewed 90 deg/s), a 60 deg/s tap on the pendulum at 14 s,
%   22 s in all. Plants: Tutorial 5 nominal, a light one (wg2 50, Q 15) and a
%   heavy one (wg2 62, Q 30), all with the 0.5 deg encoder offset measured on
%   the rig (2026-10-21). Cost per plant, normalised by typical values:
%       J = alpha_rms/0.3 + arm_err_rms/5 + u_rms/300      (abort: J = 100)
%   and the design cost is the worst plant (robust). fminsearch on log-gains.
%   R: table of Tutorial 6, optimised PID and LQR designs with per-plant numbers.
    if nargin < 1, opts = struct(); end
    if ~isfield(opts, 'iters'), opts.iters = 120; end
    P = plants();
    base = odyssix.sim.defaults(6); base.seq = 0; base.seconds = 22;
    names = {'kp', 'ki', 'kd', 'kpp', 'kdp', 'fdp'};
    x0 = log([base.kp base.ki base.kd base.kpp base.kdp base.fdp]);
    f = @(x) worst(cfgFrom(base, names, exp(x)), P);
    o = optimset('Display', 'iter', 'MaxIter', opts.iters, 'MaxFunEvals', opts.iters * 2, 'TolX', 1e-3, 'TolFun', 1e-3);
    xo = fminsearch(f, x0, o);
    pid = cfgFrom(base, names, exp(xo));
    % LQR: tune the pendulum weight and R (4-state model of the nominal plant)
    lb = odyssix.sim.defaults(23); lb.seq = 0; lb.seconds = 22;
    g = @(y) worst(lqrCfg(lb, exp(y)), P);
    yo = fminsearch(g, log([10 0.01]), optimset(o, 'MaxIter', 40, 'MaxFunEvals', 80));
    lqrc = lqrCfg(lb, exp(yo));
    designs = {'Tutorial 6 PID', base; 'optimised PID', pid; 'LQR default', lb; 'optimised LQR', lqrc};
    rows = {};
    for i = 1:size(designs, 1)
        for j = 1:numel(P)
            [J, m] = score(designs{i, 2}, P(j));
            rows(end+1, :) = {designs{i, 1}, P(j).name, J, m.alpha_rms, m.arm_err, m.u_rms, m.tap_peak, m.ok}; %#ok<AGROW>
        end
    end
    R = cell2table(rows, 'VariableNames', {'design', 'plant', 'J', 'alpha_rms_deg', 'arm_err_rms_deg', 'u_rms', 'tap_peak_deg', 'balanced'});
    R.Properties.UserData = struct('pid', pid, 'lqr', lqrc, 'lqrQR', exp(yo), 'status', 'SIMULATION, model-optimal');
    disp(R);
    fprintf('optimised PID: kp %.3g ki %.3g kd %.3g kpp %.4g kdp %.3g fdp %.3g\n', pid.kp, pid.ki, pid.kd, pid.kpp, pid.kdp, pid.fdp);
    fprintf('optimised LQR: Q_alpha %.3g R %.3g -> K = [%s]\n', exp(yo(1)), exp(yo(2)), num2str([lqrc.k1 lqrc.k2 lqrc.k3 lqrc.k4], '%.4g '));
end

function P = plants()
    p = odyssix.sim.plant(5); p.bias = 0.5; p.name = 'nominal';
    q = p; q.wg2 = 50; q.Q = 15; q.name = 'light, wg2 50 Q 15';
    r = p; r.wg2 = 62; r.Q = 30; r.name = 'heavy, wg2 62 Q 30';
    P = [p q r];
end

function c = cfgFrom(c, names, v)
    for i = 1:numel(names), c.(names{i}) = v(i); end
    c.kp = min(c.kp, 100); c.ki = min(c.ki, 100); c.kd = min(c.kd, 100);
    c.kpp = min(c.kpp, 1000); c.kdp = min(c.kdp, 200); c.fdp = min(max(c.fdp, 0.5), 200);
end

function c = lqrCfg(c, w)
    [A, B] = odyssix.ctrl.pendulumModel('inverted', odyssix.sim.plant(5));
    K = odyssix.ctrl.lqr(A, B, diag([1 1 w(1) 1]), w(2));
    c.k1 = K(1); c.k2 = K(2); c.k3 = min(K(3), 5000); c.k4 = K(4);
end

function J = worst(c, P)
    J = 0; for j = 1:numel(P), J = max(J, score(c, P(j))); end
end

function [J, m] = score(c, p)
    o = struct('events', struct('t', 6, 'key', 'ref', 'val', 20), 'taps', [14 60]);
    S = odyssix.sim.runCtrl(c, p, o);
    a = S.alpha; w = S.phase == 8;
    m.ok = strcmp(S.Properties.UserData.abort, 'NONE') && any(w);
    if ~m.ok, J = 100; m.alpha_rms = NaN; m.arm_err = NaN; m.u_rms = NaN; m.tap_peak = NaN; return; end
    m.alpha_rms = sqrt(mean(a(w).^2));
    wt = w & S.t >= 8;                                  % after the go-to has had 2 s
    m.arm_err = sqrt(mean((S.rotor(wt) - S.ref(wt)).^2));
    m.u_rms = sqrt(mean(S.u(w).^2));
    m.tap_peak = max(abs(a(S.t >= 14 & S.t < 17)));
    J = m.alpha_rms / 0.3 + m.arm_err / 5 + m.u_rms / 300;
end

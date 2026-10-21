function fit = pendulum_free_swing_fit(t, psiDeg, opts)
%PENDULUM_FREE_SWING_FIT  Identify wg2, viscous and dry friction from a hanging free swing.
%
%   fit = pendulum_free_swing_fit(t, psiDeg)
%
%   Experiment (motor UNPOWERED or holding still, so theta'' = 0): displace
%   the hanging pendulum by 10-40 deg, release it, record the encoder angle.
%   Model, nonlinear, with stick-slip:
%       psi'' = -wg2 sin(psi - off) - gamma psi' - c sgn(psi')     (sliding)
%       psi'  = 0  while |wg2 sin(psi - off)| <= c                  (stuck)
%   c is dry (Coulomb) friction as an angular deceleration [rad/s^2]. With
%   c = 0 this is the viscous model of rotary_pendulum_psiddot. A viscous-only
%   model cannot fit the real pivot (2026-10-21: the optimiser ran away to
%   Q 1e13); see matlab/identification/identify_pendulum_20261021.m.
%
%   The release is found in the record: the start of the longest run of swing
%   peaks that never grows (a hand that lifts the pendulum slowly, or pushes it
%   again, makes a peak grow). The fit covers that run only.
%
%   t       s, column
%   psiDeg  deg, encoder angle; zero need not be exactly hanging (an offset
%           is fitted)
%   opts.TStart  force the start time instead of detecting the release
%   Returns wg2 [1/s^2], gamma [1/s], Q (Inf if no viscous part), coulomb
%   [rad/s^2], offset [deg], rms residual [deg], the window used and the fitted
%   trace. Base MATLAB only (fminsearch).

    arguments
        t (:,1) double
        psiDeg (:,1) double
        opts.TStart (1,1) double = NaN
    end

    if isnan(opts.TStart), [k0, k1] = freeWindow(t, psiDeg);
    else, k0 = find(t >= opts.TStart, 1); k1 = numel(t); end
    tw = t(k0:k1) - t(k0); y = psiDeg(k0:k1);

    % initial guesses: the rest level, and the period from full periods between
    % crossings of that level (a 0.3 deg dead band: an encoder count resting
    % exactly on the level is not a crossing)
    off0 = restLevel(t, psiDeg);
    sg = sign(y - off0); sg(abs(y - off0) < 0.3) = 0;
    nz = find(sg ~= 0); zc = nz([false; diff(sg(nz)) ~= 0]);
    if numel(zc) >= 3, T0 = median(tw(zc(3:end)) - tw(zc(1:end-2))); else, T0 = 2 * pi / sqrt(50); end
    pk = abs(y(1) - off0);

    % continuation: fit the first two periods, then four, then the whole decay,
    % each from the previous result. Fitting many cycles at once from a guess a
    % few % off lands in a wrong-phase minimum (2026-10-21: wg2 1.2e5 on R09).
    o = optimset('Display', 'off', 'MaxFunEvals', 4000, 'MaxIter', 4000, 'TolX', 1e-9, 'TolFun', 1e-12);
    best = []; fb = inf;
    for c0 = [0 0.3 1.0], for g0 = [0.02 0.3]
        x = [log((2 * pi / T0)^2), g0, c0, off0, y(1) - off0, 0.1];
        for span = [2 4 inf] * T0
            m = tw <= span; if nnz(m) < 10, continue; end
            cost = @(q) bounded(q, sum((simulate(q, tw(m)) - y(m)).^2));
            x = fminsearch(cost, x, o);
        end
        x = fminsearch(@(q) bounded(q, sum((simulate(q, tw) - y).^2)), x, o);   % restart once
        f = sum((simulate(x, tw) - y).^2); if f < fb, fb = f; best = x; end
    end, end
    x = best;

    fit.wg2 = exp(x(1)); fit.gamma = abs(x(2)); fit.coulomb = abs(x(3));
    fit.Q = sqrt(fit.wg2) / max(fit.gamma, eps); if fit.gamma < 1e-4, fit.Q = Inf; end
    fit.offsetDeg = x(4); fit.amplitudeDeg = abs(x(5)); fit.firstPeakDeg = pk;
    fit.stickBandDeg = rad2deg(fit.coulomb / fit.wg2);
    fit.tRelease = t(k0) + x(6);
    fit.tStart = t(k0); fit.tEnd = t(k1);
    fit.t = tw; fit.yDeg = y; fit.yFitDeg = simulate(x, tw);
    fit.rmsDeg = sqrt(mean((fit.yFitDeg - y).^2));
    fit.periodSmallAngle = 2 * pi / sqrt(fit.wg2);
end

function [k0, k1] = freeWindow(t, y)
% swing peaks between crossings of the rest level; the longest run of peaks
% that does not grow (0.3 deg tolerance) is the free decay
    off = restLevel(t, y);
    s = sign(y - off); s(abs(y - off) < 0.2) = 0;              % encoder 0.15 deg: ignore +-1 count
    nz = find(s ~= 0);
    if numel(nz) < 3, k0 = 1; k1 = numel(t); return; end
    cr = nz([false; diff(s(nz)) ~= 0]);                         % first sample after each crossing
    edges = [nz(1); cr; numel(y) + 1];
    P = zeros(0, 3);                                            % [index, amplitude, held]
    for i = 1:numel(edges) - 1
        seg = edges(i):edges(i + 1) - 1;
        [a, j] = max(abs(y(seg) - off));
        % a free apex stays within 0.5 deg of its extreme for well under 0.1 s;
        % longer means a hand held it there
        held = sum(abs(abs(y(seg) - off) - a) <= 0.5) * median(diff(t)) > 0.2;
        if a >= 0.75, P(end + 1, :) = [seg(j), a, held]; end %#ok<AGROW>
    end
    if size(P, 1) < 2, k0 = 1; k1 = numel(t); return; end
    best = [1 1]; i = 1;
    while i <= size(P, 1)
        j = i;
        while j < size(P, 1) && P(j + 1, 2) <= P(j, 2) + 0.5 && ~P(j + 1, 3), j = j + 1; end   % a held peak starts a new run
        if j - i >= best(2) - best(1), best = [i j]; end          % ties: the later run
        i = j + 1;
    end
    k0 = P(best(1), 1);
    % a hand may hold the pendulum at the top before letting go: the release is
    % where it starts to fall (> 1.5 deg within the next 0.1 s; a free fall from
    % 10 deg covers about 3 deg in 0.1 s, a hand drifts < 0.5); start 0.15 s
    % before it and let the fit find the instant (tau)
    nw = max(1, round(0.1 / median(diff(t))));
    kp = P(best(1), 1);
    while kp + nw <= numel(y) && abs(y(kp + nw) - y(kp)) <= 1.5, kp = kp + 1; end
    k0 = max(k0, find(t >= t(kp) - 0.15, 1));
    if best(2) < size(P, 1)                                      % pushed again: stop before that swing
        k1 = P(best(2) + 1, 1) - 1;
        k1 = edges(find(edges <= k1, 1, 'last'));
        k1 = max(k1 - 1, P(best(2), 1) + 1);
    else
        k1 = numel(t);
    end
    k1 = min(k1, numel(t));
end

function c = bounded(q, c)
% physical bounds: wg2 between 5 and 500 1/s^2 (pendulums from 4 cm to 2 m)
    if q(1) < log(5) || q(1) > log(500), c = c + 1e9; end
    if q(6) < 0 || q(6) > 0.4, c = c + 1e9; end            % release instant inside the window
end

function off = restLevel(t, y)
% where the pendulum hangs still: no encoder change for 0.5 s (a swing peak
% holds one encoder value for much less, even at 1 deg of amplitude)
    n = max(2, round(0.5 / median(diff(t))));
    still = movmax(abs([0; diff(y)]), [n - 1 0]) == 0;
    if nnz(still) >= n, off = median(y(still)); else, off = median(y); end
end

function yDeg = simulate(x, t)
% psi'' = -wg2 sin(psi - off) - gamma psi' - c sgn(psi'), with sticking;
% semi-implicit Euler, 0.5 ms steps; held at the start angle until tau = x(6)
    w = exp(x(1)); g = abs(x(2)); c = abs(x(3)); off = deg2rad(x(4)); tau = x(6);
    a = deg2rad(x(5)) + off; v = 0; h = 5e-4;
    yDeg = zeros(size(t)); yDeg(1) = rad2deg(a);
    for k = 2:numel(t)
        n = max(1, round((t(k) - t(k-1)) / h)); hh = (t(k) - t(k-1)) / n;
        for i = 1:n
            if t(k - 1) + i * hh <= tau, continue; end          % still in the hand
            drive = -w * sin(a - off) - g * v;
            if v == 0 && abs(drive) <= c, continue; end
            if v ~= 0, sg = sign(v); else, sg = sign(drive); end
            vn = v + (drive - c * sg) * hh;
            if v ~= 0 && vn * v < 0, vn = 0; end
            v = vn; a = a + v * hh;
        end
        yDeg(k) = rad2deg(a);
    end
end

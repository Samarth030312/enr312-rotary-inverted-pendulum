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

    % initial guesses: period from the crossings, offset from the rest at the end
    off0 = restLevel(t, psiDeg);
    z = find(diff(sign(y - off0)) ~= 0);
    if numel(z) >= 3, T0 = 2 * mean(diff(tw(z))); else, T0 = 2 * pi / sqrt(50); end
    pk = abs(y(1) - off0);

    cost = @(x) sum((simulate(x, tw) - y).^2);
    o = optimset('Display', 'off', 'MaxFunEvals', 4000, 'MaxIter', 4000, 'TolX', 1e-9, 'TolFun', 1e-12);
    best = []; fb = inf;
    for c0 = [0 0.3 1.0], for g0 = [0.02 0.3]
        x = fminsearch(cost, [log((2 * pi / T0)^2), g0, c0, off0, y(1) - off0], o);
        x = fminsearch(cost, x, o);                              % restart once
        f = cost(x); if f < fb, fb = f; best = x; end
    end, end
    x = best;

    fit.wg2 = exp(x(1)); fit.gamma = abs(x(2)); fit.coulomb = abs(x(3));
    fit.Q = sqrt(fit.wg2) / max(fit.gamma, eps); if fit.gamma < 1e-4, fit.Q = Inf; end
    fit.offsetDeg = x(4); fit.amplitudeDeg = abs(x(5)); fit.firstPeakDeg = pk;
    fit.stickBandDeg = rad2deg(fit.coulomb / fit.wg2);
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
    P = zeros(0, 2);                                            % [index, amplitude]
    for i = 1:numel(edges) - 1
        seg = edges(i):edges(i + 1) - 1;
        [a, j] = max(abs(y(seg) - off));
        if a >= 0.75, P(end + 1, :) = [seg(j), a]; end %#ok<AGROW>
    end
    if size(P, 1) < 2, k0 = 1; k1 = numel(t); return; end
    best = [1 1]; i = 1;
    while i <= size(P, 1)
        j = i;
        while j < size(P, 1) && P(j + 1, 2) <= P(j, 2) + 0.5, j = j + 1; end
        if j - i >= best(2) - best(1), best = [i j]; end          % ties: the later run
        i = j + 1;
    end
    k0 = P(best(1), 1);
    if best(2) < size(P, 1)                                      % pushed again: stop before that swing
        k1 = P(best(2) + 1, 1) - 1;
        k1 = edges(find(edges <= k1, 1, 'last'));
        k1 = max(k1 - 1, P(best(2), 1) + 1);
    else
        k1 = numel(t);
    end
    k1 = min(k1, numel(t));
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
% semi-implicit Euler, 0.5 ms steps
    w = exp(x(1)); g = abs(x(2)); c = abs(x(3)); off = deg2rad(x(4));
    a = deg2rad(x(5)) + off; v = 0; h = 5e-4;
    yDeg = zeros(size(t)); yDeg(1) = rad2deg(a);
    for k = 2:numel(t)
        n = max(1, round((t(k) - t(k-1)) / h)); hh = (t(k) - t(k-1)) / n;
        for i = 1:n
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

function fit = pendulum_free_swing_fit(t, psiDeg, opts)
%PENDULUM_FREE_SWING_FIT  Identify wg2 and Q from a hanging free-swing record.
%
%   fit = pendulum_free_swing_fit(t, psiDeg)
%
%   Experiment (motor UNPOWERED or holding still, so theta'' = 0): displace
%   the hanging pendulum by 10-40 deg, release it, record the encoder angle.
%   The model is the NONLINEAR pendulum
%       psi'' = -wg2 sin(psi) - gamma psi'
%   (rotary_pendulum_psiddot with the arm still), so large amplitudes are
%   fitted correctly; a linear fit would bias wg2 low (about 3.4 % at 30 deg: the period of a
%   pendulum grows with amplitude: +1.7 % at 30 deg).
%
%   t       s, column
%   psiDeg  deg, encoder angle; zero need not be exactly hanging (an offset
%           is fitted)
%   Returns wg2 [1/s^2], gamma [1/s], Q, offset [deg], rms residual [deg],
%   and the fitted trace. Base MATLAB only (fminsearch).

    arguments
        t (:,1) double
        psiDeg (:,1) double
        opts.TStart (1,1) double = NaN     % default: first peak
    end

    % start at the first local extremum, so psiDot(0) ~ 0
    if isnan(opts.TStart)
        d = diff(psiDeg);
        k0 = find(sign(d(1:end-1)) ~= sign(d(2:end)), 1) + 1;
        if isempty(k0), k0 = 1; end
    else
        k0 = find(t >= opts.TStart, 1);
    end
    t = t(k0:end) - t(k0); y = psiDeg(k0:end);

    % initial guesses from zero crossings of the de-meaned signal
    off0 = mean(y(end - round(numel(y) / 4):end));
    z = find(diff(sign(y - off0)) ~= 0);
    if numel(z) >= 3, T0 = 2 * mean(diff(t(z))); else, T0 = 2 * pi / sqrt(57); end
    pk = abs(y(1) - off0);
    x0 = [log((2 * pi / T0)^2), log(0.3), off0, y(1) - off0];   % [log wg2, log gamma, offset, A0]

    cost = @(x) sum((simulate(x, t) - y).^2);
    o = optimset('Display', 'off', 'MaxFunEvals', 4000, 'MaxIter', 4000, 'TolX', 1e-9, 'TolFun', 1e-12);
    x = fminsearch(cost, x0, o);
    x = fminsearch(cost, x, o);                  % restart once for robustness

    fit.wg2 = exp(x(1)); fit.gamma = exp(x(2));
    fit.Q = sqrt(fit.wg2) / fit.gamma;
    fit.offsetDeg = x(3); fit.amplitudeDeg = abs(x(4)); fit.firstPeakDeg = pk;
    fit.t = t; fit.yDeg = y; fit.yFitDeg = simulate(x, t);
    fit.rmsDeg = sqrt(mean((fit.yFitDeg - y).^2));
    fit.periodSmallAngle = 2 * pi / sqrt(fit.wg2);
end

function yDeg = simulate(x, t)
%SIMULATE  RK4 of psi'' = -wg2 sin psi - gamma psi' (rotary_pendulum_psiddot with
%   the arm still), inlined for speed inside fminsearch.
    w = exp(x(1)); g = exp(x(2)); off = x(3);
    a = deg2rad(x(4)); v = 0;
    yDeg = zeros(size(t)); yDeg(1) = rad2deg(a) + off;
    for k = 2:numel(t)
        H = t(k) - t(k-1); n = max(1, ceil(H / 1e-3)); h = H / n;
        for i = 1:n
            k1a = v;              k1v = -w*sin(a) - g*v;
            a2 = a + h/2*k1a;     v2 = v + h/2*k1v;
            k2a = v2;             k2v = -w*sin(a2) - g*v2;
            a3 = a + h/2*k2a;     v3 = v + h/2*k2v;
            k3a = v3;             k3v = -w*sin(a3) - g*v3;
            a4 = a + h*k3a;       v4 = v + h*k3v;
            k4a = v4;             k4v = -w*sin(a4) - g*v4;
            a = a + h/6*(k1a + 2*k2a + 2*k3a + k4a);
            v = v + h/6*(k1v + 2*k2v + 2*k3v + k4v);
        end
        yDeg(k) = rad2deg(a) + off;
    end
end

function ok = rotary_pendulum_validate_physics()
%ROTARY_PENDULUM_VALIDATE_PHYSICS  Checks on the nonlinear pendulum model.
%
%   Each check compares the model against something INDEPENDENT of it:
%   the Tutorial linear models, the exact large-amplitude pendulum period
%   (complete elliptic integral), energy conservation, and the linear
%   fall-time formula. Also checks that the free-swing identifier recovers
%   known parameters from SYNTHETIC data with encoder quantisation.
%   Base MATLAB only. Prints a PASS/FAIL table; returns true if all pass.

    R = {};
    pI = rotary_pendulum_params('inverted');
    pS = rotary_pendulum_params('suspended');

    % 1. wr2/wg2 = r/g: Tutorial values imply r close to the manual's 0.14 m
    R(end+1, :) = chk('r implied by Tutorial 5 (m)', 0.14, pI.rImplied, 0.03);
    R(end+1, :) = chk('r implied by Tutorial 3/12 (m)', 0.14, pS.rImplied, 0.03);

    % 2. Linearisation reproduces the Tutorial transfer functions
    h = 1e-6;
    dS = (rotary_pendulum_psiddot(h, 0, 0, 0, pS) - rotary_pendulum_psiddot(-h, 0, 0, 0, pS)) / (2*h);
    R(end+1, :) = chk('hanging  d(psi'''')/d(psi) = -wg2', -pS.wg2, dS, 1e-6);
    cS = rotary_pendulum_psiddot(0, 0, 0, 1, pS) - rotary_pendulum_psiddot(0, 0, 0, 0, pS);
    R(end+1, :) = chk('hanging  d(psi'''')/d(theta'''') = +wr2', pS.wr2, cS, 1e-9);
    dI = (rotary_pendulum_psiddot(pi + h, 0, 0, 0, pI) - rotary_pendulum_psiddot(pi - h, 0, 0, 0, pI)) / (2*h);
    R(end+1, :) = chk('upright  d(psi'''')/d(psi) = +wg2 (unstable)', pI.wg2, dI, 1e-6);
    cI = rotary_pendulum_psiddot(pi, 0, 0, 1, pI) - rotary_pendulum_psiddot(pi, 0, 0, 0, pI);
    R(end+1, :) = chk('upright  d(psi'''')/d(theta'''') = -wr2 (SIGN FLIP)', -pI.wr2, cI, 1e-9);

    % 3. Period: small amplitude and 40 deg against the elliptic-integral law
    q = pS; q.gamma = 0;
    for A = [1 40]
        [t, psi] = swing(q, deg2rad(A), 6, 2e-4);
        Tm = measuredPeriod(t, psi);
        K = ellipke(sin(deg2rad(A) / 2)^2);
        Tth = 4 * K / sqrt(q.wg2);
        R(end+1, :) = chk(sprintf('period at %2d deg vs exact (s)', A), Tth, Tm, 2e-4); %#ok<AGROW>
    end

    % 4. Energy conservation, undamped, 60 deg, 10 s
    [t, psi, psiD] = swing(q, deg2rad(60), 10, 1e-3);
    E = 0.5 * psiD.^2 + q.wg2 * (1 - cos(psi));
    R(end+1, :) = chk('energy drift over 10 s (relative)', 0, max(abs(E - E(1))) / E(1), 1e-6);

    % 5. Upright fall from 1 deg to 15 deg: linear formula vs nonlinear
    lam = (-pI.gamma + sqrt(pI.gamma^2 + 4 * pI.wg2)) / 2;
    lam2 = (-pI.gamma - sqrt(pI.gamma^2 + 4 * pI.wg2)) / 2;
    a0 = deg2rad(1);  c1 = a0 * (-lam2) / (lam - lam2); c2 = a0 - c1;   % alpha'(0)=0
    tl = fzero(@(tt) c1 * exp(lam * tt) + c2 * exp(lam2 * tt) - deg2rad(15), 0.4);
    [t, psi] = swing(pI, pi + a0, 1.0, 1e-4);
    tn = t(find(abs(psi - pi) >= deg2rad(15), 1));
    R(end+1, :) = chk('fall 1->15 deg, linear formula (s)', tl, tn, 0.02);
    R(end+1, :) = row('fall: nonlinear slower than linear (sin a < a)', tn > tl, ...
                      sprintf('%.4f vs %.4f s', tn, tl));

    % 6. Free-swing identification on SYNTHETIC data (0.15 deg quantised, 50 Hz)
    [t, psi] = swing(pS, deg2rad(25), 15, 5e-4);
    ts = (0:0.02:15)'; ys = interp1(t, rad2deg(psi), ts);
    ys = round(ys / 0.15) * 0.15 + 0.3;                     % encoder + 0.3 deg datum error
    f = pendulum_free_swing_fit(ts, ys);
    R(end+1, :) = chk('ID: wg2 from synthetic swing', pS.wg2, f.wg2, 0.005);
    R(end+1, :) = chk('ID: Q from synthetic swing',   pS.Q,   f.Q,   0.10);
    R(end+1, :) = chk('ID: datum offset (deg)',        0.3,    f.offsetDeg, 0.1);

    % report
    fprintf('\nRotary pendulum physics validation\n%s\n', repmat('-', 1, 92));
    for i = 1:size(R, 1)
        fprintf('  %-52s %-28s %s\n', R{i, 1}, R{i, 3}, ternary(R{i, 2}, 'PASS', 'FAIL'));
    end
    n = sum([R{:, 2}]);
    fprintf('%s\n  %d / %d checks passed\n\n', repmat('-', 1, 92), n, size(R, 1));
    ok = n == size(R, 1);
end

function r = chk(name, expected, actual, relTol)
    if expected == 0, pass = abs(actual) <= relTol;
    else, pass = abs(actual - expected) <= relTol * abs(expected); end
    r = {name, pass, sprintf('exp %-9.5g got %-9.5g', expected, actual)};
end

function r = row(name, pass, txt)
    r = {name, pass, txt};
end

function [t, psi, psiD] = swing(p, psi0, T, h)
%SWING  RK4 with the arm still (theta' = theta'' = 0).
    n = round(T / h); t = (0:n)' * h;
    psi = zeros(n + 1, 1); psiD = psi; s = [psi0; 0];
    f = @(q) [q(2); rotary_pendulum_psiddot(q(1), q(2), 0, 0, p)];
    psi(1) = s(1);
    for k = 1:n
        k1 = f(s); k2 = f(s + h/2*k1); k3 = f(s + h/2*k2); k4 = f(s + h*k3);
        s = s + h/6 * (k1 + 2*k2 + 2*k3 + k4);
        psi(k+1) = s(1); psiD(k+1) = s(2);
    end
end

function T = measuredPeriod(t, psi)
    % downward zero crossings, linearly interpolated
    i = find(psi(1:end-1) > 0 & psi(2:end) <= 0);
    tc = t(i) + (t(i+1) - t(i)) .* psi(i) ./ (psi(i) - psi(i+1));
    T = mean(diff(tc));
end

function s = ternary(c, a, b)
    if c, s = a; else, s = b; end
end

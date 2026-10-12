function yDeg = pendulum_free_swing_sim(t, wg2, gamma, ampDeg, offsetDeg)
%PENDULUM_FREE_SWING_SIM  Free swing of the hanging pendulum, arm still (deg).
%
%   yDeg = pendulum_free_swing_sim(t, wg2, gamma, ampDeg, offsetDeg)
%   Released from rest at ampDeg (relative to hanging) at t(1).
%   Nonlinear: psi'' = -wg2 sin(psi) - gamma psi'  (rotary_pendulum_psiddot).
%   RK4 with steps <= 1 ms. Used to overlay a model prediction on data.
    p = struct('wg2', wg2, 'wr2', 0, 'gamma', gamma);
    s = [deg2rad(ampDeg); 0];
    yDeg = zeros(size(t)); yDeg(1) = ampDeg + offsetDeg;
    f = @(q) [q(2); rotary_pendulum_psiddot(q(1), q(2), 0, 0, p)];
    for k = 2:numel(t)
        H = t(k) - t(k-1); n = max(1, ceil(H / 1e-3)); h = H / n;
        for i = 1:n
            k1 = f(s); k2 = f(s + h/2*k1); k3 = f(s + h/2*k2); k4 = f(s + h*k3);
            s = s + h/6 * (k1 + 2*k2 + 2*k3 + k4);
        end
        yDeg(k) = rad2deg(s(1)) + offsetDeg;
    end
end

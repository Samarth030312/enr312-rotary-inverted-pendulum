function r = derivativeNoise(t, angDeg, fc, nMA)
%DERIVATIVENOISE  PEND C11 and Q8: quantisation, derivative noise, D filter, moving average.
%
%   r = odyssix.pend.derivativeNoise(t, angDeg)
%   r = odyssix.pend.derivativeNoise(t, angDeg, fc, nMA)
%
%   The encoder gives the angle in steps of q = 360/2400 = 0.15 deg. A raw
%   difference derivative at sample period Ts can only take the values
%   k q / Ts: at the firmware's 500 Hz one count is 75 deg/s, so a pendulum
%   sitting still between two counts reads 0 or +/-75 deg/s. Multiplied by
%   the pendulum D gain (Kd 30) that is 2250 deg/s^2 of plant input from one
%   count: more than the 1500 deg/s^2 actuator limit. Hence the firmware's
%   first-order low-pass on D (corner fc, default 10 Hz for the pendulum).
%
%   Applied to a recorded or simulated angle (t [s], angDeg [deg]):
%     r.q, r.Ts          count size [deg], sample period [s]
%     r.dRaw             raw difference derivative [deg/s]
%     r.dFilt            same through the firmware's filter at fc [Hz]
%     r.dMA              same through an nMA-point moving average (Q8)
%     r.rmsRaw/Filt/MA   rms of each on the record [deg/s]
%     r.lagFiltS         filter lag at low frequency, 1/(2 pi fc) [s]
%     r.lagMAS           moving-average lag, (nMA-1) Ts / 2 [s]
%   The trade-off: more smoothing = less noise and more lag, and lag costs
%   phase margin (odyssix.sim.loop / gainSweep with 'fdp' or 'ma').
%   NOTE the lab app logs at 50 Hz; the firmware differentiates at 500 Hz,
%   so apply this to a 500 Hz record (emulator / simulation) for the
%   firmware's numbers.
    if nargin < 3 || isempty(fc), fc = 10; end
    if nargin < 4 || isempty(nMA), nMA = 8; end
    t = t(:); y = angDeg(:);
    Ts = median(diff(t));
    r.q = 360 / 2400; r.Ts = Ts;
    r.countRateDegS = r.q / Ts;
    r.dRaw = [0; diff(y) / Ts];
    % the firmware's filter (enr312_ctrl.c lp_alpha): d += a (raw - d), a = 1 - exp(-2 pi fc Ts)
    a = 1 - exp(-2 * pi * fc * Ts);
    d = 0; r.dFilt = zeros(size(y));
    for k = 2:numel(y)
        d = d + a * (r.dRaw(k) - d); r.dFilt(k) = d;
    end
    r.dMA = filter(ones(nMA, 1) / nMA, 1, r.dRaw);
    r.rmsRaw = sqrt(mean(r.dRaw.^2));
    r.rmsFilt = sqrt(mean(r.dFilt.^2));
    r.rmsMA = sqrt(mean(r.dMA.^2));
    r.lagFiltS = 1 / (2 * pi * fc);
    r.lagMAS = (nMA - 1) * Ts / 2;
    r.fc = fc; r.nMA = nMA;
end

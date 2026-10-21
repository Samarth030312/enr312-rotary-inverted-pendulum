function r = freeSwing(t, psiDeg, nOsc)
%FREESWING  PEND A4: period, equivalent length and damping from a free swing.
%
%   r = odyssix.pend.freeSwing(t, psiDeg)
%   r = odyssix.pend.freeSwing(t, psiDeg, nOsc)       % default nOsc = 10
%
%   The experiment: motor still, displace the hanging pendulum by 10-20 deg,
%   let go, record the encoder (the lab app's "Free swing" button, or by hand
%   with a stopwatch over nOsc full oscillations).
%
%   What it computes, and the physics behind each number:
%     T       period [s] = (time of peak 1+nOsc - time of peak 1) / nOsc,
%             exactly what a stopwatch over nOsc oscillations measures
%     T0      T corrected to small amplitude: T = T0 (1 + A^2/16 + 11 A^4/3072),
%             A [rad] = mean peak amplitude over the n periods
%     Lsimple g (T0/2pi)^2 [m]: the length of the SIMPLE pendulum (point
%             mass on a massless string) that would swing with this period
%     delta   log decrement = ln(A_1 / A_{1+n}) / n
%     zeta    damping ratio = delta / sqrt(4 pi^2 + delta^2);  Q = 1/(2 zeta)
%     wg2     (2pi/T0)^2 [1/s^2], the model's gravity constant
%     fit     nonlinear least-squares fit (pendulum_free_swing_fit), which
%             uses the whole record rather than the peaks
%
%   Comparing with a ruler. The rig's pendulum is a COMPOUND pendulum (a rod
%   with a pivot fitting), so Lsimple = J/(m lc) is NOT the rod length. For a
%   uniform rod pivoted at one end Lsimple = 2/3 of the rod; Tutorial 5 writes
%   wg2 = g/(0.6805 L), i.e. Lsimple = 0.6805 L for the Edukit pendulum.
%   r.LrodPredicted = Lsimple / 0.6805 is the length a ruler should read.
%
%   psiDeg: encoder angle [deg], 0 = hanging (an offset is removed).
    if nargin < 3, nOsc = 10; end
    t = t(:); y = psiDeg(:);
    g = 9.81;
    off = median(y(round(end * 3 / 4):end));
    y = y - off;
    pk = peaks_(y);
    if numel(pk) < 3, error('odyssix:pend', 'fewer than 3 swing peaks: record longer or swing wider'); end
    n = min(nOsc, numel(pk) - 1);
    r.nOsc = n;
    r.tPeaks = t(pk); r.aPeaks = y(pk);
    r.T = (t(pk(1 + n)) - t(pk(1))) / n;
    % the swing decays over the n periods: correct with the mean peak amplitude
    A = deg2rad(mean(abs(y(pk(1:1+n)))));
    r.amplitudeDeg = rad2deg(A);
    r.T0 = r.T / (1 + A^2 / 16 + 11 * A^4 / 3072);
    r.Lsimple = g * (r.T0 / (2 * pi))^2;
    r.LrodPredicted = r.Lsimple / 0.6805;
    r.delta = log(abs(y(pk(1))) / abs(y(pk(1 + n)))) / n;
    r.zeta = r.delta / sqrt(4 * pi^2 + r.delta^2);
    r.Q = 1 / (2 * r.zeta);
    r.wg2 = (2 * pi / r.T0)^2;
    r.offsetDeg = off;
    try
        r.fit = pendulum_free_swing_fit(t, psiDeg(:));
    catch err
        r.fit = struct('error', err.message);
    end
end

function k = peaks_(y)
% positive local maxima above 0.5 deg (2-3 encoder counts). The encoder holds
% each value for several samples, so runs of equal values are collapsed first
% and a peak is a run higher than the runs on both sides; its index is the
% middle of the run.
    st = [1; find(diff(y) ~= 0) + 1];          % start of each run
    en = [st(2:end) - 1; numel(y)];
    v = y(st);
    m = find(v(2:end-1) > v(1:end-2) & v(2:end-1) > v(3:end) & v(2:end-1) > 0.5) + 1;
    k = round((st(m) + en(m)) / 2);
end

function r = recovery(t, ang, t0, band, tEnd)
%RECOVERY  Time for an angle to return and stay inside a band after an event.
%
%   r = odyssix.pend.recovery(t, ang, t0, band)
%   r = odyssix.pend.recovery(t, ang, t0, band, tEnd)
%
%   PEND A5 (time to stop a swing, suspended PID: ang = psi, band e.g. 1 deg)
%   PEND A7 (tap recovery, inverted: ang = alpha, band e.g. 1 deg)
%   t0    event time [s] (release of the pluck, or the tap)
%   band  [deg]; recovered = |ang| <= band from then until tEnd
%   tEnd  end of the window (default: end of record or next event)
%   Returns peak |ang| [deg] after t0, the time of the peak, and the recovery
%   time [s] after t0 (NaN = never recovered inside the window). A 50 Hz app
%   log resolves the time to 20 ms.
    if nargin < 5 || isempty(tEnd), tEnd = t(end); end
    w = t >= t0 & t <= tEnd;
    tw = t(w); a = abs(ang(w));
    if isempty(a), r = struct('peakDeg', NaN, 'tPeak', NaN, 'recoverS', NaN); return; end
    [r.peakDeg, k] = max(a); r.tPeak = tw(k) - t0;
    out = a > band;
    if out(end), r.recoverS = NaN;
    elseif ~any(out), r.recoverS = 0;
    else, r.recoverS = tw(find(out, 1, 'last') + 1) - t0;
    end
    r.band = band;
end

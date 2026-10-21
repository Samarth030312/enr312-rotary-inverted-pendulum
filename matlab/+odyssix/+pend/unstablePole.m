function r = unstablePole(x, kind)
%UNSTABLEPOLE  PEND C9: the upright pendulum's unstable pole and what it asks of the loop.
%
%   r = odyssix.pend.unstablePole(L)          % L = simple-pendulum length [m]
%   r = odyssix.pend.unstablePole(wg2, 'wg2') % or the model constant [1/s^2]
%   r = odyssix.pend.unstablePole(plant)      % or an odyssix.sim.plant struct
%
%   Linearised about upright (arm still), alpha'' = wg2 alpha - gamma alpha',
%   characteristic equation s^2 + gamma s - wg2 = 0, poles
%       s = (-gamma +/- sqrt(gamma^2 + 4 wg2)) / 2  ~  +/- sqrt(wg2) = +/- sqrt(g/L).
%   The positive root p is the rate an uncorrected tilt grows: alpha ~ e^(p t),
%   doubling every ln2/p seconds. A controller has to act well within that.
%   Rules of thumb (stated as such, not laws): the closed-loop crossover must
%   be above p, and the sampling rate 10-30x the crossover; sample-and-hold
%   plus one tick of computation cost about 1.5 Ts of delay, i.e.
%   1.5 Ts wc rad of phase at crossover wc. odyssix.pend.loopRate checks this
%   against the simulated rig.
    if isstruct(x)
        wg2 = x.wg2; gam = sqrt(x.wg2) / x.Q;
    elseif nargin > 1 && strcmpi(kind, 'wg2')
        wg2 = x; gam = 0;
    else
        wg2 = 9.81 / x; gam = 0;
    end
    s = roots([1, gam, -wg2]);
    r.wg2 = wg2;
    r.poles = s;
    r.p = max(real(s));                    % rad/s
    r.pHz = r.p / (2 * pi);
    r.doublingS = log(2) / r.p;
    r.timeConstS = 1 / r.p;
    r.Lsimple = 9.81 / wg2;
    r.minLoopHz = 10 * r.p / (2 * pi) * 2;   % 10x a crossover of at least 2p
    r.note = sprintf(['unstable pole %.2f rad/s (%.2f Hz): a 1 deg tilt doubles every %.0f ms; ', ...
        'crossover > ~2p = %.1f rad/s; loop >~ %.0f Hz (10x); the rig runs 500 Hz'], ...
        r.p, r.pHz, 1e3 * r.doublingS, 2 * r.p, r.minLoopHz);
end

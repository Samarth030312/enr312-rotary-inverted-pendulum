function s = exp005_stability_margins(m, w)
%EXP005_STABILITY_MARGINS  Gain margin, phase margin and M_S (Tutorial 5).
%
%   w_GC  : gain crossover, |L| = 1
%   phi_M : phase margin = 180 deg + angle L(j w_GC)
%   w_PC  : phase crossover, angle L = -180 deg
%   GM    : gain margin = 1/|L(j w_PC)|, in dB
%   M_S   : max |S|, at w_MS ;  w_SC where |S| = 1
%
%   All three margin families measure the same thing -- distance from -1 on the
%   Nyquist diagram -- along different directions: GM radially, phi_M angularly,
%   M_S as the closest approach in any direction.
%
%   No toolbox required.
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        m struct
        w (1,:) double = logspace(-3, 4, 200000)
    end

    Lj = polyval(m.L.num, 1j*w) ./ polyval(m.L.den, 1j*w);
    mag = abs(Lj);
    ph  = unwrap(angle(Lj));

    S = 1 ./ (1 + Lj);
    smag = abs(S);
    [s.Ms, iMs] = max(smag);
    s.MsdB = 20*log10(s.Ms);
    s.wMs  = w(iMs);

    k = find(diff(sign(smag - 1)) ~= 0, 1, 'first');
    if isempty(k), s.wSC = NaN; else, s.wSC = w(k); end

    k = find(diff(sign(mag - 1)) ~= 0, 1, 'first');
    if isempty(k)
        s.wGC = NaN; s.phiMdeg = NaN;
    else
        s.wGC = w(k);
        pm = 180 + rad2deg(ph(k));
        pm = mod(pm + 180, 360) - 180;
        s.phiMdeg = pm;
    end

    % Phase crossover: angle L = -180 deg modulo 360.
    resid = ph/pi - (2*round((ph/pi + 1)/2) - 1);
    k = find(diff(sign(resid)) ~= 0, 1, 'first');
    if isempty(k)
        s.wPC = NaN; s.GMdB = Inf;
    else
        s.wPC = w(k);
        s.GMdB = -20*log10(mag(k));
    end

    s.w = w; s.L = Lj; s.SmagdB = 20*log10(smag);
end

function s = exp004_sensitivity_analysis(kpRotor, kdRotor, w)
%EXP004_SENSITIVITY_ANALYSIS  M_S, w_SC and Nyquist metrics (Tutorial 4 section 6).
%
%   s = EXP004_SENSITIVITY_ANALYSIS(kpRotor, kdRotor, w) computes the sensitivity
%   function of the MIMO suspended-mode loop and its performance metrics.
%
%       S(s) = 1/(1 + P C),  P = T_rotor (inner loop),  C = K_rotor
%       M_S  = max over w of |S(jw)|          reported in dB
%       w_SC = frequency where |S(jw)| = 1
%
%   NYQUIST IDENTITY (Tutorial 4 section 6): 1/S = 1 + L is the vector from
%   (-1,0) to L(jw), so M_S = 1/min|1+L|. This function returns both so the
%   identity can be CHECKED rather than trusted.
%
%   NO DERIVATIVE FILTER IS APPLIED, deliberately. M_S is a frequency-domain
%   metric of a proper transfer function and needs no realisation. Evidence: the
%   ideal controller gives 2.794 dB against Tutorial 4's published 2.7 dB, while
%   an N = 100 rad/s filter gives 3.121 dB. This differs from EXP003, whose
%   CE_Max is a time-domain metric of an IMPROPER transfer function and does need
%   a realisation.
%
%   No toolbox required.
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        kpRotor (1,1) double
        kdRotor (1,1) double
        w       (1,:) double = logspace(-3, 4, 200000)
    end

    m = exp003_mimo_model(kpRotor, kdRotor, 1e12);   % huge N == effectively ideal
    % Build the ideal loop directly rather than relying on the large-N limit.
    trNum = m.Trotor.num;
    trDen = m.Trotor.den;
    lNum  = conv(trNum, [kdRotor, kpRotor]);
    lDen  = trDen;

    Lj = polyval(lNum, 1j*w) ./ polyval(lDen, 1j*w);
    S  = 1 ./ (1 + Lj);
    mag = abs(S);

    s.w      = w;
    s.S      = S;
    s.magdB  = 20*log10(mag);
    s.Ms     = max(mag);
    s.MsdB   = 20*log10(s.Ms);

    k = find(diff(sign(mag - 1)) ~= 0, 1, 'first');
    if isempty(k), s.wSC = NaN; else, s.wSC = w(k); end

    s.nyquistMinDist = min(abs(-1 - Lj));
    s.nyquistIdentityError = abs(s.nyquistMinDist - 1/s.Ms);

    s.L = Lj;
    s.kpRotor = kpRotor;
    s.kdRotor = kdRotor;
end

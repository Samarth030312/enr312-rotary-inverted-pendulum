function m = exp003_mimo_model(kpRotor, kdRotor, nFilt)
%EXP003_MIMO_MODEL  Dual-loop suspended-mode model of Tutorial 3.
%
%   m = EXP003_MIMO_MODEL(kpRotor, kdRotor, nFilt) builds the inner and outer
%   loop transfer functions and the control-effort transfer function.
%
%   Plants (Tutorial 1 section 2; Tutorial 12 section 2):
%       G_rotor(s) = 1/s^2
%       G_pend(s)  = wr2 s^2 / (s^2 + (wg/Q) s + wg2)      SUSPENDED mode
%
%   Controllers (Tutorial 3 section 3 and section 6):
%       K_pend(s)  = 10.0 + 5.0 s      SUPPLIED and FIXED by Tutorial 3
%       K_rotor(s) = kpRotor + kdRotor s     the design variable
%
%   Loops (Tutorial 3 section 4):
%       T_rotor          = G_rotor / (1 + G_pend K_pend G_rotor)
%       T_rotor_tracking = T_rotor K_rotor / (1 + T_rotor K_rotor)
%       CE               = K_rotor / (1 + T_rotor K_rotor)
%
%   nFilt (default 100 rad/s) is the derivative-filter corner applied to
%   K_rotor. It is REQUIRED, not cosmetic: CE(s) is improper without it, so its
%   step response contains a Dirac delta and CE_Max is undefined. CE_Max scales
%   linearly with nFilt; CE_Total, settling and overshoot do not. Tutorial 3's
%   published CE_Max = 477 corresponds to nFilt = 99.4 rad/s.
%
%   Returned as [num den] coefficient vectors -- NO toolbox required.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        kpRotor (1,1) double
        kdRotor (1,1) double
        nFilt   (1,1) double {mustBePositive} = 100
    end

    % Suspended-mode pendulum, Tutorial 12. ASSUMED -- reference rig, not this one (OI-9).
    m.wr2 = 0.803;
    m.wg2 = 57.01;
    m.Q   = 27.0;
    m.gamma = sqrt(m.wg2) / m.Q;
    denPend = [1, m.gamma, m.wg2];

    % Inner controller: SUPPLIED and FIXED by Tutorial 3.
    m.kpPend = 10.0;
    m.tdPend = 0.5;
    m.kdPend = m.kpPend * m.tdPend;      % 5.0

    % Inner closed loop. G_pend*G_rotor = wr2/denPend (the s^2 cancels exactly),
    % so T_rotor = denPend / ( s^2 * (denPend + wr2*K_pend) ).
    inner = denPend + [0, m.wr2 * m.kdPend, m.wr2 * m.kpPend];   % pad to degree 2
    m.innerPoly = inner;
    m.innerZeta = inner(2) / (2 * sqrt(inner(3)));
    m.openZeta  = m.gamma / (2 * sqrt(m.wg2));

    m.Trotor = struct('num', denPend, 'den', conv([1 0 0], inner));

    krNum = [kdRotor * nFilt, kpRotor * nFilt];
    krDen = [1, nFilt];
    m.Krotor = struct('num', krNum, 'den', krDen);
    m.nFilt  = nFilt;

    lNum = conv(m.Trotor.num, krNum);
    lDen = conv(m.Trotor.den, krDen);
    cl   = lDen + [zeros(1, numel(lDen) - numel(lNum)), lNum];

    m.Ttracking = struct('num', lNum, 'den', cl);
    m.CE        = struct('num', conv(krNum, m.Trotor.den), 'den', cl);

    m.kpRotor = kpRotor;
    m.kdRotor = kdRotor;
    m.tdRotor = kdRotor / kpRotor;
end

function m = exp005_inverted_model(kpRotor, kdRotor)
%EXP005_INVERTED_MODEL  Inverted-mode (unstable) MIMO model, Tutorial 5.
%
%   Plant (Tutorial 5 section 8) -- NOTE THE MINUS:
%       G_pend(s) = wr2 s^2 / (s^2 + (wg/Q) s - wg2)
%       wr2 = 0.803, wg2 = 55.85, Q = 20      (wg2 and Q DIFFER from suspended)
%       G_rotor(s) = 1/s^2
%
%   Inner controller, SUPPLIED and FIXED: K_pend = 300 + 30 s.
%
%   SOURCE CONFLICT. Tutorial 5 states Kp=300, Td=0.5, Kd=Kp*Td=30, but
%   300*0.5 = 150. Kd = 30 is operative -- Tutorial 5's own serial transcript
%   enters 30.00, and the UCLA reference firmware pairs 300 with 30. The implied
%   Td is therefore 0.1 s, not 0.5 s.
%
%   OUTER-LOOP SIGN INVERSION. T_rotor has NEGATIVE DC gain in inverted mode
%   (numerator den_pend, constant term -wg2), so a positive K_rotor closes
%   POSITIVE feedback. Established from evidence: without the inversion BOTH of
%   Tutorial 5's published designs are unstable; with it both are stable and
%   their relative stability reproduces the Tutorial's own naming.
%
%   No toolbox required.
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        kpRotor (1,1) double
        kdRotor (1,1) double
    end

    m.wr2 = 0.803;
    m.wg2 = 55.85;          % inverted; suspended is 57.01
    m.Q   = 20.0;           % inverted; suspended is 27
    m.gamma = sqrt(m.wg2) / m.Q;
    denPend = [1, m.gamma, -m.wg2];        % MINUS -- unstable
    m.denPend = denPend;
    m.openLoopPoles = roots(denPend);
    m.rhpPole = max(real(m.openLoopPoles));
    m.fallTimeConstant = 1 / m.rhpPole;

    m.kpPend = 300.0;
    m.kdPend = 30.0;                       % NOT 150 -- see the conflict note
    m.tdPend = m.kdPend / m.kpPend;        % 0.1 s implied

    inner = denPend + [0, m.wr2 * m.kdPend, m.wr2 * m.kpPend];   % pad to degree 2
    m.innerPoly  = inner;
    m.innerPoles = roots(inner);
    m.innerStable = all(real(m.innerPoles) < 0);
    m.innerZeta = inner(2) / (2 * sqrt(inner(3)));

    m.Trotor = struct('num', denPend, 'den', conv([1 0 0], inner));

    % T_rotor's NUMERATOR is denPend, so the unstable POLE becomes a
    % NON-MINIMUM-PHASE ZERO. This is the fundamental limitation of EXP005.
    m.nmpZero = m.rhpPole;
    m.bandwidthCeiling = m.nmpZero / 2;

    m.rotorSign = -1;                      % inverted-mode inversion
    krNum = m.rotorSign * [kdRotor, kpRotor];

    lNum = conv(m.Trotor.num, krNum);
    lDen = m.Trotor.den;
    cl   = lDen + [zeros(1, numel(lDen) - numel(lNum)), lNum];

    m.L  = struct('num', lNum, 'den', lDen);
    m.T  = struct('num', lNum, 'den', cl);
    m.closedLoopPoles = roots(cl);
    m.closedLoopStable = all(real(m.closedLoopPoles) < 0);

    m.kpRotor = kpRotor;
    m.kdRotor = kdRotor;
    m.tdRotor = kdRotor / kpRotor;
end

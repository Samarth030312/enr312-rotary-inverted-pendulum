function m = exp002_sensitivity_model(kp, kd)
%EXP002_SENSITIVITY_MODEL  Sensitivity functions of the EXP002 rotor loop.
%
%   m = EXP002_SENSITIVITY_MODEL(kp, kd) builds the four closed-loop transfer
%   functions of Tutorial 2 for the rotor plant P(s) = 1/s^2 and the PD
%   controller C(s) = kp + kd*s.
%
%   Returned struct fields (all as [num den] coefficient vectors, so that NO
%   toolbox is required -- see matlab/ENVIRONMENT.md):
%       m.S   sensitivity                1/(1+PC)  = s^2/(s^2 + kd s + kp)
%       m.T   complementary sensitivity  PC/(1+PC) = (kd s + kp)/(s^2 + kd s + kp)
%       m.SD  load-disturbance sens.     P/(1+PC)  = 1/(s^2 + kd s + kp)
%       m.wn, m.zeta
%       m.SD_final   steady-state offset under a unit load step = 1/kp
%
%   NOTE ON SD. SD(0) = 1/kp, NOT zero. A PD controller has no integral action,
%   so a constant load leaves a PERMANENT offset. Overshoot and settling for SD
%   must be measured relative to 1/kp; measured against zero, SD never settles.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        kp (1,1) double {mustBePositive}
        kd (1,1) double {mustBeNonnegative}
    end

    den   = [1, kd, kp];          % s^2 + kd s + kp

    m.kp  = kp;
    m.kd  = kd;
    m.td  = kd / kp;
    m.den = den;

    m.S   = struct('num', [1, 0, 0], 'den', den);   % s^2 / den
    m.T   = struct('num', [kd, kp],  'den', den);   % (kd s + kp) / den
    m.SD  = struct('num', 1,         'den', den);   % 1 / den

    m.wn       = sqrt(kp);
    m.zeta     = kd / (2 * sqrt(kp));
    m.SD_final = 1 / kp;
    m.T_final  = 1;
    m.T_zero   = -kp / kd;        % numerator zero of T; increases overshoot
end

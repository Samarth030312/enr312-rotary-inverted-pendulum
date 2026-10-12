function [t, y] = exp002_step_response(tf, tEnd, n)
%EXP002_STEP_RESPONSE  Step response from pole/residue expansion. No toolbox needed.
%
%   [t, y] = EXP002_STEP_RESPONSE(tf, tEnd, n) computes the unit-step response of
%   the transfer function struct tf (fields .num, .den) with a second-order
%   denominator, using the closed-form expansion rather than a numerical solver.
%
%   Deliberately toolbox-free: Control System Toolbox is NOT assumed available.
%   See matlab/ENVIRONMENT.md.
%
%   For den = s^2 + kd s + kp with distinct poles p1, p2:
%       g(t) = 1 + (p2 e^{p1 t} - p1 e^{p2 t})/(p1 - p2)   unit-DC-gain step
%       h(t) = (e^{p1 t} - e^{p2 t})/(p1 - p2)             impulse of 1/den
%   and any numerator [a b] gives  y = (b/kp)*g + a*h.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        tf   struct
        tEnd (1,1) double {mustBePositive} = 20
        n    (1,1) double {mustBePositive} = 20001
    end

    den = tf.den;
    kd  = den(2);
    kp  = den(3);

    p = roots(den);
    p1 = p(1);
    p2 = p(2);
    if abs(p1 - p2) < 1e-12
        error('odyssix:exp002:repeatedPoles', ...
              'Repeated poles (kd^2 = 4 kp) are not handled by this expansion.');
    end

    t = linspace(0, tEnd, n).';
    e1 = exp(p1 * t);
    e2 = exp(p2 * t);
    g  = real(1 + (p2 * e1 - p1 * e2) / (p1 - p2));   % step of kp/den
    h  = real((e1 - e2) / (p1 - p2));                 % impulse of 1/den

    num = tf.num(:).';
    if isscalar(num)                 % SD = 1/den
        y = g / kp;
    elseif numel(num) == 2           % T = (kd s + kp)/den
        y = (num(2) / kp) * g + num(1) * h;
    else                             % S = s^2/den  ==>  1 - T
        y = 1 - ((kp / kp) * g + kd * h);
    end
end

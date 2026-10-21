function p = plant(exp)
%PLANT  Default plant for a tutorial: Tutorial values (NOT measured on this rig).
%   p = odyssix.sim.plant(exp)   fields wg2 Q wr2 nonlinear quant
%   The upright experiments (5, 6, 7, 8, 23) use the Tutorial 5 (inverted)
%   set, the others Tutorial 3/12.
%   Replace wg2 and Q with the rig's free-swing identification when available.
    if nargin < 1, exp = 3; end
    if any(exp == [5 6 7 8 23]), q = rotary_pendulum_params('inverted'); else, q = rotary_pendulum_params('suspended'); end
    p = struct('wg2', q.wg2, 'Q', q.Q, 'wr2', q.wr2, 'nonlinear', true, 'quant', true);
end

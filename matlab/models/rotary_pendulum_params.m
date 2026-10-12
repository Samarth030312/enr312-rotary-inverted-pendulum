function p = rotary_pendulum_params(mode)
%ROTARY_PENDULUM_PARAMS  Physical parameters of the Edukit rotary pendulum.
%
%   p = rotary_pendulum_params('inverted')    % Tutorial 5 values (default)
%   p = rotary_pendulum_params('suspended')   % Tutorial 3/12 values
%
%   The pendulum is described by two lumped constants (derivation:
%   docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md):
%       wg2 = m g lc / J      [1/s^2]   gravity term
%       wr2 = m r lc / J      [-]       arm-acceleration coupling
%       gamma = sqrt(wg2)/Q   [1/s]     viscous pivot damping
%   with J the pendulum's inertia about its pivot, lc the pivot-to-COM
%   distance and r the radius of the pivot from the motor axis.
%
%   Physics forces wr2 / wg2 = r / g. The Tutorial values imply r below;
%   the Edukit manual gives r = 0.14 m. That agreement is a consistency check
%   on the Tutorial model, not a fit.
%
%   STATUS: every number here is a Tutorial value from ANOTHER rig (OI-9).
%   None is measured on this rig. Replace with pendulum_free_swing_fit results.

    if nargin < 1, mode = 'inverted'; end
    p.g = 9.81;                         % m/s^2
    p.rManual = 0.14;                   % m, Edukit Manual Table 2
    p.wr2 = 0.803;                      % Tutorials 3, 5, 12
    switch lower(mode)
        case 'inverted'
            p.wg2 = 55.85; p.Q = 20;    % Tutorial 5
        case 'suspended'
            p.wg2 = 57.01; p.Q = 27;    % Tutorial 3/12
        otherwise
            error('rotary_pendulum_params: mode must be inverted or suspended');
    end
    p.mode  = lower(mode);
    p.gamma = sqrt(p.wg2) / p.Q;
    p.rImplied = p.wr2 * p.g / p.wg2;   % m, from wr2/wg2 = r/g
    % Tutorial 5 writes wg2 = g / (L * 0.6805); L is the equivalent length.
    p.Leq = p.g / (p.wg2 * 0.6805);     % m
    p.source = 'Tutorial values, NOT measured on this rig (OI-9)';
end

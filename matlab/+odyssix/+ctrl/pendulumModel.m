function [A, B, info] = pendulumModel(mode, plant)
%PENDULUMMODEL  Linearised rotary pendulum, arm acceleration as the input.
%
%   [A, B, info] = odyssix.ctrl.pendulumModel(mode, plant)
%   mode  'inverted' (state x = [theta thetadot alpha alphadot], upright)
%         'suspended' (state x = [theta thetadot psi psidot], hanging)
%         'rotor'     (state x = [theta thetadot], Tutorials 9/10)
%   plant struct with wg2, Q, wr2 (odyssix.sim.plant); default Tutorial 5.
%   Units: degrees, so u is the arm acceleration in deg/s^2; the model is
%   the linearisation of docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md (6):
%     hanging:  psi''   = -wg2 psi   + wr2 theta'' - gamma psi'
%     upright:  alpha'' = +wg2 alpha + wr2 theta'' - gamma alpha'   (alpha = 180 - psi)
%   info.poles: open-loop poles; info.unstable: the unstable pole sqrt(wg2) (upright).
    if nargin < 2 || isempty(plant), plant = odyssix.sim.plant(5); end
    g = sqrt(plant.wg2) / plant.Q;
    switch lower(mode)
        case 'rotor'
            A = [0 1; 0 0]; B = [0; 1];
        case 'inverted'
            A = [0 1 0 0; 0 0 0 0; 0 0 0 1; 0 0 plant.wg2 -g];
            B = [0; 1; 0; plant.wr2];
        case 'suspended'
            A = [0 1 0 0; 0 0 0 0; 0 0 0 1; 0 0 -plant.wg2 -g];
            B = [0; 1; 0; plant.wr2];
        otherwise
            error('odyssix:model', 'mode must be inverted, suspended or rotor');
    end
    info.poles = eig(A);
    info.unstable = max(real(info.poles));
    info.gamma = g;
end

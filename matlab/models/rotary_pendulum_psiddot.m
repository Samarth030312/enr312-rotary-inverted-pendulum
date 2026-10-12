function psiDD = rotary_pendulum_psiddot(psi, psiD, thD, thDD, p)
%ROTARY_PENDULUM_PSIDDOT  Nonlinear pendulum angular acceleration [rad/s^2].
%
%   psiDD = rotary_pendulum_psiddot(psi, psiD, thD, thDD, p)
%
%   psi   pendulum angle from HANGING, rad, one absolute coordinate for both
%         modes (psi = pi is upright). Positive sense: the sense in which the
%         hanging pendulum swings when the arm accelerates in +theta.
%   psiD  dpsi/dt, rad/s
%   thD   arm angular velocity, rad/s       (imposed by the stepper)
%   thDD  arm angular acceleration, rad/s^2 (imposed by the stepper)
%   p     rotary_pendulum_params
%
%   Equation (docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md, eq. 6):
%     psi'' = -wg2 sin(psi) + wr2 cos(psi) theta'' + theta'^2 sin(psi) cos(psi)
%             - gamma psi'
%
%   Assumptions: thin rigid pendulum on a frictionless-except-viscous pivot;
%   the arm motion theta(t) is imposed (a stepper that does not miss steps);
%   the arm is rigid and the pivot axis is radial. Vectorised over inputs.

    psiDD = -p.wg2 .* sin(psi) + p.wr2 .* cos(psi) .* thDD ...
            + thD.^2 .* sin(psi) .* cos(psi) - p.gamma .* psiD;
end

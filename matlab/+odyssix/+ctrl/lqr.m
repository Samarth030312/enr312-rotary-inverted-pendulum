function [K, P, poles] = lqr(A, B, Q, R)
%LQR  Continuous-time linear quadratic regulator without any toolbox.
%
%   [K, P, poles] = odyssix.ctrl.lqr(A, B, Q, R)
%   Minimises J = integral(x'Qx + u'Ru) dt for xdot = Ax + Bu with u = -Kx.
%   P solves the algebraic Riccati equation  A'P + PA - P B R^-1 B' P + Q = 0
%   (Tutorial 10, Appendix A), found from the stable invariant subspace of the
%   Hamiltonian matrix with an ordered real Schur form. K = R^-1 B' P.
%   poles = eig(A - B K).
%
%   Check against Tutorial 10: A = [0 1; 0 0], B = [0; 1], Q = I, R = 1
%   gives K = [1 1.7321]; with A = [0 1; 0 -2] it gives K = [1 0.6458].
    n = size(A, 1);
    H = [A, -B / R * B'; -Q, -A'];
    [U, T] = schur(H, 'real');
    [U, T] = ordschur(U, T, 'lhp');            % stable eigenvalues first
    if any(real(ordeig(T(1:n, 1:n))) >= 0)
        error('odyssix:lqr', 'no stabilising solution (is (A,B) stabilisable?)');
    end
    U11 = U(1:n, 1:n); U21 = U(n+1:end, 1:n);
    P = U21 / U11;
    P = (P + P') / 2;                          % remove round-off asymmetry
    K = R \ (B' * P);
    poles = eig(A - B * K);
end

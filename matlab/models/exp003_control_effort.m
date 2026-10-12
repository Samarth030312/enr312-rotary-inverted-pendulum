function ce = exp003_control_effort(u, t)
%EXP003_CONTROL_EFFORT  Tutorial 3 section 5 control-effort metrics.
%
%   ce = EXP003_CONTROL_EFFORT(u, t) returns
%       ce.maxAmplitude = max |u|
%       ce.maxPower     = max u^2
%       ce.total        = integral of |u| dt
%       ce.signed       = integral of u dt          (diagnostic only)
%
%   NOTE ON ce.total -- DOCUMENTED CONFLICT IN THE SOURCE.
%   Tutorial 3 section 5 writes this metric as the SIGNED integral of u, but its
%   results table gives 11.0 for Design 1. The signed integral is exactly ZERO
%   here, because CE(s) has zero DC gain. Testing all three candidate readings
%   against the tutorial's own value:
%       integral u   dt = 0.0000     (not 11.0)
%       integral u^2 dt = 1.17e+03   (not 11.0)
%       integral |u| dt = 10.88      MATCHES 11.0
%   The absolute value is therefore taken. ce.signed is returned so the zero can
%   be seen rather than taken on trust.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        u (:,1) double
        t (:,1) double
    end

    [ce.maxPower, i] = max(u .^ 2);
    ce.maxAmplitude  = abs(u(i));
    ce.total         = trapz(t, abs(u));
    ce.signed        = trapz(t, u);
end

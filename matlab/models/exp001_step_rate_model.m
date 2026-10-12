function s = exp001_step_rate_model(p, fCmdHz)
%EXP001_STEP_RATE_MODEL  Step-rate quantisation from the integer timer reload.
%
%   s = EXP001_STEP_RATE_MODEL(p, fCmdHz) evaluates equations (2)-(3) of
%   experiments/EXP001/FIRST_PRINCIPLES.md.
%
%   Because the auto-reload register holds an integer, the achievable step rate
%   is quantised. The resulting error is a RATE error, not a POSITION error --
%   the position model counts pulses issued, not their spacing.
%
%   Outputs (struct s):
%     fCmd      commanded rate, Hz
%     arr       auto-reload value
%     fActual   achieved rate, Hz
%     errPct    100*(fActual - fCmd)/fCmd
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        p      struct
        fCmdHz double {mustBePositive}
    end

    divisor    = max(round(p.step.tickHz ./ fCmdHz), 1);
    s.fCmd     = fCmdHz;
    s.arr      = divisor - 1;
    s.fActual  = p.step.tickHz ./ divisor;
    s.errPct   = 100 * (s.fActual - fCmdHz) ./ fCmdHz;
end

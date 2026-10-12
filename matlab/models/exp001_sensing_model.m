function m = exp001_sensing_model(p)
%EXP001_SENSING_MODEL  Analytic sensing/actuation chain model for EXP001.
%
%   m = EXP001_SENSING_MODEL(p) evaluates equations (5)-(14) of
%   experiments/EXP001/FIRST_PRINCIPLES.md for parameter set p.
%
%   This is a MEASUREMENT-CHAIN model, not a plant model. EXP001 has no plant
%   model by design: no inertia, no friction, no dynamics. See
%   FIRST_PRINCIPLES.md section 6.
%
%   Inputs:
%     p  parameter struct from odyssix.rigParams()
%
%   Outputs (struct m):
%     q                 rad per encoder count                      (eq. 6)
%     sigmaTheta        angle quantisation std, rad                (eq. 11)
%     velGranularity    velocity estimate granularity, rad/s       (eq. 13)
%     sigmaOmega        backward-difference velocity std, rad/s    (eq. 14)
%     aliasLimitRevS    counter-wrap aliasing threshold, rev/s     (eq. 10)
%     radPerMicrostep   rad per commanded microstep                (eq. 1)
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    arguments
        p struct
    end

    m.parameterSetId = p.parameterSetId;

    % Equation (6): angular resolution.
    m.q = p.encoder.radPerCount;

    % Equation (11): quantisation residual is uniform on [-q/2, q/2],
    % hence zero-mean with variance q^2/12.
    m.sigmaTheta = m.q / sqrt(12);

    % Equation (13): the backward difference can only take integer multiples
    % of one count per sample.
    m.velGranularity = m.q / p.timing.Ts;

    % Equation (14): differencing two independent quantisation residuals
    % amplifies the std by sqrt(2)/Ts.
    m.sigmaOmega = m.sigmaTheta * sqrt(2) / p.timing.Ts;

    % Equation (10): the modular-difference decoder is valid while the true
    % motion per sample stays below half a counter period.
    halfModulus      = 2^(p.encoder.counterBits - 1);
    m.aliasLimitRevS = halfModulus / p.encoder.countsPerRev / p.timing.Ts;

    % Equation (1): nominal command increment.
    m.radPerMicrostep = p.rotor.radPerMicrostep;

    % Noise gain of a first-order low-pass applied to the derivative:
    %   y[k] = y[k-1] + a*(u[k] - y[k-1]),  a = 1 - exp(-2*pi*fc*Ts)
    % has steady-state noise gain sqrt(a/(2-a)).
    m.derivFilterNoiseGain = @(fc) localFilterGain(fc, p.timing.Ts);
    m.sigmaOmegaFiltered   = @(fc) m.sigmaOmega * localFilterGain(fc, p.timing.Ts);
end

function g = localFilterGain(fc, Ts)
    a = 1 - exp(-2*pi*fc*Ts);
    g = sqrt(a ./ (2 - a));
end

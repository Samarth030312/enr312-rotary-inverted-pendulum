function p = rigParams()
%RIGPARAMS  Parameter set PS-EDUKIT01-v1 for the ENR312 rotary inverted pendulum.
%
%   These values MIRROR shared/parameters/edukit01_rig.yaml and
%   firmware/enr312/inc/enr312_rig_config.h. All three must agree; the
%   agreement is checked by validation/exp001_check_parameter_consistency.m.
%
%   PROVENANCE. Nothing here is MEASURED. Every value is a prediction until
%   EXP001 and EXP002 execute on hardware. Do not cite these as results.
%
%   See also EXP001_SENSING_MODEL, EXP001_RUN_ANALYSIS.

    p.parameterSetId = 'PS-EDUKIT01-v1';
    p.status         = 'UNVERIFIED_AGAINST_HARDWARE';

    % --- Sensing chain: incremental quadrature encoder --------------------
    p.encoder.ppr            = 600;                      % [DATASHEET]
    p.encoder.decodeX        = 4;                        % [REF] firmware choice
    p.encoder.countsPerRev   = p.encoder.ppr * p.encoder.decodeX;   % 2400
    p.encoder.radPerCount    = 2*pi / p.encoder.countsPerRev;
    p.encoder.degPerCount    = 360  / p.encoder.countsPerRev;
    p.encoder.counterBits    = 16;                       % [REF] TIM3 is 16-bit
    p.encoder.polarity       = -1;   % MEASURED 2026-10-12, EXP001 P2b (rig_20261012-160027.log)

    % --- Actuation chain: NEMA-17 stepper via L6474 -----------------------
    p.rotor.fullStepsPerRev  = 200;                      % [DATASHEET]
    p.rotor.microstepDiv     = 16;                       % [REF] STEP_SEL_1_16
    p.rotor.microstepsPerRev = p.rotor.fullStepsPerRev * p.rotor.microstepDiv; % 3200
    p.rotor.radPerMicrostep  = 2*pi / p.rotor.microstepsPerRev;
    p.rotor.degPerMicrostep  = 360  / p.rotor.microstepsPerRev;
    p.rotor.polarity         = +1;   % MEASURED 2026-10-12, EXP001 P1 (protractor + green line)

    % --- Step-clock generation --------------------------------------------
    p.step.sysclkHz          = 84e6;                     % [LOCAL FIRMWARE]
    p.step.prescaler         = 1024;                     % [REF]
    p.step.tickHz            = p.step.sysclkHz / p.step.prescaler;  % 82031.25
    p.step.maxRateHzExp001   = 1000;                     % EXP001 self-imposed cap

    % --- Timing ------------------------------------------------------------
    p.timing.Ts              = 0.002;                    % [COURSE] s
    p.timing.fs              = 1 / p.timing.Ts;          % 500 Hz
    p.timing.nyquistHz       = p.timing.fs / 2;

    % --- Safety limits -----------------------------------------------------
    p.limits.rotorDeg        = 240;                      % [REF]
    p.limits.pendulumDeg     = 120;                      % [REF]

    % --- Mechanical: DELIBERATELY ABSENT -----------------------------------
    % Masses, lengths, inertias and friction are NOT known and are NOT needed
    % by EXP001. They are required from EXP004. Populating them with reference
    % values would be fabrication.
    p.mechanical.status      = 'NOT_AVAILABLE';
    p.mechanical.requiredBy  = {'EXP004','EXP005'};
end

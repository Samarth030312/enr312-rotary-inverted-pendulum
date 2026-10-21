function p = rigParams()
%RIGPARAMS  Parameter set PS-EDUKIT01-v1 for the ENR312 rotary inverted pendulum.
%
%   These values MIRROR shared/parameters/edukit01_rig.yaml and
%   firmware/enr312/inc/enr312_rig_config.h. All three must agree; the
%   agreement is checked by validation/exp001_check_parameter_consistency.m.
%
%   PROVENANCE. Each value says where it comes from: [DATASHEET], [REF],
%   [COURSE], [LOCAL FIRMWARE], or MEASURED with the date and the evidence.
%
%   See also EXP001_SENSING_MODEL, EXP001_RUN_ANALYSIS.

    p.parameterSetId = 'PS-EDUKIT01-v1';
    p.status         = 'PARTLY_MEASURED';      % polarities, scales, pendulum dynamics: see each entry

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

    % --- Pendulum dynamics: IDENTIFIED from rig runs of 2026-10-21 ----------
    % matlab/identification/identify_pendulum_20261021.m, table
    % results/tables/PEND_identification_20261021.csv. Not from a dedicated
    % free swing (still to be recorded); from a T10 stretch with the arm still
    % and from the steady 92 deg swings of the pendulum-target run R05.
    p.pendulum.wg2Measured   = [47.6 49.5];   % rad^2/s^2: free decay 5.7 deg; 92 deg swings (elliptic period)
    p.pendulum.wg2FreeSwing  = [48.4 48.6];   % rad^2/s^2: dedicated free swings EXP001 R03, R06 (peak period,
                                              % 2026-10-21 19:19 UTC); 48 +- 1 over all methods
    p.pendulum.wg2           = 48.5;          % the value to give the firmware ($wg2); swing-up caught 3.88 s with it (R08)
    p.pendulum.coulomb       = 0.40;          % rad/s^2, dry pivot friction (free swings 0.33/0.40, T10 0.48)
    p.pendulum.QLargeSwing   = [57 63];       % viscous Q that closes the energy balance at 92 deg
    p.pendulum.source        = 'MEASURED 2026-10-21 (free swings EXP001 R03/R06; EXP010 R01; EXP024 R05)';
    p.pendulum.tutorialWg2   = 57.01;         % [COURSE] from the Tutorial geometry; what the rig ran with
    % Arm coupling. For a rod pendulum on an arm of length r (Tutorial 12, both
    % hanging and inverted forms) wr2 / wg2 = r / g exactly, whatever the rod.
    p.rotor.armLength        = 0.14;          % m [DATASHEET] STEVAL-EDUKIT01 manual, Table 2
    p.pendulum.wr2           = p.rotor.armLength * p.pendulum.wg2 / 9.81;   % 0.692 (Tutorial: 0.803)
    p.pendulum.rodEquivalent = 3 * 9.81 / (2 * p.pendulum.wg2);             % m, uniform rod with this wg2: 0.30

    % --- Masses, lengths, inertias: NOT MEASURED ------------------------------
    % Only their combinations wg2 and wr2 enter the models; wr2 follows from wg2
    % and the documented arm length (above).
    p.mechanical.status      = 'NOT_MEASURED';
end

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

    % --- Pendulum dynamics: MEASURED on this rig, 2026-10-21 --------------------
    % Six dedicated free swings (motor off), fitted by pendulum_free_swing_fit and
    % timed by their period: results/tables/PEND_free_swings.csv. Earlier
    % estimates from stretches of other runs agree:
    % results/tables/PEND_identification_20261021.csv.
    p.pendulum.wg2Measured   = [47.6 49.5];   % rad^2/s^2: free decay 5.7 deg; 92 deg swings (elliptic period)
    p.pendulum.wg2FreeSwing  = [47.1 48.4];   % rad^2/s^2: six free swings, EXP001 R03, R06-R10 (fit and period)
    p.pendulum.wg2           = 48.0;          % +-0.5: the value to give the firmware ($wg2). The swing-ups of
                                              % 2026-10-21 ran with 48.5 (within 1 %) and caught 4 of 4
    p.pendulum.coulomb       = 0.37;          % rad/s^2, dry pivot friction (10 deg free swings 0.35-0.40; T10 0.48;
                                              % larger swings fit a dry + viscous mix: the split is uncertain)
    p.rotor.tiltDeg          = 0.57;          % deg, MEASURED 2026-10-24: the motor axis leans; the steady lean while
                                              % balancing falls 0.008 deg per deg of arm in every upright run of the
                                              % day. Reproduces the arm's slow creep and the smaller step overshoot.
                                              % A fault to remove (level the base), so the app simulates a level rig.
    p.pendulum.coulombUpright = 0.12;         % rad/s^2, the dry friction that reproduces BALANCING (small, slow
                                              % motion): T6/T7/T8 pendulum rms on 2026-10-24 match 0.05-0.2, the
                                              % T8 load peak < 0.1; 0.37 gives 2x the hunting seen on the rig.
                                              % (10-21 afternoon, before the mechanics were gone over, matched 0.37.)
                                              % A bearing at micro-motion is not a constant-torque Coulomb contact.
                                              % results/reports/2026-10-24_rig_session.md, section 4
    p.pendulum.QLargeSwing   = [57 63];       % viscous Q that closes the energy balance at 92 deg
    p.pendulum.source        = 'MEASURED 2026-10-21 (six free swings, EXP001 R03, R06-R10)';
    p.pendulum.tutorialWg2   = 57.01;         % [COURSE] from the Tutorial geometry; what the rig ran with
    % Arm coupling. For a rod pendulum on an arm of length r (Tutorial 12, both
    % hanging and inverted forms) wr2 / wg2 = r / g exactly, whatever the rod.
    p.rotor.armLength        = 0.14;          % m [DATASHEET] STEVAL-EDUKIT01 manual, Table 2
    p.pendulum.wr2           = p.rotor.armLength * p.pendulum.wg2 / 9.81;   % 0.685 (Tutorial: 0.803)
    p.pendulum.rodEquivalent = 3 * 9.81 / (2 * p.pendulum.wg2);             % m, uniform rod with this wg2: 0.31
    p.pendulum.rodLength     = 0.26;          % m, MEASURED 2026-10-22 (ruler). A uniform 0.26 m rod pivoted at its
                                              % end would have wg2 56.6. The rig carries a small paper holder clipped
                                              % at the tip: a tip mass of 0.19-0.47 of the rod's explains 48.0.
    p.pendulum.tipAccessory  = 'paper holder clipped at the rod end (mass not measured)';

    % --- Masses, lengths, inertias: NOT MEASURED ------------------------------
    % Only their combinations wg2 and wr2 enter the models; wr2 follows from wg2
    % and the documented arm length (above).
    p.mechanical.status      = 'NOT_MEASURED';
end

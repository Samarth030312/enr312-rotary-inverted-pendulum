function results = exp001_validate_sensing_model()
%EXP001_VALIDATE_SENSING_MODEL  Self-checking validation of the EXP001 model.
%
%   results = EXP001_VALIDATE_SENSING_MODEL() checks the analytic sensing model
%   against (a) hand-derived expected values from FIRST_PRINCIPLES.md and
%   (b) an independent Monte-Carlo simulation.
%
%   A model that is not checked against an expected value is not validated. Every
%   check below has a stated tolerance and fails loudly.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.
%   When executed, record the MATLAB version, release, date and repository
%   revision in experiments/EXP001/MEASUREMENTS.md.

    p = odyssix.rigParams();
    m = exp001_sensing_model(p);

    results = struct('name', {}, 'expected', {}, 'actual', {}, ...
                     'tol', {}, 'pass', {});

    results = addCheck(results, 'counts_per_rev',      2400,               p.encoder.countsPerRev,  0);
    results = addCheck(results, 'deg_per_count',       0.15,               p.encoder.degPerCount,   1e-12);
    results = addCheck(results, 'rad_per_count',       2.617993877991494e-3, m.q,                   1e-15);
    results = addCheck(results, 'sigma_theta_rad',     7.557497350975908e-4, m.sigmaTheta,          1e-12);
    results = addCheck(results, 'vel_granularity_rads',1.308996938995747,  m.velGranularity,        1e-9);
    results = addCheck(results, 'sigma_omega_rads',    0.5343957625674435, m.sigmaOmega,            1e-9);
    results = addCheck(results, 'alias_limit_rev_s',   6826.666666666667,  m.aliasLimitRevS,        1e-6);
    results = addCheck(results, 'microsteps_per_rev',  3200,               p.rotor.microstepsPerRev, 0);
    results = addCheck(results, 'rad_per_microstep',   1.963495408493621e-3, m.radPerMicrostep,     1e-15);

    % Cross-check against the UCLA reference constants. Deriving these from part
    % geometry and landing exactly on the reference's numbers is independent
    % evidence that the 600-PPR-x4 and 200-x-16 assumptions are the right ones.
    results = addCheck(results, 'ref_encoder_angle_scale', 6.666667, ...
                       1/p.encoder.degPerCount, 1e-6);
    results = addCheck(results, 'ref_stepper_steps_per_deg', 8.888889, ...
                       1/p.rotor.degPerMicrostep, 1e-6);

    % Step-rate quantisation, equations (2)-(3).
    s = exp001_step_rate_model(p, [200 500 1000 2000 10000]);
    results = addCheck(results, 'arr_at_1000Hz',   81,        s.arr(3),     0);
    results = addCheck(results, 'factual_1000Hz',  1000.3811, s.fActual(3), 1e-3);
    results = addCheck(results, 'arr_at_10kHz',    7,         s.arr(5),     0);
    results = addCheck(results, 'errpct_10kHz',    2.5391,    s.errPct(5),  1e-3);

    % Independent Monte-Carlo confirmation of equations (11) and (14).
    rng(20260819);
    n      = 2e6;
    theta  = cumsum(randn(n,1) * 50 * m.q);
    thetaQ = round(theta / m.q) * m.q;
    resid  = thetaQ - theta;
    omegaErr = diff(thetaQ)/p.timing.Ts - diff(theta)/p.timing.Ts;

    results = addCheck(results, 'mc_sigma_theta', m.sigmaTheta, std(resid), ...
                       0.02*m.sigmaTheta);
    results = addCheck(results, 'mc_sigma_omega', m.sigmaOmega, std(omegaErr), ...
                       0.02*m.sigmaOmega);
    results = addCheck(results, 'mc_mean_resid',  0, mean(resid), 1e-5*m.q);

    % Derivative low-pass: the reference project's 10 Hz corner.
    results = addCheck(results, 'sigma_omega_10Hz_filtered', 0.1358, ...
                       m.sigmaOmegaFiltered(10), 1e-3);

    nPass = sum([results.pass]);
    nTot  = numel(results);
    fprintf('\nEXP001 sensing-model validation (%s)\n', p.parameterSetId);
    fprintf('%s\n', repmat('-', 1, 72));
    for k = 1:nTot
        fprintf('  %-28s expected %-16.9g actual %-16.9g  %s\n', ...
            results(k).name, results(k).expected, results(k).actual, ...
            ternary(results(k).pass, 'PASS', 'FAIL'));
    end
    fprintf('%s\n', repmat('-', 1, 72));
    fprintf('  %d / %d checks passed\n\n', nPass, nTot);

    if nPass ~= nTot
        error('odyssix:exp001:validationFailed', ...
              'EXP001 sensing-model validation failed (%d of %d).', ...
              nTot - nPass, nTot);
    end
end

function r = addCheck(r, name, expected, actual, tol)
    r(end+1) = struct('name', name, 'expected', expected, 'actual', actual, ...
                      'tol', tol, 'pass', abs(actual - expected) <= tol);
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end

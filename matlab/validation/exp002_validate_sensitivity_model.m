function results = exp002_validate_sensitivity_model()
%EXP002_VALIDATE_SENSITIVITY_MODEL  Self-checking validation for EXP002.
%
%   Checks the sensitivity model against hand-derived values from
%   experiments/EXP002/FIRST_PRINCIPLES.md section 7, and against the results of
%   the independent Python numerical check.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.
%   When executed, record MATLAB version, release, date and repository revision
%   in experiments/EXP002/MEASUREMENTS.md.

    results = struct('name', {}, 'expected', {}, 'actual', {}, 'tol', {}, 'pass', {});

    % ---- Tutorial 1 design -------------------------------------------------
    m = exp002_sensitivity_model(5.0, 2.5);
    results = add(results, 'wn',        2.2360680, m.wn,       1e-6);
    results = add(results, 'zeta',      0.5590170, m.zeta,     1e-6);
    results = add(results, 'SD_final',  0.2000000, m.SD_final, 1e-9);
    results = add(results, 'T_zero',   -2.0000000, m.T_zero,   1e-9);

    [t, yT]  = exp002_step_response(m.T,  30, 30001);
    [~, ySD] = exp002_step_response(m.SD, 30, 30001);

    [pkT, tpT, osT, stT] = metrics(t, yT, 1.0);
    results = add(results, 'T_peak',        1.2676, pkT, 2e-3);
    results = add(results, 'T_peak_time',   1.055,  tpT, 5e-3);
    results = add(results, 'T_overshoot',  26.76,   osT, 0.05);
    results = add(results, 'T_settling',    3.239,  stT, 5e-3);

    [pkD, tpD, osD, stD] = metrics(t, ySD, m.SD_final);
    results = add(results, 'SD_peak',       0.2241, pkD, 2e-4);
    results = add(results, 'SD_peak_time',  1.694,  tpD, 5e-3);
    results = add(results, 'SD_overshoot', 12.03,   osD, 0.05);
    results = add(results, 'SD_settling',   2.617,  stD, 5e-3);

    % Fundamental identity S + T = 1 must hold at every sample.
    [~, yS] = exp002_step_response(m.S, 30, 30001);
    results = add(results, 'S_plus_T_equals_1', 0, max(abs(yS + yT - 1)), 1e-9);

    % ---- EXP002 selected design -------------------------------------------
    m2 = exp002_sensitivity_model(6.55, 4.0);
    results = add(results, 'sel_zeta',     0.7814616, m2.zeta,     1e-6);
    results = add(results, 'sel_SD_final', 0.1526718, m2.SD_final, 1e-7);

    nPass = sum([results.pass]);
    fprintf('\nEXP002 sensitivity-model validation\n');
    fprintf('%s\n', repmat('-', 1, 70));
    for k = 1:numel(results)
        if results(k).pass, v = 'PASS'; else, v = 'FAIL'; end
        fprintf('  %-22s expected %-14.7g actual %-14.7g %s\n', ...
                results(k).name, results(k).expected, results(k).actual, v);
    end
    fprintf('%s\n  %d / %d checks passed\n\n', repmat('-', 1, 70), nPass, numel(results));

    if nPass ~= numel(results)
        error('odyssix:exp002:validationFailed', ...
              'EXP002 validation failed (%d of %d).', numel(results) - nPass, numel(results));
    end
end

function [peak, tpk, os, settling] = metrics(t, y, yf)
    [peak, i] = max(y);
    tpk = t(i);
    os  = 100 * (peak - yf) / abs(yf);
    outside = find(abs(y - yf) > 0.02 * abs(yf), 1, 'last');
    if isempty(outside), settling = 0; else, settling = t(outside); end
end

function r = add(r, name, expected, actual, tol)
    r(end+1) = struct('name', name, 'expected', expected, 'actual', actual, ...
                      'tol', tol, 'pass', abs(actual - expected) <= tol);
end

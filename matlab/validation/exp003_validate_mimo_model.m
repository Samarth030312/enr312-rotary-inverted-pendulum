function results = exp003_validate_mimo_model()
%EXP003_VALIDATE_MIMO_MODEL  Self-checking validation for EXP003.
%
%   Validates against Tutorial 3's OWN PUBLISHED Design 1 values, which is the
%   strongest check available: reproducing them exercises both plants, both
%   controllers, the loop algebra and the control-effort definitions at once.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    results = struct('name', {}, 'expected', {}, 'actual', {}, 'tol', {}, 'pass', {});

    m = exp003_mimo_model(6.0, 4.8, 100);

    % Structure
    results = add(results, 'kd_pend',      5.0,       m.kdPend,     1e-12);
    results = add(results, 'gamma',        0.2796478, m.gamma,      1e-6);
    results = add(results, 'inner_b',      4.29465,   m.innerPoly(2), 1e-4);
    results = add(results, 'inner_c',      65.04,     m.innerPoly(3), 1e-4);
    results = add(results, 'inner_zeta',   0.26625,   m.innerZeta,  1e-4);
    results = add(results, 'open_zeta',    0.0185185, m.openZeta,   1e-6);

    % Design 1 response vs Tutorial 3's published table
    t = linspace(0, 40, 40001).';
    y = exp003_step(m.Ttracking, t);
    u = exp003_step(m.CE, t);
    ce = exp003_control_effort(u, t);

    os = 100 * (max(y) - 1);
    k  = find(abs(y - 1) > 0.02, 1, 'last');
    if isempty(k), st = 0; else, st = t(k); end

    results = add(results, 'settling_s',    2.1,     st,               0.42);   % +/-20 %
    results = add(results, 'overshoot_pct', 31.4,    os,               6.28);
    results = add(results, 'ce_max',        477,     ce.maxAmplitude,  95.4);
    results = add(results, 'ce_max_power',  2.27e5,  ce.maxPower,      4.54e4);
    results = add(results, 'ce_total',      11.0,    ce.total,         2.2);
    results = add(results, 'ce_signed_is_zero', 0,   ce.signed,        0.1);

    % Self-consistency of the tutorial's own two numbers.
    results = add(results, 'ce_power_eq_max_squared', ce.maxAmplitude^2, ...
                  ce.maxPower, 1e-6 * ce.maxPower);

    nPass = sum([results.pass]);
    fprintf('\nEXP003 MIMO-model validation (Tutorial 3 Design 1)\n');
    fprintf('%s\n', repmat('-', 1, 74));
    for k2 = 1:numel(results)
        if results(k2).pass, v = 'PASS'; else, v = 'FAIL'; end
        fprintf('  %-26s expected %-13.6g actual %-13.6g %s\n', ...
                results(k2).name, results(k2).expected, results(k2).actual, v);
    end
    fprintf('%s\n  %d / %d checks passed\n\n', repmat('-', 1, 74), nPass, numel(results));

    if nPass ~= numel(results)
        error('odyssix:exp003:validationFailed', 'EXP003 validation failed (%d of %d).', ...
              numel(results) - nPass, numel(results));
    end
end

function y = exp003_step(tf, t)
%EXP003_STEP  Step response by partial fractions. No toolbox required.
    p = roots(tf.den);
    if numel(unique(round(p, 9))) ~= numel(p)
        error('odyssix:exp003:repeatedPoles', 'Repeated poles are not handled.');
    end
    % Y(s) = num/(den*s): residue at 0 plus one per pole.
    y = polyval(tf.num, 0) / polyval(tf.den, 0) * ones(size(t));
    for k = 1:numel(p)
        dpoly = polyder(tf.den);
        res = polyval(tf.num, p(k)) / (p(k) * polyval(dpoly, p(k)));
        y = y + real(res * exp(p(k) * t));
    end
end

function r = add(r, name, expected, actual, tol)
    r(end+1) = struct('name', name, 'expected', expected, 'actual', actual, ...
                      'tol', tol, 'pass', abs(actual - expected) <= tol);
end

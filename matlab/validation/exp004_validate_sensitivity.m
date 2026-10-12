function results = exp004_validate_sensitivity()
%EXP004_VALIDATE_SENSITIVITY  Self-checking validation for EXP004.
%
%   Validates against Tutorial 4's published M_S = 2.7 dB (Figure 7) for the
%   reference design, and checks the Nyquist identity M_S = 1/min|1+L|, which is
%   algebraic and must therefore hold to numerical precision.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    results = struct('name', {}, 'expected', {}, 'actual', {}, 'tol', {}, 'pass', {});

    s = exp004_sensitivity_analysis(6.0, 4.8);
    results = add(results, 'Ms_dB_reference',   2.7,      s.MsdB,  0.15);
    results = add(results, 'Ms_linear',         1.3794,   s.Ms,    0.01);
    results = add(results, 'w_SC_rad_s',        3.635,    s.wSC,   0.05);
    results = add(results, 'nyquist_identity',  0,        s.nyquistIdentityError, 1e-9);
    results = add(results, 'nyquist_min_dist',  0.724935, s.nyquistMinDist, 1e-4);

    a = exp004_sensitivity_analysis(1.20, 1.50);       % Design A, Step 1
    results = add(results, 'designA_Ms_dB',     0.995,    a.MsdB,  0.05);
    results = add(results, 'designA_under_1dB', 1,        double(a.MsdB < 1.0), 0);

    b = exp004_sensitivity_analysis(0.25, 4.80);       % Design B, Step 2
    results = add(results, 'designB_Ms_dB',     1.857,    b.MsdB,  0.05);
    results = add(results, 'designB_under_3dB', 1,        double(b.MsdB < 3.0), 0);

    nPass = sum([results.pass]);
    fprintf('\nEXP004 sensitivity validation (Tutorial 4)\n');
    fprintf('%s\n', repmat('-', 1, 72));
    for k = 1:numel(results)
        if results(k).pass, v = 'PASS'; else, v = 'FAIL'; end
        fprintf('  %-24s expected %-13.6g actual %-13.6g %s\n', ...
                results(k).name, results(k).expected, results(k).actual, v);
    end
    fprintf('%s\n  %d / %d checks passed\n\n', repmat('-', 1, 72), nPass, numel(results));

    if nPass ~= numel(results)
        error('odyssix:exp004:validationFailed', 'EXP004 validation failed (%d of %d).', ...
              numel(results) - nPass, numel(results));
    end
end

function r = add(r, name, expected, actual, tol)
    r(end+1) = struct('name', name, 'expected', expected, 'actual', actual, ...
                      'tol', tol, 'pass', abs(actual - expected) <= tol);
end

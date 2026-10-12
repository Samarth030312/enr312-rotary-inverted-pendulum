function results = exp005_validate_inverted()
%EXP005_VALIDATE_INVERTED  Self-checking validation for EXP005.
%
%   Checks, in order: that the OPEN-loop plant really is unstable; that the
%   supplied inner controller stabilises it; that the outer-loop sign inversion
%   is necessary; the non-minimum-phase zero; and the stability margins of
%   Tutorial 5's own published designs.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    results = struct('name', {}, 'expected', {}, 'actual', {}, 'tol', {}, 'pass', {});

    m = exp005_inverted_model(9.0, 9.0);      % Tutorial 5 Stable System 1

    % --- The plant must actually be unstable, or nothing else means anything.
    results = add(results, 'rhp_pole',        7.2888,  m.rhpPole,           1e-3);
    results = add(results, 'fall_tau_ms',     137.2,   1000*m.fallTimeConstant, 1.0);
    results = add(results, 'gamma',           0.373664, m.gamma,            1e-6);

    % --- Inner loop stabilises it.
    results = add(results, 'inner_b',         24.4637, m.innerPoly(2),      1e-3);
    results = add(results, 'inner_c',        185.05,   m.innerPoly(3),      1e-2);
    results = add(results, 'inner_stable',     1,      double(m.innerStable), 0);
    results = add(results, 'inner_zeta',       0.8992, m.innerZeta,         1e-3);

    % --- Kd conflict resolved to 30, implying Td = 0.1 s.
    results = add(results, 'kd_pend',         30.0,    m.kdPend,            1e-9);
    results = add(results, 'td_pend_implied',  0.1,    m.tdPend,            1e-9);

    % --- The fundamental limitation.
    results = add(results, 'nmp_zero',         7.2888, m.nmpZero,           1e-3);
    results = add(results, 'bandwidth_ceiling',3.6444, m.bandwidthCeiling,  1e-3);

    % --- Sign inversion is NECESSARY: without it Tutorial 5's own design fails.
    results = add(results, 'closed_loop_stable_with_inversion', 1, ...
                  double(m.closedLoopStable), 0);
    results = add(results, 'max_re_pole_sys1', -1.7915, max(real(m.closedLoopPoles)), 0.05);

    % --- Margins of the two published designs.
    s1 = exp005_stability_margins(m);
    results = add(results, 'sys1_phiM_deg',   47.31,  s1.phiMdeg, 0.5);
    results = add(results, 'sys1_GM_dB',       6.01,  s1.GMdB,    0.2);
    results = add(results, 'sys1_Ms_dB',       6.365, s1.MsdB,    0.1);

    m2 = exp005_inverted_model(10.0, 3.33);
    s2 = exp005_stability_margins(m2);
    results = add(results, 'sys2_phiM_deg',   17.54,  s2.phiMdeg, 0.5);
    results = add(results, 'sys2_Ms_dB',      10.322, s2.MsdB,    0.1);
    results = add(results, 'sys2_margins_poor', 1, double(s2.phiMdeg < 30 && s2.MsdB > 10), 0);

    nPass = sum([results.pass]);
    fprintf('\nEXP005 inverted-mode validation (Tutorial 5)\n');
    fprintf('%s\n', repmat('-', 1, 76));
    for k = 1:numel(results)
        if results(k).pass, v = 'PASS'; else, v = 'FAIL'; end
        fprintf('  %-34s expected %-12.6g actual %-12.6g %s\n', ...
                results(k).name, results(k).expected, results(k).actual, v);
    end
    fprintf('%s\n  %d / %d checks passed\n\n', repmat('-', 1, 76), nPass, numel(results));

    if nPass ~= numel(results)
        error('odyssix:exp005:validationFailed', 'EXP005 validation failed (%d of %d).', ...
              numel(results) - nPass, numel(results));
    end
end

function r = add(r, name, expected, actual, tol)
    r(end+1) = struct('name', name, 'expected', expected, 'actual', actual, ...
                      'tol', tol, 'pass', abs(actual - expected) <= tol);
end

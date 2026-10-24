function K = loadRecords(id, D)
%LOADRECORDS  The 500 Hz records of a run, placed on the run's own time axis.
%
%   K = odyssix.data.loadRecords('EXP024_20261021-210043_swing-up_R15')
%   K = odyssix.data.loadRecords(id, D)        D from odyssix.data.loadRun(id)
%
%   K is a struct array, one per record (<run id>_500Hz_<n>.csv), with
%     id, reason, D     D: t (s, run time), rotor, psi, alpha, u, phase
%     t0                run time of the trigger (s)
%     fit               rms mismatch of the placement (deg); under ~0.5 is a clean match
%   The record does not carry the run's clock, and its arrival time in the run
%   is late by the 0.5 s after the trigger plus the transfer. It is placed where
%   its commanded arm angle and its encoder angle match the run's 50 Hz stream:
%   the arm angle is exact (microsteps), so the match is unambiguous whenever
%   the arm moved during the record.
    if nargin < 2, D = odyssix.data.loadRun(id); end
    root = odyssix.repoRoot();
    dirs = {fullfile(root, 'data', 'raw', id(1:6)), fullfile(root, 'matlab', 'data', 'synthetic', id(1:6))};
    K = struct('id', {}, 'reason', {}, 'D', {}, 't0', {}, 'fit', {});
    for d = dirs
        F = dir(fullfile(d{1}, [id '_500Hz_*.csv']));
        for f = F'
            R = readtable(fullfile(f.folder, f.name));
            [t0, fit] = place(D, R);
            E = table(R.t_s + t0, R.rotor_deg, R.psi_deg, R.alpha_deg, R.u, R.phase, ...
                'VariableNames', {'t', 'rotor', 'psi', 'alpha', 'u', 'phase'});
            rec = erase(f.name, '.csv'); reason = '';
            j = fullfile(root, 'data', 'metadata', id(1:6), [rec '.json']);
            if isfile(j), m = jsondecode(fileread(j)); reason = m.reason; end
            K(end+1) = struct('id', rec, 'reason', reason, 'D', E, 't0', t0, 'fit', fit); %#ok<AGROW>
        end
    end
    if ~isempty(K), [~, o] = sort([K.t0]); K = K(o); end
end

function [t0, fit] = place(D, R)
% the offset t0 (s) that best lays the record (t_s from its trigger) on the run
    k = 1:5:height(R);                                % 100 Hz is plenty for the match
    tr = R.t_s(k); rr = R.rotor_deg(k); pr = R.psi_deg(k);
    cost = @(t0) sqrt(mean((interp1(D.t, D.rotor, tr + t0, 'linear', NaN) - rr).^2 + ...
                           (interp1(D.t, D.psi,   tr + t0, 'linear', NaN) - pr).^2, 'omitnan') ...
                      + 1e3 * mean(isnan(interp1(D.t, D.rotor, tr + t0))));   % penalise falling off the run
    c = arrayfun(cost, (0:0.02:D.t(end))'); [~, i] = min(c);
    fine = (i - 2) * 0.02:0.002:i * 0.02;
    c2 = arrayfun(cost, fine); [fit, j] = min(c2); t0 = fine(j);
end

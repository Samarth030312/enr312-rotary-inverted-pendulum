function [D, M] = loadRun(id)
%LOADRUN  A recorded run and its metadata, by run id (or CSV path).
%
%   [D, M] = odyssix.data.loadRun('EXP006_20261021-191502_t6-ref_R03')
%   D: table (t from 0, rotor, psi, alpha, u, ref, phase, ...); M: metadata
%   struct (from the JSON sidecar; empty struct for legacy runs).
    root = odyssix.repoRoot();
    T = odyssix.data.listRuns();
    k = find(T.run_id == string(id) | T.csv == string(id), 1);
    if isempty(k), error('odyssix:data', 'no run %s', id); end
    csv = fullfile(root, T.csv(k));
    D = readtable(csv);
    % legacy files name the time column t; the 2026-10-12 ones too
    if ~ismember('t', D.Properties.VariableNames) && ismember('t_s', D.Properties.VariableNames)
        D = renamevars(D, 't_s', 't');
    end
    D.t = D.t - D.t(1);
    if ~ismember('alpha', D.Properties.VariableNames) && ismember('psi', D.Properties.VariableNames)
        D.alpha = mod(180 - D.psi + 180, 360) - 180;
    end
    M = struct();
    [p, n] = fileparts(char(T.csv(k)));
    j = fullfile(root, strrep(p, [filesep 'raw' filesep], [filesep 'metadata' filesep]), [n '.json']);
    if ~isfile(j), j = fullfile(root, p, [n '.json']); end      % synthetic: same folder
    if isfile(j), M = jsondecode(fileread(j)); end
end

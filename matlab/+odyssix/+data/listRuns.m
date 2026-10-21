function T = listRuns(which)
%LISTRUNS  Every recorded run, newest first (from the run indexes).
%
%   T = odyssix.data.listRuns()              % hardware and synthetic
%   T = odyssix.data.listRuns('hardware')    % or 'synthetic'
%
%   Columns: run_id, experiment, data_class, date_utc, label, result,
%   duration_s, key_metrics, csv. Runs recorded before the index existed
%   (data/raw/EXP00N/*.csv) are listed too, with what their file name tells.
    if nargin < 1, which = 'all'; end
    root = odyssix.repoRoot();
    files = {};
    if ~strcmpi(which, 'synthetic'), files{end+1} = fullfile(root, 'data', 'metadata', 'run_index.csv'); end
    if ~strcmpi(which, 'hardware'),  files{end+1} = fullfile(root, 'matlab', 'data', 'synthetic', 'run_index.csv'); end
    T = table();
    for i = 1:numel(files)
        if isfile(files{i})
            o = detectImportOptions(files{i}, 'Delimiter', ',', 'TextType', 'string');
            o = setvartype(o, setdiff(o.VariableNames, {'duration_s'}), 'string');
            T = [T; readtable(files{i}, o)]; %#ok<AGROW>
        end
    end
    % legacy runs (2026-10-12): data/raw/EXP00N/EXP00N_yyyyMMdd_HHmmss_rev.csv
    if ~strcmpi(which, 'synthetic')
        L = dir(fullfile(root, 'data', 'raw', 'EXP*', 'EXP*.csv'));
        known = string([]); if ~isempty(T), known = T.csv; end
        for k = 1:numel(L)
            relp = string(fullfile('data', 'raw', L(k).folder(end-5:end), L(k).name));
            if any(known == relp), continue; end
            tok = regexp(L(k).name, '^(EXP\d{3})_(\d{8})_(\d{6})', 'tokens', 'once');
            if isempty(tok), continue; end
            d = datetime([tok{2} tok{3}], 'InputFormat', 'yyyyMMddHHmmss');
            row = table(string(erase(L(k).name, '.csv')), string(tok{1}), "HARDWARE", ...
                string(char(d, 'yyyy-MM-dd HH:mm:ss')), "legacy", "", NaN, "", relp, ...
                'VariableNames', {'run_id', 'experiment', 'data_class', 'date_utc', 'label', ...
                                  'result', 'duration_s', 'key_metrics', 'csv'});
            T = [T; row]; %#ok<AGROW>
        end
    end
    if ~isempty(T), T = sortrows(T, 'date_utc', 'descend'); end
end

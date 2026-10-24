function R = saveCrash(runId, C, info)
%SAVECRASH  Store a 500 Hz crash record next to the run it belongs to.
%
%   R = odyssix.data.saveCrash(runId, C)
%   R = odyssix.data.saveCrash(runId, C, info)    info.firmware, info.rawLog, info.notes
%
%   C is one record from RigLink.takeCrashes(): reason ('OPERATOR' for the 'k'
%   key or the app's PUSH MARK, else the abort reason), triggerTick and a
%   table D with t_s (0 = the trigger), tick, rotor_deg, psi_deg, alpha_deg,
%   u, phase. Files, beside the run's own:
%     data/raw/EXPnnn/<run id>_500Hz_<n>.csv        (read-only)
%     data/metadata/EXPnnn/<run id>_500Hz_<n>.json
%   Synthetic runs (id ending _SYN) go to matlab/data/synthetic/EXPnnn.
    if nargin < 3, info = struct(); end
    root = odyssix.repoRoot();
    ex = runId(1:6);
    if endsWith(runId, '_SYN')
        dDir = fullfile(root, 'matlab', 'data', 'synthetic', ex); mDir = dDir;
    else
        dDir = fullfile(root, 'data', 'raw', ex); mDir = fullfile(root, 'data', 'metadata', ex);
    end
    if ~isfolder(dDir), mkdir(dDir); end
    if ~isfolder(mDir), mkdir(mDir); end
    k = numel(dir(fullfile(dDir, [runId '_500Hz_*.csv']))) + 1;
    id = sprintf('%s_500Hz_%d', runId, k);
    csv = fullfile(dDir, [id '.csv']);
    writetable(C.D, csv);
    if isunix, fileattrib(csv, '-w', 'a'); else, fileattrib(csv, '-w'); end   % raw data is never edited
    M = struct('record_id', id, 'run_id', runId, 'reason', C.reason, ...
        'trigger_tick', C.triggerTick, 'samples', height(C.D), ...
        'sampling', 'every 500 Hz control tick (firmware crash recorder, enr312_crashrec.c)', ...
        'window', '1.5 s before the trigger, 0.5 s after (shorter if the recorder had just re-armed)', ...
        'received_utc', char(C.received, 'yyyy-MM-dd HH:mm:ss'), ...
        'firmware', getf(info, 'firmware', ''), 'raw_serial_log', strrep(char(getf(info, 'rawLog', '')), [root filesep], ''), ...
        'notes', getf(info, 'notes', ''), ...
        'units', struct('t_s', 's from the trigger', 'tick', '500 Hz control ticks', 'rotor_deg', 'deg (commanded)', ...
                        'psi_deg', 'deg, encoder, 0 = hanging datum', 'alpha_deg', 'deg from upright', ...
                        'u', 'deg/s^2 (plant input)', 'phase', 'controller phase'));
    json = fullfile(mDir, [id '.json']);
    fid = fopen(json, 'w'); fprintf(fid, '%s', jsonencode(M, 'PrettyPrint', true)); fclose(fid);
    R = struct('id', id, 'csv', csv, 'json', json);
end

function v = getf(s, f, d), if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end, end

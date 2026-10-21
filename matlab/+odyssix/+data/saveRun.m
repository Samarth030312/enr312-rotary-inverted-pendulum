function R = saveRun(D, info)
%SAVERUN  Record one run: immutable CSV + metadata (YAML and JSON) + index row.
%
%   R = odyssix.data.saveRun(D, info)
%
%   D     table: t [s] plus any of rotor, psi, alpha [deg], u [deg/s^2],
%         ref [deg], phase, ...  (the 50 Hz stream of the 500 Hz loop)
%   info  struct, all optional except exp:
%     exp          experiment number (1..10, 21..24)
%     label        short human tag, e.g. 'T6-ref', 'LAB-up-LQR', 'swing-up'
%     synthetic    true for emulator / simulation runs (stored apart, git-ignored)
%     cfg, plant   configuration sent / model used
%     events       struct array t, what, value  (go-to, live gains, taps, ...)
%     metrics      struct of numbers (odyssix.sim.metrics)
%     result       'FINISHED', 'ABORTED: PENDULUM_LOST', 'STOPPED', ...
%     firmware, protocol, port, board, rawLog, operator, notes
%
%   Naming: EXP006_20261021-191502_T6-ref_R03  (R = run number of that
%   experiment on that day). Hardware runs go to data/raw/EXPnnn (CSV made
%   read-only) and data/metadata/EXPnnn; synthetic runs to
%   matlab/data/synthetic/EXPnnn. One row per run is appended to
%   run_index.csv next to them (odyssix.data.listRuns reads it).
%   R: struct id, csv, yaml, json, dir.
    root = odyssix.repoRoot();
    if ~isfield(info, 'synthetic'), info.synthetic = false; end
    if ~isfield(info, 'label') || isempty(info.label), info.label = 'run'; end
    ex = sprintf('EXP%03d', info.exp);
    now_ = datetime('now', 'TimeZone', 'UTC');
    if info.synthetic
        base = fullfile(root, 'matlab', 'data', 'synthetic'); dDir = fullfile(base, ex); mDir = dDir;
        cls = 'SYNTHETIC';
    else
        base = fullfile(root, 'data'); dDir = fullfile(base, 'raw', ex); mDir = fullfile(base, 'metadata', ex);
        cls = 'HARDWARE';
    end
    if ~isfolder(dDir), mkdir(dDir); end
    if ~isfolder(mDir), mkdir(mDir); end
    day = char(now_, 'yyyyMMdd');
    prev = dir(fullfile(dDir, sprintf('%s_%s-*.csv', ex, day)));
    lbl = regexprep(lower(info.label), '[^a-z0-9]+', '-');
    lbl = regexprep(lbl, '^-|-$', '');
    id = sprintf('%s_%s_%s_R%02d', ex, char(now_, 'yyyyMMdd-HHmmss'), lbl, numel(prev) + 1);
    if info.synthetic, id = [id '_SYN']; end

    csv = fullfile(dDir, [id '.csv']);
    writetable(D, csv);
    if isunix, fileattrib(csv, '-w', 'a'); end           % raw data is never edited

    [~, rev] = system(sprintf('git -C "%s" rev-parse --short HEAD', root)); rev = strtrim(rev);
    [~, dirty] = system(sprintf('git -C "%s" status --porcelain -- firmware matlab', root));
    M = struct();
    M.run_id = id;
    M.experiment_id = ex;
    M.data_class = cls;
    M.label = info.label;
    M.date_utc = char(now_, 'yyyy-MM-dd HH:mm:ss');
    M.result = getf(info, 'result', '');
    M.duration_s = 0; if height(D) > 1, M.duration_s = D.t(end) - D.t(1); end
    M.samples = height(D);
    M.sampling = '50 Hz stream of the 500 Hz control loop, MCU time stamps';
    M.raw_data_file = rel(csv, root);
    M.raw_serial_log = rel(getf(info, 'rawLog', ''), root);
    M.firmware = getf(info, 'firmware', '');
    M.firmware_protocol = getf(info, 'protocol', NaN);
    M.board = getf(info, 'board', '');
    M.serial_port = getf(info, 'port', '');
    M.repository_rev = rev;
    M.repository_dirty = ~isempty(strtrim(dirty));
    M.operator = getf(info, 'operator', '');
    M.notes = getf(info, 'notes', '');
    M.config = getf(info, 'cfg', struct());
    M.plant_model = getf(info, 'plant', struct());
    M.events = getf(info, 'events', struct('t', {}, 'what', {}, 'value', {}));
    M.metrics = getf(info, 'metrics', struct());
    M.units = struct('t', 's', 'rotor', 'deg', 'psi', 'deg, encoder, 0 = hanging datum', ...
                     'alpha', 'deg from upright', 'u', 'deg/s^2 (plant input)', 'ref', 'deg');

    yaml = fullfile(mDir, [id '.yaml']);
    fid = fopen(yaml, 'w'); writeYaml(fid, M, 0); fclose(fid);
    json = fullfile(mDir, [id '.json']);
    fid = fopen(json, 'w'); fprintf(fid, '%s', jsonencode(M, 'PrettyPrint', true)); fclose(fid);

    % ---- index -------------------------------------------------------------
    idx = fullfile(base, ternary(info.synthetic, '', 'metadata'), 'run_index.csv');
    newFile = ~isfile(idx);
    fid = fopen(idx, 'a');
    if newFile, fprintf(fid, 'run_id,experiment,data_class,date_utc,label,result,duration_s,key_metrics,csv\n'); end
    q = @(x) ['"' strrep(strrep(char(x), '"', ''''), ',', ';') '"'];     % every text field quoted, no commas
    fprintf(fid, '%s,%s,%s,%s,%s,%s,%.2f,%s,%s\n', id, ex, cls, M.date_utc, q(info.label), ...
        q(M.result), M.duration_s, q(metricText(M.metrics)), M.raw_data_file);
    fclose(fid);
    R = struct('id', id, 'csv', csv, 'yaml', yaml, 'json', json, 'dir', dDir);
end

function v = getf(s, f, d), if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end, end
function s = ternary(c, a, b), if c, s = a; else, s = b; end, end
function p = rel(p, root), p = strrep(char(p), [root filesep], ''); end

function s = metricText(m)
    f = fieldnames(m); p = {};
    for i = 1:min(numel(f), 6)
        v = m.(f{i});
        if isnumeric(v) && isscalar(v) && isfinite(v), p{end+1} = sprintf('%s=%.3g', f{i}, v); end %#ok<AGROW>
    end
    s = strjoin(p, ' ');
end

function writeYaml(fid, s, ind)
    pad = repmat(' ', 1, ind);
    f = fieldnames(s);
    for i = 1:numel(f)
        v = s.(f{i});
        if isstruct(v) && (numel(v) ~= 1 || strcmp(f{i}, 'events'))
            if isempty(v), fprintf(fid, '%s%s: []\n', pad, f{i}); continue; end
            fprintf(fid, '%s%s:\n', pad, f{i});
            for k = 1:numel(v)
                g = fieldnames(v(k)); parts = cellfun(@(n) sprintf('%s: %s', n, scalar(v(k).(n))), g, 'UniformOutput', false);
                fprintf(fid, '%s  - {%s}\n', pad, strjoin(parts, ', '));
            end
        elseif isstruct(v)
            if isempty(fieldnames(v)), fprintf(fid, '%s%s: {}\n', pad, f{i}); continue; end
            fprintf(fid, '%s%s:\n', pad, f{i});
            writeYaml(fid, v, ind + 2);
        else
            fprintf(fid, '%s%s: %s\n', pad, f{i}, scalar(v));
        end
    end
end

function s = scalar(v)
    if ischar(v) || isstring(v)
        v = char(v); s = ['"' strrep(v, '"', '''') '"'];
    elseif islogical(v)
        if v, s = 'true'; else, s = 'false'; end
    elseif isnumeric(v) && isscalar(v)
        if isnan(v), s = 'null'; else, s = sprintf('%.10g', v); end
    elseif isnumeric(v)
        s = ['[' strjoin(arrayfun(@(x) sprintf('%.6g', x), v(:)', 'UniformOutput', false), ', ') ']'];
    else
        s = '""';
    end
end

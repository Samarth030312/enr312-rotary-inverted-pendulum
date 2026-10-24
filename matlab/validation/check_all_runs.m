function T = check_all_runs(outDir)
%CHECK_ALL_RUNS  Load every recorded rig run, check it, and draw them all.
%
%   T = check_all_runs()      writes results/tables/ALL_RUNS_check.csv and
%                             results/figures/all_runs_overview.png
%
%   For each run in data/raw (odyssix.data.listRuns('hardware')):
%     load time      odyssix.data.loadRun plus odyssix.data.loadRecords, in s
%     samples, duration, median sample interval (50 Hz stream: 0.020 s)
%     time increasing, no missing arm or pendulum samples, metadata present
%     500 Hz records: how many, and how well each is placed on the run (deg rms)
%   A run passes when its time is increasing, nothing is missing, and it has metadata
%   (the five runs of 2026-10-12 predate the metadata files and are marked legacy).
%   This is what the app does when a run is overlaid, so it also checks replay.
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = repo; end
    L = odyssix.data.listRuns('hardware');
    n = height(L); rows = cell(n, 14); S = cell(n, 1);
    for i = 1:n
        id = char(L.run_id(i)); t0 = tic;
        [D, M] = odyssix.data.loadRun(id);
        K = odyssix.data.loadRecords(id, D);
        tl = toc(t0);
        dt = median(diff(D.t));
        mono = all(diff(D.t) > 0);
        full = ~any(isnan(D.rotor)) && ~any(isnan(D.psi));
        meta = ~isempty(fieldnames(M));
        fits = [K.fit]; worst = NaN; if ~isempty(fits), worst = max(fits); end
        legacy = L.label(i) == "legacy";
        ok = mono && full && (meta || legacy);
        rows(i, :) = {id, char(L.experiment(i)), char(L.date_utc(i)), char(L.result(i)), height(D), ...
            D.t(end), dt, mono, full, meta, numel(K), worst, ok, tl};
        S{i} = struct('D', D, 'K', K, 'exp', char(L.experiment(i)), 'id', id, 'load', tl);
    end
    T = cell2table(rows, 'VariableNames', {'run_id', 'experiment', 'date_utc', 'result', 'samples', ...
        'duration_s', 'median_dt_s', 'time_increasing', 'no_missing', 'metadata', 'records_500hz', ...
        'worst_record_fit_deg', 'pass', 'load_s'});
    writetable(T, fullfile(outDir, 'results', 'tables', 'ALL_RUNS_check.csv'));

    % ---- one small plot per run ------------------------------------------------------
    nc = 7; nr = ceil(n / nc);
    f = figure('Color', 'w', 'Position', [20 20 2100 300 * nr], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
    tl = tiledlayout(f, nr, nc, 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = n:-1:1                                          % oldest first
        s = S{i}; D = s.D; ax = nexttile(tl); hold(ax, 'on'); box(ax, 'on'); grid(ax, 'on');
        up = mod(180 - D.psi + 180, 360) - 180;              % from upright
        y = mod(D.psi + 180, 360) - 180;                     % from hanging
        if mean(abs(up) < 30) > 0.5, y = up; lab = '\alpha'; else, lab = '\psi'; end
        yyaxis(ax, 'left'); plot(ax, D.t, y, '-', 'LineWidth', 0.8); ylabel(ax, [lab ' (deg)']);
        for k = s.K
            yk = mod(k.D.psi + 180, 360) - 180; if strcmp(lab, '\alpha'), yk = mod(180 - k.D.psi + 180, 360) - 180; end
            plot(ax, k.D.t, yk, 'k.', 'MarkerSize', 2);
        end
        yyaxis(ax, 'right'); plot(ax, D.t, D.rotor, '-', 'LineWidth', 0.6); ylabel(ax, '\theta (deg)');
        nm = regexprep(s.id, '^(EXP\d+)_(\d{4})(\d{2})(\d{2})[-_](\d{2})(\d{2})\d{2}_?', '$1 $3-$4 $5:$6 ');
        title(ax, strrep(nm, '_', ' '), 'FontSize', 7, 'FontWeight', 'normal', 'Interpreter', 'none');
        ax.FontSize = 6;
    end
    title(tl, sprintf('Every rig run (%d), oldest first: pendulum (left axis; dots = 500 Hz records) and arm (right axis) against time in s', n));
    exportgraphics(f, fullfile(outDir, 'results', 'figures', 'all_runs_overview.png'), 'Resolution', 110);
    close(f);
    fprintf('%d runs, %d pass; load time median %.3f s, max %.3f s; %d records at 500 Hz, worst placement %.2f deg rms\n', ...
        n, nnz(T.pass), median(T.load_s), max(T.load_s), sum(T.records_500hz), max(T.worst_record_fit_deg));
end

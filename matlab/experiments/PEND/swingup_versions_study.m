function T = swingup_versions_study(outDir)
%SWINGUP_VERSIONS_STUDY  Four firmware versions of the swing-up on the identified pendulum.
%
%   T = swingup_versions_study()   writes
%       results/tables/PEND_swingup_versions.csv
%       results/figures/2026-10-21b_swingup_versions.png
%
%   Question. On 2026-10-21 the rig caught the swing-up 3 of 3 times on firmware
%   2.2.0 and 1 of 3 on 2.3.0. Does a model of the pendulum identified from that
%   day's data reproduce this, and what does it predict for 2.3.1 and 2.3.2?
%
%   Plant (matlab/identification/identify_pendulum_20261021.m):
%     wg2  47.6 and 49.5   (free decay; 92 deg swings)
%     dry friction 0.48 rad/s^2 (free decay)
%     Q 50, 65, 90         (R05: at a 92 deg swing the arm puts in 2.7x what dry
%                           friction alone takes out; viscous Q 60-70 makes up
%                           the rest)
%     encoder offset 0 and 0.5 deg; start 0.3, 1.5, -1.0 deg from hanging
%   Firmware told wg2 = 57.01, as on the rig, and also the measured 48.5.
%
%   The older versions are the current simulation (odyssix.sim.runCtrl, equal to
%   the C code) with their catch and learning rules put back; each substitution
%   below is checked to apply exactly once. SIMULATION, not rig data.
    repo = odyssix.repoRoot();
    if nargin < 1, outDir = repo; end
    src = fileread(fullfile(repo, 'matlab', '+odyssix', '+sim', 'runCtrl.m'));
    over = sprintf(['                if upr && abs(aRaw) < 5.0 && abs(dpsi) > 100.0 && ~swOver\n' ...
                    '                    swDelta = swDelta - 1.0 * (en - 2.0);']);
    catchNew = 'if c.amp >= 179.0 && abs(aRaw) <= 7.0 && (slowc || appr) && feas && swE >= 1.8';
    lo = 'lo = -0.3;                                          % CTRL_SW_DELTA_MIN';
    lo0 = 'lo = 0.0; if ~upr, lo = -0.3; end';
    overOld = @(r, k) sprintf(['                if upr && abs(aRaw) < 5.0 && abs(dpsi) > %g && ~swOver\n' ...
                               '                    swDelta = swDelta - %g * (en - 2.0);'], r, k);
    V = struct('name', {'2.2.0', '2.3.0', '2.3.1', '2.3.2'}, 'subs', { ...
        {over, overOld(100, 0.5); catchNew, 'if c.amp >= 179.0 && abs(aRaw) <= 7.0 && abs(dpsi) <= 100.0 && swE >= 1.8'; lo, lo0}, ...
        {over, overOld(60, 0.5);  catchNew, 'if c.amp >= 179.0 && abs(aRaw) <= 7.0 && abs(dpsi) <= 60.0 && swE >= 1.8'; lo, lo0}, ...
        {lo, lo0}, {}});
    tmp = tempname; mkdir(tmp); addpath(tmp); c0 = onCleanup(@() cleanTmp(tmp));
    for i = 1:numel(V)
        s = strrep(src, 'function S = runCtrl(cfg, plant, opts)', sprintf('function S = runCtrlV%d(cfg, plant, opts)', i));
        for j = 1:size(V(i).subs, 1)
            assert(numel(strfind(s, V(i).subs{j, 1})) == 1, 'swingup_versions_study: substitution %d of %s does not apply', j, V(i).name);
            s = strrep(s, V(i).subs{j, 1}, V(i).subs{j, 2});
        end
        fid = fopen(fullfile(tmp, sprintf('runCtrlV%d.m', i)), 'w'); fwrite(fid, s); fclose(fid);
    end
    rehash;

    W = [47.6 49.5]; QQ = [50 65 90]; B = [0 0.5]; P0 = [0.3 1.5 -1.0]; FW = [57.01 48.5];
    rows = {};
    for i = 1:numel(V)
        f = str2func(sprintf('runCtrlV%d', i));
        for fw = FW, for w = W, for q = QQ, for b = B, for p0 = P0
            p = odyssix.sim.plant(5); p.wg2 = w; p.Q = q; p.coulomb = 0.48; p.bias = b;
            c = odyssix.sim.defaults(24); c.seconds = 45; c.wg2 = fw;
            S = f(c, p, struct('psi0', p0)); k = find(S.phase == 8, 1);
            tc = NaN; held = false; if ~isempty(k), tc = S.t(k); held = S.phase(end) == 8; end
            rows(end+1, :) = {V(i).name, fw, w, q, b, p0, tc, held}; %#ok<AGROW>
        end, end, end, end, end
    end
    T = cell2table(rows, 'VariableNames', {'firmware', 'fw_wg2', 'plant_wg2', 'plant_Q', 'enc_offset_deg', 'psi0_deg', 't_catch_s', 'balancing_at_45s'});
    writetable(T, fullfile(outDir, 'results', 'tables', 'PEND_swingup_versions.csv'));

    rig = [3 3; 1 3];                                   % caught / tries on 2026-10-21
    f = figure('Visible', 'off', 'Color', 'w', 'Position', [0 0 1150 480]);
    if exist('theme', 'file'), theme(f, 'light'); end
    ax = axes(f); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    pc = zeros(numel(V), 2);
    for i = 1:numel(V)
        for j = 1:2
            m = strcmp(T.firmware, V(i).name) & T.fw_wg2 == FW(j);
            pc(i, j) = 100 * mean(~isnan(T.t_catch_s(m)) & T.balancing_at_45s(m));
        end
    end
    b = bar(ax, categorical({V.name}, {V.name}), [pc nan(numel(V), 1)], 'EdgeColor', 'none');
    b(1).FaceColor = [0.55 0.55 0.58]; b(2).FaceColor = [0.13 0.55 0.30];
    xr = b(3).XEndPoints(1:2);
    plot(ax, xr, 100 * rig(:, 1) ./ rig(:, 2), 'o', 'MarkerSize', 11, 'LineWidth', 2.2, 'Color', [0.10 0.35 0.80], 'MarkerFaceColor', 'w');
    text(ax, xr + 0.07, 100 * rig(:, 1) ./ rig(:, 2), {'rig 3 of 3', 'rig 1 of 3'}, 'FontSize', 9.5, 'Color', [0.10 0.35 0.80], ...
         'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
    ylim(ax, [0 112]); ylabel(ax, 'caught and still balancing at 45 s (%)');
    legend(ax, {'simulation, firmware told \omega_g^2 57.01 (as on the rig)', 'simulation, firmware told the measured 48.5', '', 'rig, 2026-10-21'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
    title(ax, 'Swing-up on the identified pendulum: told the measured \omega_g^2, every version catches; told 57.01, only 2.3.2 does reliably');
    exportgraphics(f, fullfile(outDir, 'results', 'figures', '2026-10-21b_swingup_versions.png'), 'Resolution', 150);
    close(f);
    for i = 1:numel(V), for j = 1:2
        m = strcmp(T.firmware, V(i).name) & T.fw_wg2 == FW(j); ok = ~isnan(T.t_catch_s(m)) & T.balancing_at_45s(m);
        fprintf('%s  fw wg2 %5.2f: %2d of %d caught and balancing, median catch %.1f s\n', V(i).name, FW(j), sum(ok), sum(m), median(T.t_catch_s(m), 'omitnan'));
    end, end
end

function cleanTmp(d)
    rmpath(d); rmdir(d, 's');
end

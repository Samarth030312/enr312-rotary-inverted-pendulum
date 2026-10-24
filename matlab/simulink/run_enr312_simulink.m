function R = run_enr312_simulink(outDir, parts)
%RUN_ENR312_SIMULINK  The Simulink pendulum, in the five situations of the PEND simulation.
%
%   R = run_enr312_simulink()            writes results/figures/simulink_*.png and
%                                        results/tables/SIMULINK_*.csv (about 7 min)
%   R = run_enr312_simulink(dir, [1 3])  only parts 1 and 3, into dir/results/...
%
%   1. open loop, hanging and upright, from a small angle: stable and unstable
%   2. balancing on the nonlinear model: LQR (experiments 23/24) and dual PID (Tutorial 6)
%   3. a tap while balanced, three sizes
%   4. the largest initial tilt each controller recovers from
%   5. the slowest loop rate at which the dual PID still balances
%   The measured pendulum of this rig is used throughout (enr312_simulink_params).
%   SIMULATION. Needs Simulink; the model is (re)built from build_enr312_simulink.m.
    repo = odyssix.repoRoot();
    if nargin < 1 || isempty(outDir), outDir = repo; end
    if nargin < 2, parts = 1:5; end
    fig = fullfile(outDir, 'results', 'figures'); tab = fullfile(outDir, 'results', 'tables');
    here = fileparts(mfilename('fullpath')); mdl = 'enr312_pendulum';
    if ~isfile(fullfile(here, [mdl '.slx'])), build_enr312_simulink(here); end
    load_system(fullfile(here, [mdl '.slx']));
    C = struct('lqr', [0.10 0.35 0.80], 'pid', [0.85 0.33 0.10], 'grey', [0.55 0.55 0.58], 'bad', [0.80 0.13 0.13]);
    al = @(ps) mod(180 - ps + 180, 360) - 180;
    R = struct();

    % ---- picture of the model ------------------------------------------------------------
    if ~isfolder(fig), mkdir(fig); end
    if ~isfolder(tab), mkdir(tab); end
    print(['-s' mdl], '-dpng', '-r150', fullfile(fig, 'simulink_model.png'));   % works without a display

    % ---- 1. open loop -------------------------------------------------------------------------
    if ismember(1, parts)
        f = mkfig(1300, 430); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        P = enr312_simulink_params(); P.closedLoop = false; P.stopTime = 6; P.upright = false; P.alpha0 = 10;
        o = simP(mdl, P); ax = nexttile(tl); prep(ax);
        plot(ax, o.psi_deg.Time, o.psi_deg.Data, 'Color', C.lqr, 'LineWidth', 1.4);
        xlabel(ax, 't (s)'); ylabel(ax, '\psi from hanging (deg)');
        title(ax, 'Hanging, released at 10°: it swings and decays (stable)');
        P.upright = true; P.alpha0 = 1; P.stopTime = 3;
        o = simP(mdl, P); ax = nexttile(tl); prep(ax);
        p1 = -P.gamma / 2 + sqrt(P.gamma^2 / 4 + P.wg2); p2 = -P.gamma / 2 - sqrt(P.gamma^2 / 4 + P.wg2);
        t = o.psi_deg.Time; lin = P.alpha0 * (p2 * exp(p1 * t) - p1 * exp(p2 * t)) / (p2 - p1);   % linear model, released at rest
        plot(ax, t, 180 - o.psi_deg.Data, 'Color', C.bad, 'LineWidth', 1.4);   % not wrapped: 180 = hanging
        plot(ax, t(lin < 200), lin(lin < 200), '--', 'Color', C.grey, 'LineWidth', 1.2);
        yline(ax, 180, ':', 'hanging', 'Color', C.grey, 'LabelHorizontalAlignment', 'left');
        xlabel(ax, 't (s)'); ylabel(ax, '\alpha from upright (deg)'); ylim(ax, [-20 380]);
        legend(ax, {'nonlinear model', sprintf('linearised: poles +%.2f and %.2f rad/s', p1, p2)}, 'Location', 'southeast');
        title(ax, sprintf('Upright, released at 1°: it falls (unstable pole +%.2f rad/s)', p1));
        save_(f, fig, 'simulink_open_loop.png');
    end
    % ---- 2. balancing --------------------------------------------------------------------------
    if ismember(2, parts)
        f = mkfig(1300, 640); tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        axA = nexttile(tl); prep(axA); axT = nexttile(tl); prep(axT); axU = nexttile(tl); prep(axU);
        for ctl = {'lqr', 'pid'}
            P = enr312_simulink_params('measured', ctl{1}); P.alpha0 = 5; P.stopTime = 10;
            o = simP(mdl, P); c = C.(ctl{1});
            plot(axA, o.psi_deg.Time, al(o.psi_deg.Data), 'Color', c, 'LineWidth', 1.3);
            plot(axT, o.theta_deg.Time, o.theta_deg.Data, 'Color', c, 'LineWidth', 1.3);
            stairs(axU, o.u.Time, o.u.Data, 'Color', c);
        end
        ylabel(axA, '\alpha (deg)'); ylabel(axT, 'arm \theta (deg)'); ylabel(axU, 'u (deg/s^2)'); xlabel(axU, 't (s)');
        legend(axA, {'LQR (experiments 23/24)', 'dual PID (Tutorial 6)'}, 'Location', 'northeast');
        title(axA, 'Released at 5° from upright: both controllers balance the nonlinear model');
        save_(f, fig, 'simulink_balance.png');
    end
    % ---- 3. taps --------------------------------------------------------------------------------
    if ismember(3, parts)
        f = mkfig(1300, 480); tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        taps = [20 40 60]; rows = {};
        for j = 1:2
            ctl = {'lqr', 'pid'}; ax = nexttile(tl); prep(ax); cols = [0.2 0.5 0.85];
            for v = taps
                P = enr312_simulink_params('measured', ctl{j}); P.alpha0 = 0.5; P.tapTime = 3; P.tapRate = v; P.stopTime = 9;
                o = simP(mdl, P); a = al(o.psi_deg.Data); w = o.psi_deg.Time > 3;
                plot(ax, o.psi_deg.Time - 3, a, 'Color', cols(v == taps) * [1 1 1] .* C.(ctl{j}) + (1 - cols(v == taps)) * [1 1 1], 'LineWidth', 1.3);
                rec = recoverTime(o.psi_deg.Time(w) - 3, a(w));
                rows(end+1, :) = {upper(ctl{j}), v, max(abs(a(w))), rec}; %#ok<AGROW>
            end
            xlim(ax, [-0.5 6]); xlabel(ax, 't from the tap (s)'); ylabel(ax, '\alpha (deg)');
            legend(ax, compose('tap %d deg/s', taps), 'Location', 'northeast');
            title(ax, sprintf('%s: a tap while balanced', upper(ctl{j})));
        end
        save_(f, fig, 'simulink_taps.png');
        R.taps = cell2table(rows, 'VariableNames', {'controller', 'tap_deg_s', 'alpha_peak_deg', 'back_within_1p5deg_s'});
        writetable(R.taps, fullfile(tab, 'SIMULINK_taps.csv'));
    end
    % ---- 4. largest initial tilt -----------------------------------------------------------
    if ismember(4, parts)
        a0 = 1:1:30; ok = false(2, numel(a0)); ctl = {'lqr', 'pid'};
        for j = 1:2
            for i = 1:numel(a0)
                P = enr312_simulink_params('measured', ctl{j}); P.alpha0 = a0(i); P.stopTime = 8;
                o = simP(mdl, P); a = al(o.psi_deg.Data);
                ok(j, i) = all(abs(a(o.psi_deg.Time > 6)) < 3) && max(abs(o.theta_deg.Data)) < 240;
                if ~ok(j, i) && i > 1 && ~ok(j, i - 1), break; end
            end
        end
        R.maxTilt = [max([0, a0(ok(1, :))]), max([0, a0(ok(2, :))])];
        writetable(table({'LQR'; 'PID'}, R.maxTilt(:), 'VariableNames', {'controller', 'largest_recovered_tilt_deg'}), ...
            fullfile(tab, 'SIMULINK_max_tilt.csv'));
        fprintf('largest recovered tilt: LQR %d deg, PID %d deg\n', R.maxTilt);
    end
    % ---- 5. slowest loop rate (dual PID) ---------------------------------------------------
    if ismember(5, parts)
        divs = [1 2 5 10 15 20 25 30 35 40]; bal = false(size(divs));
        for i = 1:numel(divs)
            P = enr312_simulink_params('measured', 'pid'); P.div = divs(i); P.alpha0 = 2; P.stopTime = 8;
            o = simP(mdl, P); a = al(o.psi_deg.Data);
            bal(i) = all(abs(a(o.psi_deg.Time > 6)) < 3);
        end
        R.rates = table(500 ./ divs(:), bal(:), 'VariableNames', {'loop_rate_hz', 'balances'});
        writetable(R.rates, fullfile(tab, 'SIMULINK_loop_rate.csv'));
        R.slowestRate = min(500 ./ divs(bal));
        fprintf('slowest loop rate at which the dual PID balances: %.1f Hz\n', R.slowestRate);
    end
    close_system(mdl, 0);
end

function o = simP(mdl, P)
    assignin('base', 'P', P);
    o = sim(mdl, 'SrcWorkspace', 'base');
end

function r = recoverTime(t, a)
% time after which |alpha| stays within 1.5 deg (the dual PID hunts by about 1 deg
% on the friction of the pivot, so a tighter band would never be reached)
    out = abs(a) > 1.5; if ~any(out), r = 0; elseif out(end), r = NaN; else, r = t(find(out, 1, 'last') + 1); end
end

function f = mkfig(w, h)
    f = figure('Color', 'w', 'Position', [60 60 w h], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
end
function prep(ax), hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on'); end
function save_(f, d, name), exportgraphics(f, fullfile(d, name), 'Resolution', 140); close(f); end

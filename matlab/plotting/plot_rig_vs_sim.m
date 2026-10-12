function plot_rig_vs_sim(outFile)
%PLOT_RIG_VS_SIM  Headline figure: rig measurement vs simulation (Tutorial 2)
%   and an inverted-pendulum balancing run (Tutorial 5), from data/raw.
%
%   plot_rig_vs_sim()                 writes results/figures/rig_vs_sim_T2_T5.png
%   plot_rig_vs_sim('file.png')
    repo = odyssix.repoRoot();
    if nargin < 1, outFile = fullfile(repo, 'results', 'figures', 'rig_vs_sim_T2_T5.png'); end
    raw = @(e, stem) readtable(fullfile(repo, 'data', 'raw', e, [stem '.csv']));

    % Tutorial 2: the gains used on the rig (from its metadata)
    H2 = raw('EXP002', 'EXP002_20261012_172601_fcba006');
    c2 = odyssix.sim.defaults(2); c2.kp = 9.275; c2.kd = 3.9;
    S2 = odyssix.sim.runTutorial(c2, odyssix.sim.plant(2));
    % Tutorial 5: longest balancing run on firmware 2.0.8
    H5 = raw('EXP005', 'EXP005_20261012_183152_25f2101');
    al = mod(180 - H5.psi + 180, 360) - 180;
    % under control = from the first command after capture (firmware 2.0.8 waits,
    % motor still, until the operator has let go) until the run ends
    k0 = find(H5.phase >= 1 & H5.phase <= 4 & H5.u ~= 0, 1);
    ctl = false(height(H5), 1); ctl(k0:end) = H5.phase(k0:end) >= 1 & H5.phase(k0:end) <= 4;

    f = figure('Color', 'w', 'Position', [100 100 1300 430], 'Visible', 'off');
    if exist('theme', 'file'), theme(f, 'light'); end
    tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    t2 = H2.t - H2.t(1);
    plot(ax, S2.t, S2.ref, '--', 'Color', [0.2 0.6 0.3], 'LineWidth', 1.2);
    plot(ax, S2.t, S2.rotor, 'Color', [0.55 0.55 0.55], 'LineWidth', 2.2);
    plot(ax, t2, H2.rotor, 'Color', [0.10 0.35 0.80], 'LineWidth', 1.3);
    xlim(ax, [0 19]); xlabel(ax, 't (s)'); ylabel(ax, 'rotor angle (deg)');
    title(ax, 'Tutorial 2: reference step, then load disturbance (Kp 9.275, Kd 3.9)');
    legend(ax, {'reference', 'simulation', 'rig'}, 'Location', 'northeast');

    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    t5 = H5.t - H5.t(k0);
    yyaxis(ax, 'left'); plot(ax, t5(ctl), al(ctl), 'LineWidth', 1.0); ylabel(ax, '\alpha from upright (deg)'); ylim(ax, [-6 6]);
    yyaxis(ax, 'right'); plot(ax, t5(ctl), H5.rotor(ctl), 'LineWidth', 1.0); ylabel(ax, 'rotor angle (deg)');
    xlabel(ax, 't since control started (s)'); xlim(ax, [0 max(t5(ctl))]);
    title(ax, sprintf('Tutorial 5 on the rig: %.0f s balanced, \\alpha RMS %.2f deg', sum(ctl) * 0.02, rms(al(ctl))));
    exportgraphics(f, outFile, 'Resolution', 150); close(f);
end

function exp001_plot_step_rate(p, outDir)
%EXP001_PLOT_STEP_RATE  Step-rate quantisation figure (prediction P5).
%
%   Answers: over what range of commanded step rates is the achieved rate
%   trustworthy? Equations (2)-(3) of FIRST_PRINCIPLES.md.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    fCmd = 50:1:20000;
    s    = exp001_step_rate_model(p, fCmd);

    f = figure('Visible','off','Position',[100 100 950 520]);
    semilogx(s.fCmd, s.errPct, 'LineWidth', 1.0); hold on;
    yline(0, 'k');
    patch([min(fCmd) max(fCmd) max(fCmd) min(fCmd)], [-0.1 -0.1 0.1 0.1], ...
          [0.2 0.6 0.4], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    xline(p.step.maxRateHzExp001, '--r', 'EXP001 rate cap', 'LineWidth', 1.4);
    ylim([-4 4]); grid on;
    xlabel('commanded step rate [steps/s]');
    ylabel('achieved - commanded [%]');
    title({'EXP001 -- Step-rate quantisation from integer timer reload', ...
           sprintf('tick rate = %.2f Hz, ARR = round(tick/f) - 1 (ALGORITHMIC, not measured)', ...
                   p.step.tickHz)});

    exportgraphics(f, fullfile(outDir,'EXP001_matlab_fig3_step_rate.png'), ...
                   'Resolution', 150);
    close(f);
end

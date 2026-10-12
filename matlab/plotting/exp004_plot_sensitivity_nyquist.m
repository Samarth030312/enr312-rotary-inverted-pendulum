function exp004_plot_sensitivity_nyquist(designs, outDir)
%EXP004_PLOT_SENSITIVITY_NYQUIST  Sensitivity magnitude and Nyquist plots.
%
%   Answers: how robust is each design to plant variation, and how close does it
%   pass to the -1 point? These are the same question (Tutorial 4 section 6).
%
%   MODEL, not measured. EXECUTION STATUS: NOT_EXECUTED.

    f = figure('Visible','off','Position',[100 100 1300 520]);

    subplot(1,2,1);
    for i = 1:size(designs,1)
        s = exp004_sensitivity_analysis(designs{i,2}, designs{i,3});
        semilogx(s.w, s.magdB, 'LineWidth', 1.7, 'DisplayName', ...
                 sprintf('%s: M_S = %.2f dB', designs{i,1}, s.MsdB)); hold on;
    end
    yline(0,'k--'); yline(1,':','1 dB (Step 1)'); yline(3,':','3 dB (Step 2)');
    xlim([1e-2 1e3]); ylim([-40 8]); grid on;
    xlabel('frequency [rad/s]'); ylabel('|S(j\omega)| [dB]');
    title('Sensitivity function'); legend('Location','southeast','FontSize',8);

    subplot(1,2,2);
    wn = logspace(-2, 3, 40000);
    for i = 1:size(designs,1)
        s = exp004_sensitivity_analysis(designs{i,2}, designs{i,3}, wn);
        plot(real(s.L), imag(s.L), 'LineWidth', 1.4, 'DisplayName', ...
             sprintf('%s', designs{i,1})); hold on;
    end
    th = linspace(0, 2*pi, 400);
    plot(-1 + cos(th), sin(th), 'k--', 'DisplayName', 'unit circle about (-1,0)');
    plot(-1, 0, 'rx', 'MarkerSize', 9, 'LineWidth', 2, 'HandleVisibility','off');
    xlim([-3 1.5]); ylim([-2.5 2.5]); axis equal; grid on;
    xlabel('Re L(j\omega)'); ylabel('Im L(j\omega)');
    title('Nyquist: M_S = 1/min|1+L|'); legend('Location','southwest','FontSize',8);

    sgtitle('EXP004 (Tutorial 4) -- sensitivity and Nyquist [MODEL, not measured]');
    exportgraphics(f, fullfile(outDir,'EXP004_matlab_fig1_sensitivity_nyquist.png'), ...
                   'Resolution', 150);
    close(f);
end

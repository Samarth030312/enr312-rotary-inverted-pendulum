function exp002_plot_sensitivity(m1, m2, outDir)
%EXP002_PLOT_SENSITIVITY  T(s) and SD(s) step responses for two designs.
%
%   Answers: how does each design trade reference tracking against load-disturbance
%   rejection, and where does the permanent 1/Kp offset appear?
%
%   MODEL, not measured. EXECUTION STATUS: NOT_EXECUTED.

    [t, yT1]  = exp002_step_response(m1.T,  12, 12001);
    [~, yD1]  = exp002_step_response(m1.SD, 12, 12001);
    [~, yT2]  = exp002_step_response(m2.T,  12, 12001);
    [~, yD2]  = exp002_step_response(m2.SD, 12, 12001);

    f = figure('Visible','off','Position',[100 100 1200 500]);

    subplot(1,2,1);
    plot(t, yT1, 'LineWidth', 1.8); hold on;
    plot(t, yT2, '--', 'LineWidth', 1.8);
    yline(1, 'k'); grid on;
    xlabel('time [s]'); ylabel('rotor angle / reference [-]');
    title('Complementary sensitivity T(s) -- final value 1');
    legend(sprintf('Kp=%.2f, Kd=%.2f', m1.kp, m1.kd), ...
           sprintf('Kp=%.2f, Kd=%.2f', m2.kp, m2.kd), 'Location','southeast');

    subplot(1,2,2);
    plot(t, yD1, 'LineWidth', 1.8); hold on;
    plot(t, yD2, '--', 'LineWidth', 1.8);
    yline(m1.SD_final, ':'); yline(m2.SD_final, ':'); yline(0, 'k'); grid on;
    xlabel('time [s]'); ylabel('rotor angle deviation [-]');
    title('Load-disturbance sensitivity SD(s) -- final value 1/Kp, NOT zero');
    legend(sprintf('Kp=%.2f (offset %.4f)', m1.kp, m1.SD_final), ...
           sprintf('Kp=%.2f (offset %.4f)', m2.kp, m2.SD_final), 'Location','southeast');

    sgtitle('EXP002 (Tutorial 2) -- sensitivity step responses [MODEL, not measured]');
    exportgraphics(f, fullfile(outDir,'EXP002_matlab_fig1_sensitivity.png'), ...
                   'Resolution', 150);
    close(f);
end

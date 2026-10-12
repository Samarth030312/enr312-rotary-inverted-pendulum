function exp003_plot_control_effort(designs, outDir)
%EXP003_PLOT_CONTROL_EFFORT  Tracking vs control effort for several designs.
%
%   Answers: what does each increment of tracking performance cost in actuator
%   amplitude and energy?
%
%   MODEL, not measured. EXECUTION STATUS: NOT_EXECUTED.

    t = linspace(0, 20, 20001).';
    f = figure('Visible','off','Position',[100 100 1250 500]);

    for i = 1:size(designs, 1)
        m = exp003_mimo_model(designs{i,2}, designs{i,3}, 100);
        y = local_step(m.Ttracking, t);
        u = local_step(m.CE, t);
        ce = exp003_control_effort(u, t);
        lbl = sprintf('%s: Kp=%.2f Kd=%.3f  CE_{tot}=%.2f', ...
                      designs{i,1}, m.kpRotor, m.kdRotor, ce.total);
        subplot(1,2,1); plot(t, y, 'LineWidth', 1.7); hold on;
        subplot(1,2,2); plot(t, u, 'LineWidth', 1.3, 'DisplayName', lbl); hold on;
    end

    subplot(1,2,1); yline(1,'k'); grid on; xlabel('time [s]');
    ylabel('rotor angle / reference [-]');
    title('Rotor step response T_{rotor-tracking}(s)');

    subplot(1,2,2); yline(0,'k'); grid on; xlabel('time [s]');
    ylabel('control signal u [-]'); legend('Location','northeast','FontSize',8);
    title('Control effort CE(s) = K_{rotor}/(1+T_{rotor}K_{rotor})');

    sgtitle('EXP003 (Tutorial 3) -- tracking vs control effort [MODEL, not measured]');
    exportgraphics(f, fullfile(outDir,'EXP003_matlab_fig1_control_effort.png'), ...
                   'Resolution', 150);
    close(f);
end

function y = local_step(tf, t)
    p = roots(tf.den);
    y = polyval(tf.num, 0) / polyval(tf.den, 0) * ones(size(t));
    dp = polyder(tf.den);
    for k = 1:numel(p)
        res = polyval(tf.num, p(k)) / (p(k) * polyval(dp, p(k)));
        y = y + real(res * exp(p(k) * t));
    end
end

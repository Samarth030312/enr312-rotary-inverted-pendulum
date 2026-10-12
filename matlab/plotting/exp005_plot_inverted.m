function exp005_plot_inverted(designs, outDir)
%EXP005_PLOT_INVERTED  Step response and Nyquist for inverted-mode designs.
%
%   The step plot's key feature is the INITIAL DIP -- the non-minimum-phase zero
%   at +7.29 rad/s. Physically the arm moves away from the target first, to get
%   under the pendulum before carrying it.
%
%   MODEL, not measured. EXECUTION STATUS: NOT_EXECUTED.

    t = linspace(0, 15, 15001).';
    f = figure('Visible','off','Position',[100 100 1300 520]);

    subplot(1,2,1);
    for i = 1:size(designs,1)
        m = exp005_inverted_model(designs{i,2}, designs{i,3});
        y = local_step(m.T, t);
        plot(t, y, 'LineWidth', 1.6, 'DisplayName', designs{i,1}); hold on;
    end
    yline(1,'k'); yline(0,':','Color',[0.5 0.5 0.5]); grid on;
    xlabel('time [s]'); ylabel('rotor angle / reference [-]');
    title({'Rotor step response, INVERTED mode', ...
           'initial dip = non-minimum-phase zero at +7.29 rad/s'});
    legend('Location','southeast','FontSize',8);

    subplot(1,2,2);
    wn = logspace(-2, 3, 60000);
    for i = 1:size(designs,1)
        m = exp005_inverted_model(designs{i,2}, designs{i,3});
        s = exp005_stability_margins(m, wn);
        plot(real(s.L), imag(s.L), 'LineWidth', 1.3, 'DisplayName', ...
             sprintf('%s (\\phi_M=%.0f\\circ)', designs{i,1}, s.phiMdeg)); hold on;
    end
    th = linspace(0, 2*pi, 400);
    plot(-1 + cos(th), sin(th), 'k--', 'DisplayName', 'unit circle about (-1,0)');
    plot(-1, 0, 'rx', 'MarkerSize', 9, 'LineWidth', 2, 'HandleVisibility','off');
    xlim([-3 1.5]); ylim([-2.5 2.5]); axis equal; grid on;
    xlabel('Re L(j\omega)'); ylabel('Im L(j\omega)');
    title('Nyquist -- inverted mode'); legend('Location','southwest','FontSize',8);

    sgtitle('EXP005 (Tutorial 5) -- unstable MIMO, inverted mode [MODEL, not measured]');
    exportgraphics(f, fullfile(outDir,'EXP005_matlab_fig1_inverted.png'), ...
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

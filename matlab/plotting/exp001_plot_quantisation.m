function exp001_plot_quantisation(p, m, outDir)
%EXP001_PLOT_QUANTISATION  Figures for the EXP001 sensing chain.
%
%   Answers two engineering questions:
%     (a) what does quantisation do to a slow, small-amplitude motion?
%     (b) does sampling faster or resolving finer reduce differentiation noise?
%
%   These are properties of the ALGORITHM, not measurements of the rig. The
%   figure titles say so, and they must keep saying so.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    t     = (0 : p.timing.Ts : 2 - p.timing.Ts).';
    amp   = deg2rad(5);
    f0    = 0.5;
    theta = amp * sin(2*pi*f0*t);
    omegaTrue = amp * 2*pi*f0 * cos(2*pi*f0*t);

    thetaQ   = round(theta / m.q) * m.q;
    omegaEst = [0; diff(thetaQ) / p.timing.Ts];

    f = figure('Visible','off','Position',[100 100 1000 700]);

    subplot(2,1,1);
    plot(t, rad2deg(theta), 'LineWidth', 1.6); hold on;
    stairs(t, rad2deg(thetaQ), 'LineWidth', 1.0);
    ylabel('pendulum angle [deg]'); grid on;
    legend('true angle', sprintf('quantised (%.3f deg/count)', p.encoder.degPerCount), ...
           'Location','northeast');
    title({'EXP001 -- Quantisation of a slow, small-amplitude motion', ...
           sprintf('%d counts/rev, Ts = %g s (ALGORITHMIC, not measured)', ...
                   p.encoder.countsPerRev, p.timing.Ts)});

    subplot(2,1,2);
    plot(t, omegaTrue, 'LineWidth', 1.8); hold on;
    stairs(t, omegaEst, 'LineWidth', 0.9);
    for k = -2:2
        yline(k * m.velGranularity, ':', 'Color', [0.5 0.5 0.5]);
    end
    xlabel('time [s]'); ylabel('angular velocity [rad/s]'); grid on;
    legend('true angular velocity', 'raw backward difference', 'Location','northeast');
    text(0.02, 0.06, sprintf(['dotted: multiples of q/Ts = %.3f rad/s\n' ...
                              'the estimate can take no other value'], ...
                             m.velGranularity), 'Units','normalized', ...
         'BackgroundColor','w','FontSize',9);

    exportgraphics(f, fullfile(outDir,'EXP001_matlab_fig1_quantisation.png'), ...
                   'Resolution', 150);
    close(f);

    % --- Trade-off figure --------------------------------------------------
    rates   = [100 200 250 333 500 1000 2000];
    f = figure('Visible','off','Position',[100 100 1150 480]);

    subplot(1,2,1);
    for d = [1 2 4]
        q = 2*pi / (p.encoder.ppr * d);
        semilogy(rates, (q/sqrt(12))*sqrt(2).*rates, 'o-', 'LineWidth', 1.4); hold on;
    end
    set(gca,'XScale','log'); grid on;
    xline(p.timing.fs, '--r', 'this rig');
    xlabel('sample rate [Hz]'); ylabel('\sigma_\omega [rad/s]');
    legend('X1 (600 c/rev)','X2 (1200 c/rev)','X4 (2400 c/rev)','Location','northwest');
    title('Differentiation noise rises linearly with sample rate');

    subplot(1,2,2);
    fcs = logspace(0, 2.4, 60);
    semilogx(fcs, m.sigmaOmegaFiltered(fcs), 'LineWidth', 2); hold on;
    yline(m.sigmaOmega, '--r', sprintf('unfiltered = %.3f rad/s', m.sigmaOmega));
    xline(10, ':', 'reference 10 Hz', 'Color', [0.1 0.5 0.3], 'LineWidth', 1.4);
    grid on;
    xlabel('derivative low-pass corner frequency [Hz]');
    ylabel('\sigma_\omega [rad/s]');
    title('Why the derivative filter is not optional');

    sgtitle('EXP001 -- Velocity-estimation noise (ALGORITHMIC, not measured)');
    exportgraphics(f, fullfile(outDir,'EXP001_matlab_fig2_velocity_noise.png'), ...
                   'Resolution', 150);
    close(f);
end

function animate_enr312_simulink(o, gifFile, opts)
%ANIMATE_ENR312_SIMULINK  Show a Simulink run of the pendulum in 3-D.
%
%   o = sim('enr312_pendulum');  animate_enr312_simulink(o)
%   animate_enr312_simulink(o, 'tap.gif')                  also write an animated GIF
%   animate_enr312_simulink(o, '', 'Speed', 0.5)           half speed
%
%   o is the output of sim(): o.theta_deg (arm) and o.psi_deg (pendulum, 0 =
%   hanging). The geometry is the rig's: arm r = 0.14 m to the pivot, the rod
%   0.26 m, swinging in the vertical plane at right angles to the arm (the same
%   frame as the derivation, docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md §4).
    arguments
        o
        gifFile (1,:) char = ''
        opts.Speed (1,1) double = 1
        opts.Fps (1,1) double = 25
    end
    r = 0.14; L = 0.26;
    t  = (0:1 / opts.Fps * opts.Speed:o.psi_deg.Time(end))';
    th = interp1(o.theta_deg.Time, o.theta_deg.Data, t, 'previous', 'extrap') * pi / 180;
    ps = interp1(o.psi_deg.Time, o.psi_deg.Data, t, 'linear', 'extrap') * pi / 180;

    f = figure('Color', 'w', 'Position', [100 100 640 560], 'Visible', ternary(isempty(gifFile), 'on', 'off'));
    if exist('theme', 'file'), theme(f, 'light'); end      % R2025a+ opens figures dark
    ax = axes(f); hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on'); view(ax, 35, 22);
    lim = r + L; axis(ax, [-lim lim -lim lim -L - 0.05 L + 0.05]);
    xlabel(ax, 'x (m)'); ylabel(ax, 'y (m)'); zlabel(ax, 'z (m)');
    plot3(ax, [0 0], [0 0], [-0.12 0], 'k', 'LineWidth', 6);                  % motor
    hA = plot3(ax, [0 r], [0 0], [0 0], 'Color', [0.35 0.35 0.4], 'LineWidth', 5);
    hP = plot3(ax, [r r], [0 0], [0 -L], 'Color', [0.80 0.13 0.13], 'LineWidth', 4);
    hB = plot3(ax, r, 0, -L, 'o', 'MarkerSize', 7, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');
    hT = title(ax, '');
    for i = 1:numel(t)
        piv = r * [cos(th(i)), sin(th(i)), 0];
        tan_ = [-sin(th(i)), cos(th(i)), 0];
        tip = piv + L * (-sin(ps(i)) * tan_ + [0 0 -cos(ps(i))]);
        set(hA, 'XData', [0 piv(1)], 'YData', [0 piv(2)], 'ZData', [0 0]);
        set(hP, 'XData', [piv(1) tip(1)], 'YData', [piv(2) tip(2)], 'ZData', [0 tip(3)]);
        set(hB, 'XData', tip(1), 'YData', tip(2), 'ZData', tip(3));
        a = mod(180 - ps(i) * 180 / pi + 180, 360) - 180;
        hT.String = sprintf('t = %5.2f s    arm %6.1f°    from upright %6.1f°', t(i), th(i) * 180 / pi, a);
        if isempty(gifFile)
            drawnow; pause(1 / opts.Fps);
        else
            exportgraphics(f, gifFile, 'Append', i > 1, 'Resolution', 72);
        end
    end
    if ~isempty(gifFile), close(f); end
end

function v = ternary(c, a, b), if c, v = a; else, v = b; end, end

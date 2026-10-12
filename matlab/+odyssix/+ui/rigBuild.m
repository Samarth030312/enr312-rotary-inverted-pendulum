function rig = rigBuild(ax, opts)
%RIGBUILD  3-D model of the STEVAL-EDUKIT01 rotary pendulum, for live display.
%
%   rig = odyssix.ui.rigBuild(ax)            % ax: axes or uiaxes
%   odyssix.ui.rigPose(rig, thetaDeg, alphaDeg, refDeg, lenScale)
%
%   Geometry: NEMA17 shaft vertical on a stand tall enough for the pendulum
%   to hang and swing through a full turn; rotor arm r = 0.14 m (Edukit
%   Manual Table 2); LPD3806 encoder at the arm tip, shaft radial; pendulum a
%   uniform rod ~0.25 m swinging in the plane perpendicular to the arm.
%   Proportions are representative, not measured.

    arguments
        ax
        opts.ShowReference (1,1) logical = true
    end
    hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off');
    ax.Color = 'w'; ax.Clipping = 'off';
    view(ax, 38, 14);
    xlim(ax, [-0.20 0.24]); ylim(ax, [-0.22 0.22]); zlim(ax, [0 0.62]);
    try, ax.Toolbar.Visible = 'off'; catch, end
    dark = [0.18 0.19 0.22]; alu = [0.78 0.80 0.83]; blue = [0.16 0.38 0.78];

    zArm = 0.316;
    box3([0 0 0.006], [0.36 0.28 0.012], [0.30 0.31 0.34], ax);            % base plate
    box3([-0.03 0 0.136], [0.012 0.06 0.248], [0.62 0.64 0.67], ax);       % stand upright
    box3([0 0 0.255], [0.072 0.072 0.010], [0.62 0.64 0.67], ax);          % motor plate
    box3([0 0 0.280], [0.0423 0.0423 0.040], dark, ax);                    % NEMA17 body
    cyl3([0 0 0.300], [0 0 1], 0.0025, 0.012, alu, ax);                    % shaft
    box3([-0.12 0.09 0.020], [0.07 0.055 0.016], [0.10 0.35 0.18], ax);    % IHM01A1
    box3([-0.12 0.09 0.031], [0.07 0.055 0.004], [0.08 0.18 0.40], ax);    % Nucleo

    rig.rotor = hgtransform('Parent', ax);
    box3([0.065 0 zArm], [0.15 0.022 0.008], blue, rig.rotor);             % rotor arm
    cyl3([0 0 zArm - 0.006], [0 0 1], 0.011, 0.014, alu, rig.rotor);       % hub
    cyl3([0.122 0 zArm], [1 0 0], 0.019, 0.034, dark, rig.rotor);          % encoder body
    cyl3([0.156 0 zArm], [1 0 0], 0.003, 0.010, alu, rig.rotor);           % encoder shaft
    rig.pend = hgtransform('Parent', rig.rotor);
    cyl3([0.166 0 0], [0 0 1], 0.0045, 0.255, [0.86 0.22 0.18], rig.pend); % rod
    cyl3([0.166 0 -0.006], [1 0 0], 0.009, 0.012, alu, rig.pend);          % clamp
    rig.pivot = [0 0 zArm];
    rig.ref = plot3(ax, [0 0.20], [0 0], [zArm zArm] + 0.012, '--', ...
                    'Color', [0.13 0.59 0.33], 'LineWidth', 2, 'Visible', opts.ShowReference);
    light(ax, 'Position', [0.6 -0.8 1.0]);
end

function box3(c, d, col, parent)
    [X, Y, Z] = ndgrid([-1 1] * d(1) / 2, [-1 1] * d(2) / 2, [-1 1] * d(3) / 2);
    V = [X(:) Y(:) Z(:)] + c;
    F = [1 2 4 3; 5 6 8 7; 1 2 6 5; 3 4 8 7; 1 3 7 5; 2 4 8 6];
    shade = [1.0 0.80 0.92 0.92 0.72 0.72]';        % fixed per-face shading
    patch('Vertices', V, 'Faces', F, 'FaceVertexCData', shade * col, 'FaceColor', 'flat', ...
          'EdgeColor', col * 0.55, 'LineWidth', 0.6, 'FaceLighting', 'none', 'Parent', parent);
end

function cyl3(base, axisDir, rad, len, col, parent)
    [X, Y, Z] = cylinder(rad, 28); Z = Z * len;
    if axisDir(1) == 1, [X, Y, Z] = deal(Z, X, Y); end       % along +x
    surf(X + base(1), Y + base(2), Z + base(3), 'FaceColor', col, 'EdgeColor', 'none', ...
         'FaceLighting', 'gouraud', 'AmbientStrength', 0.45, 'Parent', parent);
    th = linspace(0, 2*pi, 28);
    for e = [0 len]
        if axisDir(1) == 1, cx = e + 0*th; cy = rad*cos(th); cz = rad*sin(th);
        else,               cx = rad*cos(th); cy = rad*sin(th); cz = e + 0*th; end
        patch(cx + base(1), cy + base(2), cz + base(3), col, 'EdgeColor', 'none', ...
              'FaceLighting', 'gouraud', 'Parent', parent);
    end
end

function rigPose(rig, thetaDeg, alphaDeg, refDeg, lenScale)
%RIGPOSE  Pose an odyssix.ui.rigBuild model.
%
%   thetaDeg  arm angle (deg)
%   alphaDeg  pendulum angle from UPRIGHT, Tutorial-5 sense (deg): 0 = upright,
%             180 = hanging. Positive alpha tilts the rod toward -theta, the
%             way it lags when the arm accelerates in +theta. From the encoder
%             angle psi (0 = hanging): alpha = 180 - psi.
%   refDeg    reference arm angle, drawn dashed (deg)
%   lenScale  rod length / drawn length (default 1)
    if nargin < 5, lenScale = 1; end
    if nargin < 4 || isempty(refDeg), refDeg = thetaDeg; end
    rig.rotor.Matrix = makehgtform('zrotate', deg2rad(thetaDeg));
    rig.pend.Matrix = makehgtform('translate', rig.pivot) * makehgtform('xrotate', deg2rad(alphaDeg)) ...
                      * makehgtform('scale', [1 1 lenScale]);
    rig.ref.XData = [0 0.20 * cosd(refDeg)]; rig.ref.YData = [0 0.20 * sind(refDeg)];
end

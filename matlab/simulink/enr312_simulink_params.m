function P = enr312_simulink_params(a, b)
%ENR312_SIMULINK_PARAMS  Parameters for the Simulink model enr312_pendulum.slx.
%
%   P = enr312_simulink_params(9)                Tutorial 9, this rig's measured pendulum
%   P = enr312_simulink_params(5, 'tutorial')    Tutorial 5 on the Tutorials' pendulum
%   P = enr312_simulink_params()                 experiment 23 (upright LQR), already balancing
%
%   exp        1-10 (Tutorials 1-10) or 21-24 (PEND: stop a swing, on-off control,
%              upright LQR, swing-up). Every one runs the firmware's own control code
%              (Enr312Firmware.m) with its default settings, odyssix.sim.defaults(exp).
%   pendulum   'measured' (this rig: odyssix.rigParams) or 'tutorial' (the
%              Tutorials' values, odyssix.sim.plant(exp)).
%
%   Change any field before sim(), for example P.kpp = 200 or P.step = 30.
%   Firmware settings (the same names as in the app and the firmware's $ commands):
%     kp kd ki kpp kdp fdr fdp k1 k2 k3 k4 bv uon db step dist imp rrate div ma seq
%     ulim (deg/s^2) vmax (deg/s) amp (deg) fw_wg2 (the firmware's own pendulum constant)
%   Pendulum:  wg2 (rad^2/s^2) wr2 (-) Q gamma (1/s) coulomb (rad/s^2) bias (deg)
%   Scenario:  psi0 (deg from hanging; 180 = upright) stopTime (s) closedLoop safety
%              startBalancing (upright experiments: skip the hand-held start)
%              tapTime (s) tapRate (deg/s, on the tilt from upright) tapWidth (s)
%              refEvents [t ref; ...] arm set-points sent during the run (deg)
%
%   The older form enr312_simulink_params('measured', 'lqr' | 'pid') still works:
%   experiment 23 or 6, already balancing, no reference steps.
    legacy = false; pendulum = 'measured';
    if nargin < 1
        exp = 23; legacy = true;
    elseif ischar(a) || isstring(a)                 % older form ('measured', 'lqr')
        pendulum = char(a); legacy = true; exp = 23;
        if nargin >= 2 && strcmpi(b, 'pid'), exp = 6; end
    else
        exp = a; if nargin >= 2, pendulum = char(b); end
    end

    c = odyssix.sim.defaults(exp);
    P = struct('exp', exp);
    for f = fieldnames(c)'
        if ~any(strcmp(f{1}, {'exp', 'wg2', 'seconds'})), P.(f{1}) = c.(f{1}); end
    end
    if ~isfield(P, 'amp'), P.amp = 180; end
    P.fw_wg2 = 55.85; if isfield(c, 'wg2'), P.fw_wg2 = c.wg2; end

    % ---- pendulum (plant) ---------------------------------------------------------
    pl = odyssix.sim.plant(exp);
    switch lower(pendulum)
        case 'measured'
            rp = odyssix.rigParams().pendulum;
            P.wg2 = rp.wg2;                 % rad^2/s^2 (= g/L_eq), six free swings
            P.wr2 = rp.wr2;                 % dimensionless (pendulum rad/s^2 per arm rad/s^2), wg2 * r / g
            P.coulomb = rp.coulomb;         % rad/s^2, dry pivot friction (large hanging swings)
            if any(exp == [5 6 7 8 23]) && isfield(rp, 'coulombUpright')
                P.coulomb = rp.coulombUpright;  % balancing upright the pivot barely turns: the
            end                                 % 2026-10-24 upright runs fit 0.05-0.2, not 0.37 (as the app)
            P.Q = mean(rp.QLargeSwing);     % viscous part, large swings
            P.fw_wg2 = rp.wg2;              % the swing-up is given the measured value ($wg2), as on the rig
        case 'tutorial'
            P.wg2 = pl.wg2; P.wr2 = pl.wr2; P.Q = pl.Q; P.coulomb = 0;
        otherwise
            error('enr312:params', 'pendulum must be ''measured'' or ''tutorial''');
    end
    if exp == 2, P.wr2 = 0; end             % Tutorial 2: the pendulum is removed or clamped
    P.gamma = sqrt(P.wg2) / P.Q;            % 1/s
    P.coulombWidth = 0.01;                  % rad/s: dry friction as c*tanh(psidot/width)
    P.bias = 0;                             % deg, encoder zero offset from true hanging

    % ---- sensors and actuator (the rig's resolution) ------------------------------
    P.encDeg = 360 / 2400;                  % encoder count, deg
    P.stepDeg = 360 / 3200;                 % microstep, deg
    P.Ts = 0.002;                           % control period, s (500 Hz)

    % ---- scenario -------------------------------------------------------------------
    up = any(exp == [5 6 7 8 23]);
    P.psi0 = 0.4; if up, P.psi0 = 179.4; end % as the firmware twin: held 0.6 deg off upright
    if exp == 21, P.psi0 = 20; end          % stop a swing: it starts swinging (as in the app)
    P.closedLoop = true;
    P.safety = true;                        % the firmware's stop rules (false: the control law alone)
    P.startBalancing = false;
    P.release = 0;                          % s the hand keeps holding after capture
    P.refEvents = zeros(0, 2);
    P.tapTime = 5; P.tapRate = 0; P.tapWidth = 0.01;
    P.stopTime = c.seconds;

    if legacy                               % the older study: already balancing, no steps
        P.startBalancing = true; P.seq = 0; P.psi0 = 178; P.stopTime = 12;
    end
end

function P = enr312_simulink_params(pendulum, controller)
%ENR312_SIMULINK_PARAMS  Parameters for the Simulink model enr312_pendulum.slx.
%
%   P = enr312_simulink_params()                     measured pendulum, LQR
%   P = enr312_simulink_params('tutorial', 'pid')    Tutorial pendulum, dual PID
%
%   pendulum    'measured' (this rig, odyssix.rigParams) or 'tutorial' (Tutorial 5)
%   controller  'lqr' (experiments 23/24: the swing-up's balancing law) or
%               'pid' (Tutorial 6: rotor PID + pendulum PD)
%
%   Every number is the firmware's (firmware/enr312/src/enr312_ctrl.c) or the rig's
%   (shared/parameters/edukit01_rig.yaml). Units: the plant works in rad, the
%   controller in deg, as the firmware does.
    if nargin < 1, pendulum = 'measured'; end
    if nargin < 2, controller = 'lqr'; end

    % ---- pendulum (plant) ---------------------------------------------------------
    switch lower(pendulum)
        case 'measured'
            rp = odyssix.rigParams().pendulum;
            P.wg2 = rp.wg2;                 % rad^2/s^2 (= g/L_eq), six free swings
            P.wr2 = rp.wr2;                 % dimensionless (pendulum rad/s^2 per arm rad/s^2), wg2 * r / g
            P.coulomb = rp.coulomb;         % rad/s^2, dry pivot friction
            P.Q = mean(rp.QLargeSwing);     % viscous part, large swings
        case 'tutorial'
            q = rotary_pendulum_params('inverted');
            P.wg2 = q.wg2; P.wr2 = q.wr2; P.Q = q.Q; P.coulomb = 0;
        otherwise
            error('enr312:params', 'pendulum must be ''measured'' or ''tutorial''');
    end
    P.gamma = sqrt(P.wg2) / P.Q;            % 1/s
    P.coulombWidth = 0.01;                  % rad/s: dry friction as c*tanh(psidot/width)

    % ---- sensors and actuator (the rig's resolution) ------------------------------
    P.encDeg = 360 / 2400;                  % encoder count, deg
    P.stepDeg = 360 / 3200;                 % microstep, deg
    P.Ts = 0.002;                           % control period, s (500 Hz)
    P.div = 1;                              % control every div ticks (loop rate 500/div Hz)
    P.uLimit = 1500;                        % deg/s^2, plant-input clamp
    P.vMax = 360;                           % deg/s, arm speed ceiling

    % ---- controller -------------------------------------------------------------------
    P.controller = lower(controller);
    P.isLqr = strcmp(P.controller, 'lqr');
    P.k = [-10, -13.787, 382.789, 50.787];  % LQR on [theta, thetadot, alpha, alphadot], deg units
    P.kp = 15; P.ki = 3; P.kd = 7.5;        % Tutorial 6 rotor PID (Ti 5 s, Td 0.5 s)
    P.kpp = 300; P.kdp = 30;                % pendulum PD
    P.fdr = 50; P.fdp = 10;                 % derivative filters, Hz
    if P.isLqr, P.fdp = 5; end              % exp 23/24
    P.ref = 0;                              % arm set-point, deg

    % ---- scenario ---------------------------------------------------------------------
    P.alpha0 = 2;                           % initial tilt from upright, deg
    P.upright = true;                       % start near upright (false: near hanging)
    P.closedLoop = true;
    P.tapTime = 5;                          % s
    P.tapRate = 0;                          % deg/s added to the pendulum rate (0: no tap)
    P.tapWidth = 0.01;                      % s, the tap is spread over this time
    P.stopTime = 12;                        % s
end

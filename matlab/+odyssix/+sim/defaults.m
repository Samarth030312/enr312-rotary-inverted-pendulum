function cfg = defaults(exp)
%DEFAULTS  Default configuration, identical to ENR312_Runner_Defaults (firmware).
%   cfg = odyssix.sim.defaults(exp)    exp = 1..10 or 21..24
%   Experiments 6-10 and 21-23 (general core, enr312_ctrl.c) have the extra
%   fields ki fdr fdp k1 k2 k3 k4 bv imp uon db rrate div ma seq wg2 amp.
    cfg = struct('exp', exp, 'kp', 0, 'kd', 0, 'kpp', 0, 'kdp', 0, 'step', 2, ...
                 'dist', 0, 'ulim', 400, 'vmax', 360, 'seconds', 20);
    if exp >= 6
        x = struct('ki', 0, 'fdr', 50, 'fdp', 10, 'k1', 0, 'k2', 0, 'k3', 0, 'k4', 0, ...
                   'bv', 0, 'imp', 0, 'uon', 0, 'db', 0, 'rrate', 90, 'div', 1, 'ma', 1, ...
                   'seq', 1, 'wg2', 55.85, 'amp', 180);
        for f = fieldnames(x)', cfg.(f{1}) = x.(f{1}); end
        cfg.step = 0; cfg.ulim = 1500;
    end
    switch exp
        case 1, cfg.step = 5;  cfg.seconds = 8;                         % first motion
        case 2, cfg.kp = 5; cfg.kd = 2.5; cfg.dist = 1; cfg.ulim = 400; cfg.seconds = 19.5;
        case {3, 4}, cfg.kp = 6; cfg.kd = 4.8; cfg.kpp = 10; cfg.kdp = 5; cfg.ulim = 800; cfg.seconds = 19;
        case 5, cfg.kp = 9; cfg.kd = 9; cfg.kpp = 300; cfg.kdp = 30; cfg.ulim = 1500; cfg.seconds = 25;
        case 6   % Tutorial 6 reference: Kp 15, Ti 5 s (Ki 3), Td 0.5 s
            cfg.kp = 15; cfg.ki = 3; cfg.kd = 7.5; cfg.kpp = 300; cfg.kdp = 30; cfg.step = 40; cfg.seconds = 43;
        case 7   % Tutorial 7: rotor PID fixed 15/0/7.5; pendulum PD designed
            cfg.kp = 15; cfg.kd = 7.5; cfg.kpp = 300; cfg.kdp = 30; cfg.imp = 10; cfg.seconds = 53;
        case 8   % Tutorial 8: Kp 15, Ti 2 s (Ki 7.5), Td 0.5 s
            cfg.kp = 15; cfg.ki = 7.5; cfg.kd = 7.5; cfg.kpp = 300; cfg.kdp = 30;
            cfg.step = 40; cfg.dist = 60; cfg.seconds = 53;
        case 9   % Tutorial 9 reference: wN 1, zeta 1 -> K = [1 2]
            cfg.k1 = 1; cfg.k2 = 2; cfg.step = 20; cfg.ulim = 800; cfg.seconds = 32;
        case 10  % Tutorial 10: LQR Q = I, R = 1 -> K = [1 1.7321]
            cfg.k1 = 1; cfg.k2 = 1.7321; cfg.step = 20; cfg.ulim = 800; cfg.seconds = 32;
        case 21  % PEND swing stop (Tutorial 3 design 1 gains), regulate until stopped
            cfg.kp = 6; cfg.kd = 4.8; cfg.kpp = 10; cfg.kdp = 5; cfg.fdr = 10; cfg.ulim = 800; cfg.seconds = 20;
        case 22  % PEND on-off control
            cfg.uon = 200; cfg.db = 0.5; cfg.step = 20; cfg.ulim = 800; cfg.seconds = 32;
        case 23  % PEND inverted LQR: Q = diag(1,1,10,1), R = 0.01, Tutorial 5 plant
            cfg.k1 = -10; cfg.k2 = -13.787; cfg.k3 = 382.789; cfg.k4 = 50.787; cfg.step = 20; cfg.seconds = 43;
            cfg.fdp = 5;   % LQR k4 on a 10 Hz rate chattered (u rms 212 vs PID 135)
        case 24  % PEND swing-up: pump 1000 deg/s^2, centring PD 4/4, exp 23 LQR catch, 720 deg/s
            cfg.uon = 1000; cfg.kp = 4; cfg.kd = 4; cfg.vmax = 720;
            cfg.k1 = -10; cfg.k2 = -13.787; cfg.k3 = 382.789; cfg.k4 = 50.787; cfg.seconds = 40; cfg.fdp = 5;
        otherwise, error('odyssix:sim', 'exp must be 1..10 or 21..24');
    end
end

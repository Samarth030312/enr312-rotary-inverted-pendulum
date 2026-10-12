function cfg = defaults(exp)
%DEFAULTS  Tutorial default configuration, identical to ENR312_Runner_Defaults.
%   cfg = odyssix.sim.defaults(exp)    exp = 1..5
    cfg = struct('exp', exp, 'kp', 0, 'kd', 0, 'kpp', 0, 'kdp', 0, 'step', 2, ...
                 'dist', 0, 'ulim', 400, 'vmax', 360, 'seconds', 20);
    switch exp
        case 1, cfg.step = 5;  cfg.seconds = 8;                         % first motion
        case 2, cfg.kp = 5; cfg.kd = 2.5; cfg.dist = 1; cfg.ulim = 400; cfg.seconds = 19.5;
        case {3, 4}, cfg.kp = 6; cfg.kd = 4.8; cfg.kpp = 10; cfg.kdp = 5; cfg.ulim = 800; cfg.seconds = 19;
        case 5, cfg.kp = 9; cfg.kd = 9; cfg.kpp = 300; cfg.kdp = 30; cfg.ulim = 1500; cfg.seconds = 25;
        otherwise, error('odyssix:sim', 'exp must be 1..5');
    end
end

function lp = loop(cfg, plant)
%LOOP  Linear outer-loop transfer function L(s) of a tutorial, and its margins.
%
%   lp = odyssix.sim.loop(cfg, plant)
%     lp.L.num/den, lp.S (sensitivity, num/den), lp.cl poles, lp.stable,
%     lp.margins (phiMdeg, GMdB, MsdB, wSC, ...), lp.zeros, lp.olPend
%
%   Structure (Tutorials 2-5), angles in degrees, G_rotor = 1/s^2:
%     T2:     L = (kd s + kp) / s^2                       (pendulum removed)
%     T3/T4:  L = (kd s + kp) den / (s^2 (den + wr2 (kdp s + kpp))),
%             den = s^2 + gamma s + wg2                    (suspended)
%     T5:     same with den = s^2 + gamma s - wg2 and the outer sign -1
%   Experiments 6-8, 21 (PID, Ki = Kp/Ti):  Krotor = (kd s^2 + kp s + ki)/s,
%     L = sgn Krotor Trotor, Trotor = den / (s^2 (den + wr2 (kdp s + kpp)))
%   Experiment 7 also: the PENDULUM loop of Tutorial 7,
%     Lpend = (kdp s + kpp) wr2 s^2 s / (den (s^3 - kd s^2 - kp s - ki))  (lp.Lpend)
%   Experiments 9, 10, 23 (state feedback): lp.cl = eig(A - B K) (no L).
%   Experiment 22 (on-off) has no linear loop: lp = [].
%   Continuous-time: the firmware's 500 Hz sampling, derivative filters,
%   quantisation and clips are NOT in L (they are in odyssix.sim.runTutorial).
    g = sqrt(plant.wg2) / plant.Q;
    if cfg.exp >= 6, lp = loopCtrl(cfg, plant, g); return; end
    kr = [cfg.kd, cfg.kp];
    if cfg.exp <= 2
        num = kr; den = [1 0 0]; lp.olPend = [];
    else
        sgn = 1; dp = [1, g, plant.wg2];
        if cfg.exp == 5, sgn = -1; dp = [1, g, -plant.wg2]; end
        inner = dp + [0, plant.wr2 * cfg.kdp, plant.wr2 * cfg.kpp];
        num = sgn * conv(kr, dp); den = conv([1 0 0], inner);
        lp.olPend = roots(dp); lp.innerPoles = roots(inner);
    end
    lp.L = struct('num', num, 'den', den);
    cl = den + [zeros(1, numel(den) - numel(num)), num];
    lp.S = struct('num', den, 'den', cl);
    lp.cl = roots(cl); lp.stable = all(real(lp.cl) < 0);
    lp.zeros = roots(num);
    lp.margins = exp005_stability_margins(struct('L', lp.L), logspace(-2, 3, 20000));
end

function lp = loopCtrl(cfg, plant, g)
    lp = struct('L', [], 'S', [], 'cl', [], 'stable', true, 'zeros', [], 'margins', [], 'olPend', []);
    e = cfg.exp;
    if any(e == [9 10 23])
        if e == 23
            [A, B] = odyssix.ctrl.pendulumModel('inverted', plant); K = [cfg.k1 cfg.k2 cfg.k3 cfg.k4];
        else
            A = [0 1; 0 -cfg.bv]; B = [0; 1]; K = [cfg.k1 cfg.k2];
        end
        lp.cl = eig(A - B * K); lp.stable = all(real(lp.cl) < 0);
        lp.olPend = eig(A);
        return;
    end
    if e == 22, lp = []; return; end
    inv = any(e == [6 7 8]);
    if inv, dp = [1, g, -plant.wg2]; sgn = -1; else, dp = [1, g, plant.wg2]; sgn = 1; end
    inner = dp + [0, plant.wr2 * cfg.kdp, plant.wr2 * cfg.kpp];
    if cfg.ki > 0
        num = sgn * conv([cfg.kd, cfg.kp, cfg.ki], dp); den = conv([1 0 0 0], inner);
    else
        num = sgn * conv([cfg.kd, cfg.kp], dp); den = conv([1 0 0], inner);
    end
    lp.L = struct('num', num, 'den', den);
    cl = den + [zeros(1, numel(den) - numel(num)), num];
    lp.S = struct('num', den, 'den', cl);
    lp.cl = roots(cl); lp.stable = all(real(lp.cl) < 0);
    lp.zeros = roots(num); lp.olPend = roots(dp); lp.innerPoles = roots(inner);
    lp.margins = exp005_stability_margins(struct('L', lp.L), logspace(-2, 3, 20000));
    if e == 7
        % Tutorial 7: the pendulum loop with the rotor loop closed (positive feedback, inverted)
        rot = [1, -cfg.kd, -cfg.kp, -cfg.ki];               % s^3 - kd s^2 - kp s - ki
        nP = conv([cfg.kdp, cfg.kpp], plant.wr2 * [1 0 0 0]); dP = conv(dp, rot);
        if cfg.ki == 0, nP = conv([cfg.kdp, cfg.kpp], plant.wr2 * [1 0 0]); dP = conv(dp, rot(1:3)); end
        lp.Lpend = struct('num', nP, 'den', dP);
        % CAUTION: Lpend has open-loop RHP poles (the upright pendulum, and the
        % sign-inverted rotor loop), so these crossover margins are NOT a
        % stability verdict (Nyquist needs the encirclement count); use lp.cl.
        lp.marginsPend = exp005_stability_margins(struct('L', lp.Lpend), logspace(-2, 3, 20000));
        lp.olUnstablePend = sum(real(roots(lp.Lpend.den)) > 0);
    end
end

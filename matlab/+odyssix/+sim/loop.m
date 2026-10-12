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
%   Continuous-time: the firmware's 500 Hz sampling, 10 Hz derivative filter,
%   quantisation and clips are NOT in L (they are in odyssix.sim.runTutorial).
    g = sqrt(plant.wg2) / plant.Q;
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

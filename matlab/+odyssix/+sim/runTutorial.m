function S = runTutorial(cfg, plant, opts)
%RUNTUTORIAL  Simulate one ENR312 tutorial exactly as the firmware runs it.
%
%   S = odyssix.sim.runTutorial(cfg, plant)
%   S = odyssix.sim.runTutorial(cfg, plant, opts)   opts.onTick as in runCtrl
%   cfg   = odyssix.sim.defaults(exp)   (exp 1..5; 6..10 and 21..23 go to
%           odyssix.sim.runCtrl, the port of the general firmware core), fields:
%           exp kp kd kpp kdp step dist ulim vmax seconds
%   plant = odyssix.sim.plant()         fields: wg2 Q wr2 nonlinear quant
%
%   A line-by-line MATLAB port of the firmware control path:
%     enr312_pd.c        PD on the error, derivative low-passed at 10 Hz
%     enr312_exp002/003/005.c   tutorial sequences, clips and abort rules
%     enr312_runner.c    u (deg/s^2) -> velocity -> step rate; speed ceiling;
%                        EXP005 alpha = wrap180(180 - psi); hold after done
%     host/enr312_plant.c nonlinear pendulum driven by the step train
%   Cross-checked against the C emulator (the firmware code itself) by
%   matlab/tests/test_sim_matches_firmware.m.
%
%   EXP001 is open loop: +step deg at 200 microsteps/s, wait, back, wait.
%
%   S: table t, rotor, psi (encoder, 0 = hanging datum), alpha (EXP005 upright
%      angle), u, ref, phase; plus S.Properties.UserData with state, abort,
%      phaseNames, cfg, plant.
%   Base MATLAB only.

    if nargin < 3, opts = struct(); end
    onTick = []; if isfield(opts, 'onTick'), onTick = opts.onTick; end
    if cfg.exp >= 6                         % general core: Tutorials 6-10, PEND
        S = odyssix.sim.runCtrl(cfg, plant, opts);
        return;
    end
    Ts = 0.002; SUB = 4; h = Ts / SUB;
    UPD = 3200 / 360;                       % microsteps per degree (C-1: may be 2x)
    ENC = 360 / 2400;                       % encoder count, deg
    d2r = pi / 180;
    N = round(cfg.seconds / Ts);

    % ---- plant ------------------------------------------------------------
    P.wg2 = plant.wg2; P.gamma = sqrt(plant.wg2) / plant.Q;
    P.wr2 = plant.wr2; if cfg.exp == 2, P.wr2 = 0; end          % pendulum removed
    psi = 0.4 * d2r; psid = 0; held = false;
    if cfg.exp == 5, psi = (180 - 0.6) * d2r; held = true; end   % operator holds it up
    pos = 0; acc = 0; vPrev = 0;

    % ---- controllers (enr312_pd.c) -------------------------------------------
    a = 1 - exp(-2 * pi * 10 * Ts);
    pdR = pdInit(cfg.kp, cfg.kd);
    pdP = pdInit(cfg.kpp, cfg.kdp);
    lim = cfg.ulim;

    % ---- sequence state -----------------------------------------------------------
    phase = 0; ptick = 0; satRun = 0; warnRun = 0; capRun = 0;
    rel5 = false; alCap = 0;                          % EXP005 release detection (C: released, alpha_capture)
    runState = 'ACTIVE'; abortWhy = 'NONE'; v = 0; vsat = 0;
    moveLeft = 0; moveDir = 1;

    [t, rot, psiO, alO, uO, refO, phO] = deal(nan(N, 1));
    for k = 1:N
        if ~isempty(onTick) && mod(k, 1000) == 0, onTick(); end
        rotor = pos / UPD;
        psiMeas = psi / d2r; if plant.quant, psiMeas = round(psi / d2r / ENC) * ENC; end   % as C
        alpha = wrap180(180 - psiMeas);           % ENR312_Runner_UprightAngle
        u = 0; ref = 0;

        switch cfg.exp
            case 1          % open loop: move, wait, move back, wait
                [phase, ptick, moveLeft, moveDir, ref] = exp001Seq(phase, ptick, moveLeft, moveDir, cfg, UPD);
            case 2
                [phase, ptick, u, ref, satRun, runState, abortWhy] = exp002(phase, ptick, rotor, satRun, runState, abortWhy);
            case {3, 4}
                [phase, ptick, u, ref, satRun, runState, abortWhy] = exp003(phase, ptick, rotor, psiMeas, satRun, runState, abortWhy);
            case 5
                [phase, ptick, u, ref, satRun, warnRun, capRun, runState, abortWhy] = ...
                    exp005(phase, ptick, rotor, alpha, satRun, warnRun, capRun, runState, abortWhy);
                if held && phase ~= 0, held = false; end      % released at capture
        end

        % ---- runner: u -> velocity ----------------------------------------------
        if cfg.exp ~= 1
            switch runState
                case 'ACTIVE'
                    v = v + u * Ts;
                    if abs(v) >= cfg.vmax
                        v = sign(v) * cfg.vmax; vsat = vsat + 1;
                        if vsat >= 100, runState = 'ABORTED'; abortWhy = 'VELOCITY_LIMIT'; v = 0; u = 0; end
                    else
                        vsat = 0;
                    end
                case 'STOPPING'
                    dv = lim * Ts; u = 0;
                    if abs(v) <= dv, v = 0; runState = 'FINISHED'; else, v = v - sign(v) * dv; end
                otherwise
                    v = 0; u = 0;
            end
            rate = v * UPD; if abs(rate) < 2, rate = 0; end
        else
            rate = 0; if moveLeft > 0, rate = 200 * moveDir; end
        end

        t(k) = (k - 1) * Ts; rot(k) = rotor; psiO(k) = psiMeas; alO(k) = alpha;
        uO(k) = u; refO(k) = ref; phO(k) = phase;
        if any(strcmp(runState, {'FINISHED', 'ABORTED'})) && k > 1 && cfg.exp ~= 5
            % keep simulating the plant at rest so the pendulum is shown settling
        end

        % ---- plant (host/enr312_plant.c) ------------------------------------------
        for i = 1:SUB
            acc = acc + abs(rate) * h; kk = floor(acc); acc = acc - kk;
            before = pos; pos = pos + sign(rate) * kk;
            if cfg.exp == 1 && moveLeft > 0
                moveLeft = moveLeft - abs(pos - before);
                if moveLeft <= 0, pos = pos - moveDir * (-moveLeft); moveLeft = 0; rate = 0; end
            end
            vr = rate / UPD * d2r;
            if held, psid = 0; elseif vr ~= vPrev, psid = psid + P.wr2 * cos(psi) * (vr - vPrev); end
            vPrev = vr;
            if ~held
                [psi, psid] = rk4(psi, psid, vr, h, P, plant.nonlinear);
            end
        end
    end
    S = table(t, rot, psiO, alO, uO, refO, phO, 'VariableNames', ...
              {'t', 'rotor', 'psi', 'alpha', 'u', 'ref', 'phase'});
    S.Properties.UserData = struct('state', runState, 'abort', abortWhy, ...
        'phaseNames', {phaseNames(cfg.exp)}, 'cfg', cfg, 'plant', plant);

    % ============================================================ nested: PD
    function pd = pdInit(kp, kd)
        pd = struct('kp', kp, 'kd', kd, 'd', 0, 'e0', 0, 'have', false);
    end
    function [pd, uu] = pdUpdate(pd, e)
        raw = 0; if pd.have, raw = (e - pd.e0) / Ts; end
        pd.d = pd.d + a * (raw - pd.d);
        uu = pd.kp * e + pd.kd * pd.d;
        pd.e0 = e; pd.have = true;
    end

    % ============================================================ nested: cores
    function [ph, pt, uu, R, sr, st, why] = exp002(ph, pt, y, sr, st, why)
        R = 0; D = 0; dur = [500 3000 1500 3000 1500];
        if ph == 1, R = cfg.step; end
        if ph == 3, D = cfg.dist; end
        [pdR, un] = pdUpdate(pdR, R - y);
        us = min(max(un, -lim), lim);
        uu = us + D;
        if strcmp(st, 'ACTIVE') && ph < 5
            if us ~= un, sr = sr + 1; else, sr = 0; end
            if sr >= 250, st = 'ABORTED'; why = 'SATURATION'; ph = 6; end
            if abs(y) > 240, st = 'ABORTED'; why = 'ROTOR_LIMIT'; ph = 6; end
        end
        if ph < 5 && pt >= dur(ph + 1), ph = ph + 1; pt = 0; end
        pt = pt + 1;                                  % C: phase_tick++ after advance
        if ph == 5 && strcmp(st, 'ACTIVE'), st = 'STOPPING'; end
        if ph >= 5, uu = 0; end
        if strcmp(st, 'ABORTED'), uu = 0; end
    end

    function [ph, pt, uu, R, sr, st, why] = exp003(ph, pt, y, p, sr, st, why)
        R = 0; dur = [500 7500 1500];
        if ph == 1, R = cfg.step; end
        [pdR, ur] = pdUpdate(pdR, R - y);
        [pdP, up] = pdUpdate(pdP, 0 - p);
        uu = min(max(ur + up, -lim), lim); clipped = uu ~= ur + up;
        if strcmp(st, 'ACTIVE') && ph < 3
            if abs(y) > 240, st = 'ABORTED'; why = 'ROTOR_LIMIT'; ph = 4;
            elseif abs(p) > 120, st = 'ABORTED'; why = 'PENDULUM_LIMIT'; ph = 4;
            else
                if clipped, sr = sr + 1; else, sr = 0; end
                if sr >= 250, st = 'ABORTED'; why = 'SATURATION'; ph = 4; end
            end
        end
        if ph < 3 && pt >= dur(ph + 1), ph = ph + 1; pt = 0; end
        pt = pt + 1;
        if ph == 3 && strcmp(st, 'ACTIVE'), st = 'STOPPING'; end
        if ph >= 3 || strcmp(st, 'ABORTED'), uu = 0; end
    end

    function [ph, pt, uu, R, sr, wr, cr, st, why] = exp005(ph, pt, y, al, sr, wr, cr, st, why)
        if ph == 1 && ~rel5 && abs(al - alCap) >= 1.5 % C: EXP005_RELEASE_DEG, motor still until then
            rel5 = true; pt = 0;
        end
        controlling = (ph == 1 && rel5) || any(ph == [2 3 4]);   % 4 = DONE, held
        wasDone = (ph == 4);
        R = 0; if ph == 2, R = cfg.step; end
        [pdR, ur] = pdUpdate(pdR, R - y);
        [pdP, up] = pdUpdate(pdP, 0 - al);
        uu = 0; clipped = false;
        if controlling
            uu = -ur + up;
            if uu > lim, uu = lim; clipped = true; elseif uu < -lim, uu = -lim; clipped = true; end
        end
        if ph ~= 5
            if abs(al) > 15, ph = 5; st = 'ABORTED'; why = 'PENDULUM_LOST';
            elseif abs(y) > 240, ph = 5; st = 'ABORTED'; why = 'ROTOR_LIMIT';
            else
                if controlling && abs(al) > 10, wr = wr + 1;
                    if wr >= 50, ph = 5; st = 'ABORTED'; why = 'PENDULUM_LOST'; end
                else, wr = 0; end
                if controlling && clipped, sr = sr + 1;
                    if sr >= 100, ph = 5; st = 'ABORTED'; why = 'SATURATION'; end
                else, sr = 0; end
            end
        end
        switch ph
            case 0
                if abs(al) <= 2, cr = cr + 1; if cr >= 500, alCap = al; rel5 = false; ph = 1; pt = 0; end, else, cr = 0; end
            case 1, if rel5 && pt >= 1000, ph = 2; pt = 0; end
            case 2, if pt >= 5000, ph = 3; pt = 0; end
            case 3, if pt >= 1500, ph = 4; pt = 0; end
        end
        pt = pt + 1;
        if ph == 5, uu = 0; end
        if ph == 4 && ~wasDone, uu = 0; end           % C: one tick of u = 0 entering HOLD
    end

    function [ph, pt, ml, md, R] = exp001Seq(ph, pt, ml, md, c, upd)
        % 0 hold 1 s | 1 move +step | 2 wait 3 s | 3 move back | 4 wait 3 s | 5 done
        R = 0; if any(ph == [1 2]), R = c.step; end
        switch ph
            case 0, if pt >= 500, ph = 1; pt = 0; ml = round(abs(c.step) * upd); md = sign(c.step + eps); end
            case 1, if ml <= 0, ph = 2; pt = 0; end
            case 2, if pt >= 1500, ph = 3; pt = 0; ml = round(abs(c.step) * upd); md = -sign(c.step + eps); end
            case 3, if ml <= 0, ph = 4; pt = 0; end
            case 4, if pt >= 1500, ph = 5; pt = 0; end
        end
        pt = pt + 1;
    end
end

function [p, pd] = rk4(p, pd, vr, h, P, nonlinear)
    f = @(q, qd) -P.wg2 * sinOrLin(q, nonlinear) + vr^2 * sinOrLin(q, nonlinear) * cosOrOne(q, nonlinear) - P.gamma * qd;
    k1a = pd;            k1b = f(p, pd);
    k2a = pd + h/2*k1b;  k2b = f(p + h/2*k1a, pd + h/2*k1b);
    k3a = pd + h/2*k2b;  k3b = f(p + h/2*k2a, pd + h/2*k2b);
    k4a = pd + h*k3b;    k4b = f(p + h*k3a, pd + h*k3b);
    p  = p  + h/6 * (k1a + 2*k2a + 2*k3a + k4a);
    pd = pd + h/6 * (k1b + 2*k2b + 2*k3b + k4b);
end

function s = sinOrLin(q, nonlinear)
    if nonlinear, s = sin(q); return; end
    % linear about the nearer equilibrium (hanging 0 or upright pi)
    if abs(wrapPi(q - pi)) < pi/2, s = -(wrapPi(q - pi)); else, s = wrapPi(q); end
end
function c = cosOrOne(q, nonlinear)
    if nonlinear, c = cos(q); elseif abs(wrapPi(q - pi)) < pi/2, c = -1; else, c = 1; end
end
function x = wrapPi(x), x = mod(x + pi, 2*pi) - pi; end
function a = wrap180(a)
%WRAP180  ENR312_Runner_UprightAngle's wrap, bit-for-bit (fmod keeps the sign).
    a = rem(a, 360);
    if a > 180, a = a - 360; end
    if a <= -180, a = a + 360; end
end

function n = phaseNames(e)
    switch e
        case 1, n = {'HOLD', 'MOVE_OUT', 'WAIT', 'MOVE_BACK', 'WAIT', 'DONE'};
        case 2, n = {'IDLE', 'REF_STEP', 'REF_SETTLE', 'DIST_STEP', 'DIST_SETTLE', 'DONE', 'ABORTED'};
        case {3, 4}, n = {'IDLE', 'ROTOR_STEP', 'SETTLE', 'DONE', 'ABORTED'};
        otherwise, n = {'WAIT_CAPTURE', 'BALANCE', 'ROTOR_STEP', 'SETTLE', 'HOLD', 'ABORTED'};
    end
end

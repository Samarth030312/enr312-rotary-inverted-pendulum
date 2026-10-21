function S = runCtrl(cfg, plant, opts)
%RUNCTRL  Simulate experiments 6-10 and 21-23 exactly as the firmware runs them.
%
%   S = odyssix.sim.runCtrl(cfg, plant)
%   S = odyssix.sim.runCtrl(cfg, plant, opts)
%   cfg    odyssix.sim.defaults(exp), exp in 6..10 or 21..23
%   plant  odyssix.sim.plant(): wg2 Q wr2 nonlinear quant
%   opts   (all optional)
%     psi0      initial encoder angle [deg]; default 0.4 (hanging), 179.4 for
%               experiments that start upright (6, 7, 8, 23)
%     release   seconds the operator's hand keeps holding after capture (0)
%     events    struct array with fields t, key, val: at time t send '$key=val'
%               (key 'ref' = live set-point; any gain name = live gain change)
%     taps      [t v; ...] add v deg/s to the pendulum rate at time t
%
%   A line-by-line port of firmware/enr312/src/enr312_ctrl.c (the controller),
%   enr312_runner.c (u -> velocity -> step rate) and host/enr312_host_rig.c
%   (board-level limits, the operator's hand, the plant). Floating-point
%   operations are in the same order as the C code;
%   matlab/tests/test_sim_matches_firmware.m compares the two.
%
%   S: table t, rotor, psi, alpha, u, ref, phase, pend_ref; UserData as runTutorial.
    if nargin < 3, opts = struct(); end
    Ts = 0.002; SUB = 4; h = Ts / SUB;
    UPD = 3200 / 360; ENC = 360 / 2400; d2r = pi / 180;
    N = round(cfg.seconds / Ts);
    inv = any(cfg.exp == [6 7 8 23]);
    capture = inv;
    sf = any(cfg.exp == [9 10 23]);

    % ---- plant (host/enr312_plant.c) ---------------------------------------
    P.wg2 = plant.wg2; P.gamma = sqrt(plant.wg2) / plant.Q; P.wr2 = plant.wr2;
    psi0 = 0.4; if capture, psi0 = 179.4; end
    if isfield(opts, 'psi0'), psi0 = opts.psi0; end
    psi = psi0 * d2r; psid = 0; held = capture;
    holdAfter = 0; if isfield(opts, 'release'), holdAfter = round(opts.release / Ts); end
    pos = 0; acc = 0; vPrev = 0;
    events = struct('t', {}, 'key', {}, 'val', {}); if isfield(opts, 'events'), events = opts.events; end
    taps = zeros(0, 2); if isfield(opts, 'taps'), taps = opts.taps; end
    evDone = false(1, numel(events)); tapDone = false(1, size(taps, 1));

    % ---- controller state (ENR312_Ctrl_Init) --------------------------------
    c = cfg;
    if inv, phase = 0; elseif cfg.exp == 21, phase = 10; else, phase = 9; end
    abortWhy = 'NONE'; ptick = 0; capRun = 0; warnRun = 0; satRun = 0; aCap = 0;
    refLive = 0; refNow = 0;
    ir = 0; erPrev = 0; dr = 0; rHave = false;
    epPrev = 0; dp = 0; pHave = false;
    psiPrev = 0; dpsi = 0; psiHave = false;
    maBuf = zeros(1, 32); maN = 0; maI = 0; maSum = 0;
    divCount = 0; uHold = 0;
    ulimRun = cfg.ulim; vmaxRun = cfg.vmax;

    % ---- runner -----------------------------------------------------------------
    runState = 'ACTIVE'; v = 0; vsat = 0; runAbort = 'NONE';
    [t, rot, psiO, alO, uO, refO, phO, prO] = deal(nan(N, 1));
    ref = 0; pendRef = 0; aMeas = 0;
    for k = 1:N
        tk = (k - 1) * Ts;
        % batch events: before the tick, as host/enr312_host_rig.c
        for i = find(~evDone)
            if tk + 1e-9 >= events(i).t
                evDone(i) = true;
                applyEvent(events(i));
            end
        end
        for i = find(~tapDone)
            if tk + 1e-9 >= taps(i, 1), tapDone(i) = true; psid = psid + taps(i, 2) * pi / 180; end
        end

        rotor = pos / UPD;
        psiMeas = psi / d2r; if plant.quant, psiMeas = round(psi / d2r / ENC) * ENC; end
        u = 0;

        % board-level limits (control_tick in the emulator, before the runner)
        moving = any(strcmp(runState, {'ACTIVE', 'STOPPING'}));
        if moving && ~inv && abs(psiMeas) > 120, runState = 'ABORTED'; runAbort = 'OPERATOR'; v = 0; end
        if abs(rotor) > 240 && any(strcmp(runState, {'ACTIVE', 'STOPPING'})), runState = 'ABORTED'; runAbort = 'OPERATOR'; v = 0; end

        if strcmp(runState, 'ACTIVE')
            u = ctrlTick(rotor, v, psiMeas);
            if phase == 13
                runState = 'ABORTED'; runAbort = abortWhy; v = 0; u = 0;
            elseif phase == 12
                runState = 'STOPPING';
            end
        end
        switch runState
            case 'ACTIVE'
                v = v + u * Ts;
                if abs(v) >= vmaxRun
                    v = sign(v) * vmaxRun; vsat = vsat + 1;
                    if vsat >= 100, runState = 'ABORTED'; runAbort = 'VELOCITY_LIMIT'; v = 0; u = 0; end
                else
                    vsat = 0;
                end
            case 'STOPPING'
                dv = ulimRun * Ts; u = 0;
                if abs(v) <= dv, v = 0; runState = 'FINISHED'; else, v = v - sign(v) * dv; end
            otherwise
                v = 0; u = 0;
        end
        rate = v * UPD; if abs(rate) < 2, rate = 0; end

        % the operator's hand: holds until captured (+ release delay)
        if held && any(strcmp(runState, {'ACTIVE', 'STOPPING'})) && phase ~= 0
            if holdAfter > 0, holdAfter = holdAfter - 1; else, held = false; end
        end

        t(k) = tk; rot(k) = rotor; psiO(k) = psiMeas; alO(k) = wrap180(180 - psiMeas);
        uO(k) = u; refO(k) = ref; phO(k) = phase; prO(k) = pendRef;

        for i = 1:SUB
            acc = acc + abs(rate) * h; kk = floor(acc); acc = acc - kk;
            pos = pos + sign(rate) * kk;
            vr = rate / UPD * d2r;
            if held, psid = 0; elseif vr ~= vPrev, psid = psid + P.wr2 * cos(psi) * (vr - vPrev); end
            vPrev = vr;
            if ~held, [psi, psid] = rk4(psi, psid, vr, h, P, plant.nonlinear); end
        end
    end
    S = table(t, rot, psiO, alO, uO, refO, phO, prO, 'VariableNames', ...
              {'t', 'rotor', 'psi', 'alpha', 'u', 'ref', 'phase', 'pend_ref'});
    S.Properties.UserData = struct('state', runState, 'abort', runAbort, ...
        'phaseNames', {phaseNames()}, 'cfg', cfg, 'plant', plant);

    % ================================================ ENR312_Ctrl_Tick
    function uOut = ctrlTick(theta, thetadot, p)
        % moving average on the encoder angle
        if maN == c.ma, maSum = maSum - maBuf(maI + 1); else, maN = maN + 1; end
        maBuf(maI + 1) = p;
        maSum = maSum + p;
        maI = mod(maI + 1, c.ma);
        psiF = maSum / maN;
        aRaw = p; if inv, aRaw = wrap180(180 - p); end
        aF = psiF; if inv, aF = wrap180(180 - psiF); end

        if phase == 1 && abs(aRaw - aCap) >= 1.5, advance(2); end

        step = 0; if phase == 3, step = c.step; end
        r = step;
        if phase == 8 || phase == 10
            d = refLive - refNow; lim = c.rrate * Ts;
            if c.rrate > 0 && d > lim, d = lim; end
            if c.rrate > 0 && d < -lim, d = -lim; end
            refNow = refNow + d;
            r = refNow;
        end
        pr = 0;
        if phase == 7 && mod(ptick, 2500) >= 2500 - 2, pr = c.imp; end
        dist = 0; if phase == 5, dist = c.dist; end

        ctl = ~any(phase == [0 1 12 13]);
        uUnsat = 0;
        if ~ctl
            divCount = 0; uHold = 0;
        elseif divCount == 0
            dt = Ts * c.div;
            rawd = 0; if psiHave, rawd = (psiF - psiPrev) / dt; end
            dpsi = dpsi + lpAlpha(c.fdp, dt) * (rawd - dpsi);
            psiPrev = psiF; psiHave = true;
            adot = dpsi; if inv, adot = -dpsi; end
            if sf
                uRot = -(c.k1 * (theta - r) + c.k2 * thetadot);
                uPen = -(c.k3 * aF + c.k4 * adot);
                uUnsat = uRot + uPen - c.bv * thetadot;
            elseif cfg.exp == 22
                e = r - theta;
                if e > c.db, uUnsat = c.uon; elseif e < -c.db, uUnsat = -c.uon; else, uUnsat = 0; end
            else
                er = r - theta;
                der = 0; if rHave, der = (er - erPrev) / dt; end
                dr = dr + lpAlpha(c.fdr, dt) * (der - dr);
                erPrev = er; rHave = true;
                ur = c.kp * er + c.kd * dr + ir;
                ep = pr - aF;
                dep = 0; if pHave, dep = (ep - epPrev) / dt; end
                dp = dp + lpAlpha(c.fdp, dt) * (dep - dp);
                epPrev = ep; pHave = true;
                up = c.kpp * ep + c.kdp * dp;
                uRot = ur; if inv, uRot = -ur; end
                uUnsat = uRot + up;
                if c.ki > 0 && abs(uUnsat) < c.ulim
                    ir = ir + c.ki * er * dt;
                    ir = min(max(ir, -c.ulim), c.ulim);
                end
            end
            uHold = uUnsat;
            divCount = c.div - 1;
        else
            divCount = divCount - 1;
            uUnsat = uHold;
        end
        uu = min(max(uUnsat, -c.ulim), c.ulim);
        clipped = ctl && (uu ~= uUnsat);
        if ctl, uu = uu + dist; end

        if ~any(phase == [12 13])
            if abs(theta) > 240
                advance(13); abortWhy = 'ROTOR_LIMIT';
            elseif inv && abs(aRaw) > 15
                advance(13); abortWhy = 'PENDULUM_LOST';
            else
                if inv && ctl && abs(aRaw) > 10
                    warnRun = warnRun + 1;
                    if warnRun >= 50, advance(13); abortWhy = 'PENDULUM_LOST'; end
                else
                    warnRun = 0;
                end
                if clipped && cfg.exp ~= 22
                    satRun = satRun + 1;
                    if satRun >= 100, advance(13); abortWhy = 'SATURATION'; end
                else
                    satRun = 0;
                end
            end
        end
        if phase == 13, uu = 0; end

        switch phase
            case 0
                if abs(aRaw) <= 2
                    capRun = capRun + 1;
                    if capRun >= 500, aCap = aRaw; advance(1); end
                else
                    capRun = 0;
                end
            case 2                      % T_BALANCE = 5 s
                if ptick >= 2500
                    if cfg.exp == 7, advance(7); else, advance(3); end
                end
            case 9, if ptick >= 500, advance(3); end
            case 3
                if ptick >= tStep(), advance(4); end
            case 4
                if ptick >= tStep()
                    if cfg.exp == 8, advance(5); elseif inv, advance(8); else, advance(12); end
                end
            case 5, if ptick >= 5000, advance(6); end
            case 6, if ptick >= 5000, advance(8); end
            case 7, if ptick >= 2500 * 8, advance(8); end
        end
        ptick = ptick + 1;
        ref = r; pendRef = pr; aMeas = aF;
        uOut = uu;
    end

    function advance(p), phase = p; ptick = 0; end
    function n = tStep(), if cfg.exp == 8, n = 5000; else, n = 7500; end, end

    function applyEvent(ev)
        moving = any(strcmp(runState, {'ACTIVE', 'STOPPING'}));
        if strcmp(ev.key, 'ref')
            if moving, refLive = ev.val; end
            return;
        end
        live = {'kp', 'ki', 'kd', 'kpp', 'kdp', 'fdr', 'fdp', 'k1', 'k2', 'k3', 'k4', 'bv', ...
                'uon', 'db', 'ulim', 'rrate', 'dist', 'div', 'vmax'};
        cfg.(ev.key) = ev.val;
        if moving && any(strcmp(ev.key, live))
            c.(ev.key) = ev.val;
            if strcmp(ev.key, 'ulim'), ulimRun = ev.val; end
            if strcmp(ev.key, 'vmax'), vmaxRun = ev.val; end
        elseif moving && strcmp(ev.key, 'ma') && ev.val ~= c.ma
            c.ma = ev.val; maN = 0; maI = 0; maSum = 0;
        end
    end
end

function a = lpAlpha(fc, dt)
    if fc <= 0, a = 1; return; end
    a = 1 - exp(-2 * pi * fc * dt);
    a = min(max(a, 0), 1);
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
    if abs(wrapPi(q - pi)) < pi/2, s = -(wrapPi(q - pi)); else, s = wrapPi(q); end
end
function c = cosOrOne(q, nonlinear)
    if nonlinear, c = cos(q); elseif abs(wrapPi(q - pi)) < pi/2, c = -1; else, c = 1; end
end
function x = wrapPi(x), x = mod(x + pi, 2*pi) - pi; end
function a = wrap180(a)
    a = rem(a, 360);
    if a > 180, a = a - 360; end
    if a <= -180, a = a + 360; end
end
function n = phaseNames()
    n = {'WAIT_CAPTURE', 'WAIT_RELEASE', 'BALANCE', 'STEP', 'STEP_BACK', 'DIST', 'DIST_OFF', ...
         'IMPULSES', 'HOLD', 'IDLE', 'REGULATE', '-', 'DONE', 'ABORTED'};
end

classdef Enr312Firmware < handle
%ENR312FIRMWARE  The firmware's control loop, one 2 ms tick per call, for Simulink.
%
%   fw = Enr312Firmware(P);  [v, u, phase, ref, held] = fw.tick(rotor, psiMeas)
%
%   rotor     arm angle the board knows (microsteps, deg)
%   psiMeas   encoder angle (deg, 0 = hanging datum)
%   v         arm velocity for the next 2 ms (deg/s): what the step generator runs
%   u         plant input the controller asked for (deg/s^2)
%   phase     the experiment's phase (the numbers of the firmware)
%   ref       arm set-point (deg)
%   held      true while the operator's hand holds the pendulum (upright start)
%
%   The same arithmetic, in the same order, as the MATLAB twin of the firmware:
%   odyssix.sim.runTutorial (experiments 1-5: enr312_exp00x.c, enr312_pd.c) and
%   odyssix.sim.runCtrl (6-10, 21-24: enr312_ctrl.c), with the runner
%   (enr312_runner.c) and the board limits of host/enr312_host_rig.c. Only the
%   plant is left out: in Simulink it is the continuous part of the model.
%   matlab/tests/test_simulink_matches_runctrl.m checks the two against each other.
%   P.safety = false switches off the controller's own stop rules (pendulum lost,
%   saturation, arm limit), to see what the control law alone can do; the firmware
%   on the rig always has them.

    properties
        P; cfg; c; exp; inv; capture; sf
        Ts = 0.002; UPD = 3200 / 360
        k = 0
        phase = 0; ptick = 0
        runState = 'ACTIVE'; runAbort = 'NONE'; abortWhy = 'NONE'
        v = 0; vsat = 0; held = false; holdAfter = 0
        ulimRun; vmaxRun
        % general core (enr312_ctrl.c)
        swDelta = 0; swDpsiPrev = 0; swEpeak = 0; swOver = false; swAmpPrev = 180
        swE = 0; homePending = false; trim = 0
        capRun = 0; warnRun = 0; satRun = 0; aCap = 0
        refLive = 0; refNow = 0
        ir = 0; erPrev = 0; dr = 0; rHave = false
        epPrev = 0; dp = 0; pHave = false
        psiPrev = 0; dpsi = 0; psiHave = false
        maBuf = zeros(1, 32); maN = 0; maI = 0; maSum = 0
        divCount = 0; uHold = 0
        evList = zeros(0, 2); evDone = false(1, 0)
        % tutorial cores (enr312_pd.c, enr312_exp00x.c)
        pdR; pdP; a10; rel5 = false; alCap = 0; moveLeft = 0; moveDir = 1
    end

    methods
        function o = Enr312Firmware(P)
            o.P = P; o.exp = P.exp;
            o.cfg = enr312_simulink_cfg(P); o.c = o.cfg;
            o.inv = any(o.exp == [6 7 8 23 24]);
            o.capture = any(o.exp == [6 7 8 23]);
            o.sf = any(o.exp == [9 10 23 24]);
            o.ulimRun = o.cfg.ulim; o.vmaxRun = o.cfg.vmax;
            if o.exp >= 6
                if o.exp == 24, o.phase = 11; elseif o.inv, o.phase = 0;
                elseif o.exp == 21 || o.cfg.seq == 0, o.phase = 10; else, o.phase = 9; end
                if o.cfg.amp >= 179, o.swDelta = 0.15; end
                o.swAmpPrev = o.cfg.amp;
                o.held = o.capture;
            else
                o.a10 = 1 - exp(-2 * pi * 10 * o.Ts);
                o.pdR = struct('kp', o.cfg.kp, 'kd', o.cfg.kd, 'd', 0, 'e0', 0, 'have', false);
                o.pdP = struct('kp', o.cfg.kpp, 'kd', o.cfg.kdp, 'd', 0, 'e0', 0, 'have', false);
                o.held = (o.exp == 5);
            end
            if isfield(P, 'release'), o.holdAfter = round(P.release / o.Ts); end
            if isfield(P, 'startBalancing') && P.startBalancing && o.inv
                o.phase = 8; o.held = false;                  % already balancing: skip capture
            end
            if isfield(P, 'refEvents') && ~isempty(P.refEvents)
                o.evList = P.refEvents; o.evDone = false(1, size(P.refEvents, 1));
            end
        end

        function [vOut, u, phase, ref, held] = tick(o, rotor, psiMeas)
            tk = o.k * o.Ts; o.k = o.k + 1;
            if ~o.P.closedLoop
                vOut = 0; u = 0; phase = o.phase; ref = 0; held = false; o.held = false; return;
            end
            if o.exp >= 6
                [vOut, u, ref] = o.tickCtrl(tk, rotor, psiMeas);
            else
                [vOut, u, ref] = o.tickTutorial(rotor, psiMeas);
            end
            phase = o.phase; held = o.held;
        end
    end

    methods (Access = private)
        % ================================================ experiments 6-10, 21-24 (runCtrl)
        function [vOut, u, ref] = tickCtrl(o, tk, rotor, psiMeas)
            for i = find(~o.evDone)
                if tk + 1e-9 >= o.evList(i, 1)
                    o.evDone(i) = true;
                    if any(strcmp(o.runState, {'ACTIVE', 'STOPPING'})), o.refLive = o.evList(i, 2); o.homePending = false; end
                end
            end
            u = 0;
            moving = any(strcmp(o.runState, {'ACTIVE', 'STOPPING'}));
            if moving && ~o.inv && abs(wrap180(psiMeas)) > 120, o.runState = 'ABORTED'; o.runAbort = 'OPERATOR'; o.v = 0; end
            if abs(rotor) > 240 && any(strcmp(o.runState, {'ACTIVE', 'STOPPING'})), o.runState = 'ABORTED'; o.runAbort = 'OPERATOR'; o.v = 0; end
            ref = 0;
            if strcmp(o.runState, 'ACTIVE')
                [u, ref] = o.ctrlTick(rotor, o.v, psiMeas);
                if o.phase == 13
                    o.runState = 'ABORTED'; o.runAbort = o.abortWhy; o.v = 0; u = 0;
                elseif o.phase == 12
                    o.runState = 'STOPPING';
                end
            end
            u = o.runner(u, o.ulimRun, o.vmaxRun);
            vOut = o.rateOut();
            if o.held && any(strcmp(o.runState, {'ACTIVE', 'STOPPING'})) && o.phase ~= 0
                if o.holdAfter > 0, o.holdAfter = o.holdAfter - 1; else, o.held = false; end
            end
        end

        function u = runner(o, u, lim, vmax)
            switch o.runState
                case 'ACTIVE'
                    o.v = o.v + u * o.Ts;
                    if abs(o.v) >= vmax
                        o.v = sign(o.v) * vmax; o.vsat = o.vsat + 1;
                        if o.vsat >= 100, o.runState = 'ABORTED'; o.runAbort = 'VELOCITY_LIMIT'; o.v = 0; u = 0; end
                    else
                        o.vsat = 0;
                    end
                case 'STOPPING'
                    dv = lim * o.Ts; u = 0;
                    if abs(o.v) <= dv, o.v = 0; o.runState = 'FINISHED'; else, o.v = o.v - sign(o.v) * dv; end
                otherwise
                    o.v = 0; u = 0;
            end
        end

        function vOut = rateOut(o)
            rate = o.v * o.UPD; if abs(rate) < 2, rate = 0; end      % the step generator's floor
            vOut = rate / o.UPD;
        end

        function [uOut, r] = ctrlTick(o, theta, thetadot, p)
            c = o.c; Ts = o.Ts; inv = o.inv;
            if o.maN == c.ma, o.maSum = o.maSum - o.maBuf(o.maI + 1); else, o.maN = o.maN + 1; end
            o.maBuf(o.maI + 1) = p;
            o.maSum = o.maSum + p;
            o.maI = mod(o.maI + 1, c.ma);
            psiF = o.maSum / o.maN;
            aRaw = wrap180(p); if inv, aRaw = wrap180(180 - p); end
            aF = wrap180(psiF); if inv, aF = wrap180(180 - psiF); end
            if inv && o.phase == 8, o.trim = o.trim + (aF - o.trim) * Ts / 8.0; end
            aC = aF; if inv, aC = aF - o.trim; end

            if o.phase == 1 && abs(aRaw - o.aCap) >= 1.5
                if c.seq == 0, o.advance(8); else, o.advance(2); end
            end
            step = 0; if o.phase == 3, step = c.step; end
            r = step;
            if o.phase == 8 || o.phase == 10
                d = o.refLive - o.refNow; lim = c.rrate * Ts;
                if c.rrate > 0 && d > lim, d = lim; end
                if c.rrate > 0 && d < -lim, d = -lim; end
                o.refNow = o.refNow + d;
                r = o.refNow;
            end
            pr = 0;
            if o.phase == 7 && mod(o.ptick, 2500) >= 2500 - 2, pr = c.imp; end
            dist = 0; if o.phase == 5, dist = c.dist; end

            ctl = ~any(o.phase == [0 1 12 13]);
            if ~ctl
                o.divCount = 0; o.uHold = 0; uUnsat = 0;
            elseif o.divCount == 0
                dt = Ts * c.div;
                rawd = 0; if o.psiHave, rawd = (psiF - o.psiPrev) / dt; end
                o.dpsi = o.dpsi + lpAlpha(c.fdp, dt) * (rawd - o.dpsi);
                o.psiPrev = psiF; o.psiHave = true;
                adot = o.dpsi; if inv, adot = -o.dpsi; end
                if o.phase == 11
                    uUnsat = o.energy(theta, thetadot, psiF, aRaw);
                elseif o.sf
                    uRot = -(c.k1 * (theta - r) + c.k2 * thetadot);
                    uPen = -(c.k3 * aC + c.k4 * adot);
                    uUnsat = uRot + uPen - c.bv * thetadot;
                elseif o.exp == 22
                    e = r - theta;
                    if e > c.db, uUnsat = c.uon; elseif e < -c.db, uUnsat = -c.uon; else, uUnsat = 0; end
                else
                    er = r - theta;
                    der = 0; if o.rHave, der = (er - o.erPrev) / dt; end
                    o.dr = o.dr + lpAlpha(c.fdr, dt) * (der - o.dr);
                    o.erPrev = er; o.rHave = true;
                    ur = c.kp * er + c.kd * o.dr + o.ir;
                    ep = pr - aC;
                    dep = 0; if o.pHave, dep = (ep - o.epPrev) / dt; end
                    o.dp = o.dp + lpAlpha(c.fdp, dt) * (dep - o.dp);
                    o.epPrev = ep; o.pHave = true;
                    up = c.kpp * ep + c.kdp * o.dp;
                    uRot = ur; if inv, uRot = -ur; end
                    uUnsat = uRot + up;
                    if c.ki > 0 && abs(uUnsat) < c.ulim
                        o.ir = o.ir + c.ki * er * dt;
                        o.ir = min(max(o.ir, -c.ulim), c.ulim);
                    end
                end
                o.uHold = uUnsat;
                o.divCount = c.div - 1;
            else
                o.divCount = o.divCount - 1;
                uUnsat = o.uHold;
            end
            uu = min(max(uUnsat, -c.ulim), c.ulim);
            clipped = ctl && (uu ~= uUnsat);
            if ctl, uu = uu + dist; end

            if ~any(o.phase == [12 13]) && o.P.safety
                if abs(theta) > 240
                    o.advance(13); o.abortWhy = 'ROTOR_LIMIT';
                elseif o.phase == 11
                    o.warnRun = 0; o.satRun = 0;
                elseif inv && abs(aRaw) > 15
                    o.advance(13); o.abortWhy = 'PENDULUM_LOST';
                else
                    if inv && ctl && abs(aRaw) > 10
                        o.warnRun = o.warnRun + 1;
                        if o.warnRun >= 50, o.advance(13); o.abortWhy = 'PENDULUM_LOST'; end
                    else
                        o.warnRun = 0;
                    end
                    catching = o.exp == 24 && o.phase == 8 && o.ptick < 250;
                    satTicks = 100; if inv && o.phase == 8, satTicks = 250; end
                    if clipped && o.exp ~= 22 && ~catching
                        o.satRun = o.satRun + 1;
                        if o.satRun >= satTicks, o.advance(13); o.abortWhy = 'SATURATION'; end
                    else
                        o.satRun = 0;
                    end
                end
            end
            if o.phase == 13, uu = 0; end

            switch o.phase
                case 11
                    adotc = -o.dpsi;
                    slowc = abs(o.dpsi) <= 60.0;
                    appr = abs(aRaw) >= 2.0 && aRaw * adotc < 0.0 && abs(o.dpsi) <= 100.0;
                    uc = c.k2 * thetadot + c.k3 * aRaw + c.k4 * adotc;
                    feas = abs(uc) <= 2.0 * c.ulim;
                    if c.amp >= 179.0 && abs(aRaw) <= 7.0 && (slowc || appr) && feas && o.swE >= 1.8
                        o.refNow = theta; o.refLive = theta; o.homePending = true; o.advance(8);
                    elseif c.amp >= 179.0 && o.ptick >= 20000
                        o.advance(12);
                    end
                case 8
                    if o.homePending && o.ptick >= 1000, o.refLive = 0; o.homePending = false; end
                case 0
                    if abs(aRaw) <= 2
                        o.capRun = o.capRun + 1;
                        if o.capRun >= 500, o.aCap = aRaw; o.advance(1); end
                    else
                        o.capRun = 0;
                    end
                case 2
                    if o.ptick >= 2500
                        if o.exp == 7, o.advance(7); else, o.advance(3); end
                    end
                case 9, if o.ptick >= 500, o.advance(3); end
                case 3, if o.ptick >= o.tStep(), o.advance(4); end
                case 4
                    if o.ptick >= o.tStep()
                        if o.exp == 8, o.advance(5); elseif inv, o.advance(8); else, o.advance(12); end
                    end
                case 5, if o.ptick >= 5000, o.advance(6); end
                case 6, if o.ptick >= 5000, o.advance(8); end
                case 7, if o.ptick >= 2500 * 8, o.advance(8); end
            end
            o.ptick = o.ptick + 1;
            uOut = uu;
        end

        function uUnsat = energy(o, theta, thetadot, psiF, aRaw)
            % energy control, enr312_ctrl.c, same operation order as runCtrl
            c = o.c;
            upr = c.amp >= 179.0;
            if upr, hstar = 2.0; else, hstar = 1.0 - cos(c.amp * pi / 180.0); end
            if c.amp ~= o.swAmpPrev
                if upr, o.swDelta = 0.15; else, o.swDelta = 0.0; end
                o.swEpeak = 0; o.swAmpPrev = c.amp;
            end
            prr = psiF * pi / 180.0; pdr = o.dpsi * pi / 180.0;
            en = pdr * pdr / (2.0 * c.wg2) + 1.0 - cos(prr);
            dirv = pdr * cos(prr);
            if dirv > 0, sg = 1; elseif dirv < 0, sg = -1; else, sg = 0; end
            if sg == 0 && en < 0.05, sg = 1; end
            if en > o.swEpeak, o.swEpeak = en; end
            if o.dpsi * o.swDpsiPrev < 0
                happ = 1.0 - cos(prr);
                if upr
                    if cos(prr) < 0.0 && o.swEpeak >= 2.0 + o.swDelta - 0.1
                        o.swDelta = o.swDelta + 0.5 * (2.0 - happ);
                    end
                elseif hstar > 0.0 && o.swEpeak >= 0.8 * (hstar + o.swDelta)
                    o.swDelta = o.swDelta + 0.5 * (hstar - happ);
                end
                o.swEpeak = 0;
            end
            if upr && abs(aRaw) < 5.0 && abs(o.dpsi) > 100.0 && ~o.swOver
                o.swDelta = o.swDelta - 1.0 * (en - 2.0);
                o.swOver = true;
            end
            if abs(aRaw) > 30.0, o.swOver = false; end
            lo = -0.3;                                          % CTRL_SW_DELTA_MIN
            if o.swDelta < lo, o.swDelta = lo; elseif o.swDelta > 0.6, o.swDelta = 0.6; end
            o.swDpsiPrev = o.dpsi;
            et = hstar + o.swDelta;
            if upr
                upp = c.uon * min(max(10.0 * (et - en), -1), 1) * sg;
            else
                upp = c.uon * min(max(5.0 * (et - en) * pdr * cos(prr) / sqrt(c.wg2), -1), 1);
            end
            if abs(thetadot) > 0.8 * c.vmax && upp * thetadot > 0, upp = 0; end
            uRot = -(c.kp * theta + c.kd * thetadot);
            o.swE = en;
            uUnsat = uRot + upp;
        end

        function advance(o, p), o.phase = p; o.ptick = 0; end
        function n = tStep(o), if o.exp == 8, n = 5000; else, n = 7500; end, end

        % ================================================ experiments 1-5 (runTutorial)
        function [vOut, u, ref] = tickTutorial(o, rotor, psiMeas)
            alpha = wrap180(180 - psiMeas);
            u = 0; ref = 0;
            switch o.exp
                case 1, ref = o.exp001Seq();
                case 2, [u, ref] = o.exp002(rotor);
                case {3, 4}, [u, ref] = o.exp003(rotor, psiMeas);
                case 5
                    [u, ref] = o.exp005(rotor, alpha);
                    if o.held && o.phase ~= 0, o.held = false; end
            end
            if o.exp ~= 1
                u = o.runner(u, o.cfg.ulim, o.cfg.vmax);
                vOut = o.rateOut();
            else
                % open loop: 200 microsteps/s until the move is done (the last
                % tick runs only the steps that are left)
                vOut = 0;
                if o.moveLeft > 0
                    n = min(o.moveLeft, 200 * o.Ts);
                    vOut = o.moveDir * n / o.Ts / o.UPD;
                    o.moveLeft = o.moveLeft - n;
                end
            end
        end

        function [pd, uu] = pdUpdate(o, pd, e)
            raw = 0; if pd.have, raw = (e - pd.e0) / o.Ts; end
            pd.d = pd.d + o.a10 * (raw - pd.d);
            uu = pd.kp * e + pd.kd * pd.d;
            pd.e0 = e; pd.have = true;
        end

        function [uu, R] = exp002(o, y)
            R = 0; D = 0; dur = [500 3000 1500 3000 1500]; lim = o.cfg.ulim;
            if o.phase == 1, R = o.cfg.step; end
            if o.phase == 3, D = o.cfg.dist; end
            [o.pdR, un] = o.pdUpdate(o.pdR, R - y);
            us = min(max(un, -lim), lim);
            uu = us + D;
            if strcmp(o.runState, 'ACTIVE') && o.phase < 5
                if us ~= un, o.satRun = o.satRun + 1; else, o.satRun = 0; end
                if o.satRun >= 250, o.runState = 'ABORTED'; o.abortWhy = 'SATURATION'; o.phase = 6; end
                if abs(y) > 240, o.runState = 'ABORTED'; o.abortWhy = 'ROTOR_LIMIT'; o.phase = 6; end
            end
            if o.phase < 5 && o.ptick >= dur(o.phase + 1), o.phase = o.phase + 1; o.ptick = 0; end
            o.ptick = o.ptick + 1;
            if o.phase == 5 && strcmp(o.runState, 'ACTIVE'), o.runState = 'STOPPING'; end
            if o.phase >= 5, uu = 0; end
            if strcmp(o.runState, 'ABORTED'), uu = 0; end
        end

        function [uu, R] = exp003(o, y, p)
            R = 0; dur = [500 7500 1500]; lim = o.cfg.ulim;
            if o.phase == 1, R = o.cfg.step; end
            [o.pdR, ur] = o.pdUpdate(o.pdR, R - y);
            [o.pdP, up] = o.pdUpdate(o.pdP, 0 - p);
            uu = min(max(ur + up, -lim), lim); clipped = uu ~= ur + up;
            if strcmp(o.runState, 'ACTIVE') && o.phase < 3
                if abs(y) > 240, o.runState = 'ABORTED'; o.abortWhy = 'ROTOR_LIMIT'; o.phase = 4;
                elseif abs(p) > 120, o.runState = 'ABORTED'; o.abortWhy = 'PENDULUM_LIMIT'; o.phase = 4;
                else
                    if clipped, o.satRun = o.satRun + 1; else, o.satRun = 0; end
                    if o.satRun >= 250, o.runState = 'ABORTED'; o.abortWhy = 'SATURATION'; o.phase = 4; end
                end
            end
            if o.phase < 3 && o.ptick >= dur(o.phase + 1), o.phase = o.phase + 1; o.ptick = 0; end
            o.ptick = o.ptick + 1;
            if o.phase == 3 && strcmp(o.runState, 'ACTIVE'), o.runState = 'STOPPING'; end
            if o.phase >= 3 || strcmp(o.runState, 'ABORTED'), uu = 0; end
        end

        function [uu, R] = exp005(o, y, al)
            lim = o.cfg.ulim;
            if o.phase == 1 && ~o.rel5 && abs(al - o.alCap) >= 1.5
                o.rel5 = true; o.ptick = 0;
            end
            controlling = (o.phase == 1 && o.rel5) || any(o.phase == [2 3 4]);
            wasDone = (o.phase == 4);
            R = 0; if o.phase == 2, R = o.cfg.step; end
            [o.pdR, ur] = o.pdUpdate(o.pdR, R - y);
            [o.pdP, up] = o.pdUpdate(o.pdP, 0 - al);
            uu = 0; clipped = false;
            if controlling
                uu = -ur + up;
                if uu > lim, uu = lim; clipped = true; elseif uu < -lim, uu = -lim; clipped = true; end
            end
            if o.phase ~= 5 && o.P.safety
                if abs(al) > 15, o.phase = 5; o.runState = 'ABORTED'; o.abortWhy = 'PENDULUM_LOST';
                elseif abs(y) > 240, o.phase = 5; o.runState = 'ABORTED'; o.abortWhy = 'ROTOR_LIMIT';
                else
                    if controlling && abs(al) > 10, o.warnRun = o.warnRun + 1;
                        if o.warnRun >= 50, o.phase = 5; o.runState = 'ABORTED'; o.abortWhy = 'PENDULUM_LOST'; end
                    else, o.warnRun = 0; end
                    if controlling && clipped, o.satRun = o.satRun + 1;
                        if o.satRun >= 100, o.phase = 5; o.runState = 'ABORTED'; o.abortWhy = 'SATURATION'; end
                    else, o.satRun = 0; end
                end
            end
            switch o.phase
                case 0
                    if abs(al) <= 2
                        o.capRun = o.capRun + 1;
                        if o.capRun >= 500, o.alCap = al; o.rel5 = false; o.phase = 1; o.ptick = 0; end
                    else, o.capRun = 0; end
                case 1, if o.rel5 && o.ptick >= 1000, o.phase = 2; o.ptick = 0; end
                case 2, if o.ptick >= 5000, o.phase = 3; o.ptick = 0; end
                case 3, if o.ptick >= 1500, o.phase = 4; o.ptick = 0; end
            end
            o.ptick = o.ptick + 1;
            if o.phase == 5, uu = 0; end
            if o.phase == 4 && ~wasDone, uu = 0; end
        end

        function R = exp001Seq(o)
            % 0 hold 1 s | 1 move +step | 2 wait 3 s | 3 move back | 4 wait 3 s | 5 done
            c = o.cfg; R = 0; if any(o.phase == [1 2]), R = c.step; end
            switch o.phase
                case 0, if o.ptick >= 500, o.phase = 1; o.ptick = 0; o.moveLeft = round(abs(c.step) * o.UPD); o.moveDir = sign(c.step + eps); end
                case 1, if o.moveLeft <= 0, o.phase = 2; o.ptick = 0; end
                case 2, if o.ptick >= 1500, o.phase = 3; o.ptick = 0; o.moveLeft = round(abs(c.step) * o.UPD); o.moveDir = -sign(c.step + eps); end
                case 3, if o.moveLeft <= 0, o.phase = 4; o.ptick = 0; end
                case 4, if o.ptick >= 1500, o.phase = 5; o.ptick = 0; end
            end
            o.ptick = o.ptick + 1;
        end
    end
end

function a = lpAlpha(fc, dt)
    if fc <= 0, a = 1; return; end
    a = 1 - exp(-2 * pi * fc * dt);
    a = min(max(a, 0), 1);
end

function a = wrap180(a)
    a = rem(a, 360);
    if a > 180, a = a - 360; end
    if a <= -180, a = a + 360; end
end

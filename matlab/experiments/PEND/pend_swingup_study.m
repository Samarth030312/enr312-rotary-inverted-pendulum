function R = pend_swingup_study(plant, opts)
%PEND_SWINGUP_STUDY  PEND C12: energy swing-up, in simulation only, and why linear PID cannot.
%
%   R = pend_swingup_study()                 % Tutorial 5 plant, default sweep
%   R = pend_swingup_study(plant, opts)
%
%   EXECUTION STATUS: simulation only. The rig firmware has no swing-up: a
%   first firmware attempt (protocol 3 development, not kept) never brought
%   the emulated pendulum closer than ~49 deg to upright, cause not
%   established. This idealised study finds that the actuator limits are NOT
%   the reason: at 1500 deg/s^2 and 360 deg/s the pump reaches the catch
%   window in about 3 s using about 65 deg of arm travel. A rig swing-up is
%   future work.
%
%   Model (nonlinear, docs/first_principles/ROTARY_PENDULUM_DYNAMICS.md),
%   psi from hanging, arm acceleration u [rad/s^2] as the input:
%       psi'' = -wg2 sin(psi) + wr2 cos(psi) u - gamma psi'
%   Energy, normalised so hanging still = 0 and upright still = 2:
%       E = psi'^2 / (2 wg2) + 1 - cos(psi)
%       dE/dt = (psi'/wg2) (wr2 cos(psi) u - gamma psi')
%   so u = umax sign(psi' cos psi) pumps energy in fastest (Astrom & Furuta
%   2000). It stops when E reaches 2, then a linear controller catches the
%   pendulum when |alpha| < catchDeg. Arm travel is limited by a centring
%   term on the arm (kc theta + kcd theta') added to the pump.
%
%   Why linear PID cannot swing up: the linearisation u -> alpha assumes
%   cos(psi) ~ -1 (near upright). Below horizontal cos(psi) changes sign,
%   so the same arm acceleration pushes the pendulum the OTHER way: a
%   linear law with fixed gains has the wrong sign over half the circle, and
%   sin(psi) ~ psi is wrong by 36 % at 90 deg. The pump law above uses the
%   sign of cos(psi) explicitly; a linear one cannot.
%
%   Sweep: umax in opts.umax [deg/s^2], arm limit opts.armDeg [deg], arm
%   speed ceiling opts.vmax [deg/s] (default 360, as the firmware runner;
%   the arm's speed is clipped there, which caps how fast energy can go in).
%   Catch: once E >= 1.95 and |alpha| < 20 deg, the 4-state LQR of
%   experiment 23 (odyssix.sim.defaults(23)) takes over, still on the
%   nonlinear model with the same limits, for opts.catchSeconds (3 s).
%   R: table umax, reached, t_reach [s], caught (|alpha| < 3 deg at the end
%   of the catch), closest_deg (closest approach to upright), max_arm_deg.
%   No sampling, quantisation or missed steps: an optimistic bound.
    if nargin < 1 || isempty(plant), plant = odyssix.sim.plant(5); end
    if nargin < 2, opts = struct(); end
    if ~isfield(opts, 'umax'), opts.umax = [750 1500 3000 6000 12000]; end
    if ~isfield(opts, 'armDeg'), opts.armDeg = 240; end
    if ~isfield(opts, 'seconds'), opts.seconds = 30; end
    if ~isfield(opts, 'vmax'), opts.vmax = 360; end     % deg/s, the runner's default ceiling
    if ~isfield(opts, 'plot'), opts.plot = nargout == 0; end
    if ~isfield(opts, 'catchSeconds'), opts.catchSeconds = 3; end
    c23 = odyssix.sim.defaults(23); K = [c23.k1 c23.k2 c23.k3 c23.k4];
    wg2 = plant.wg2; gam = sqrt(wg2) / plant.Q; wr2 = plant.wr2;
    h = 1e-3; N = round(opts.seconds / h);
    n = numel(opts.umax);
    [reached, tReach, caught, closest, maxArm] = deal(nan(n, 1));
    traces = cell(n, 1);
    for i = 1:n
        um = deg2rad(opts.umax(i));
        psi = deg2rad(5); pd = 0; th = 0; thd = 0;
        kc = 4; kcd = 4;                          % arm centring [1/s^2], [1/s]
        ok = false; best = 180; mA = 0; kEnd = N; thCatch = 0;
        log_ = zeros(ceil((N + opts.catchSeconds / h) / 10), 3); j = 0;
        k = 0;
        while k < kEnd
            k = k + 1;
            E = pd^2 / (2 * wg2) + 1 - cos(psi);
            if ok
                % LQR catch in degree units, alpha = 180 - psi, alpha' = -psi'
                al = rad2deg(wrapToPi_(pi - psi)); ald = -rad2deg(pd);
                u = deg2rad(-(K(1) * (rad2deg(th) - thCatch) + K(2) * rad2deg(thd) + K(3) * al + K(4) * ald));
            elseif E < 2
                u = um * sign(pd * cos(psi));
                if pd == 0, u = um; end           % start from rest
            else
                u = 0;
            end
            if ~ok, u = u - kc * th - kcd * thd; end
            u = max(-um, min(um, u));
            pdd = -wg2 * sin(psi) + wr2 * cos(psi) * u - gam * pd;
            pd = pd + h * pdd; psi = psi + h * pd;
            thd = thd + h * u; th = th + h * thd;
            vm = deg2rad(opts.vmax);                 % the stepper's speed ceiling
            if abs(thd) > vm, thd = sign(thd) * vm; end
            a = abs(rad2deg(wrapToPi_(pi - psi)));
            best = min(best, a); mA = max(mA, abs(rad2deg(th)));
            if mod(k, 10) == 0, j = j + 1; log_(j, :) = [k * h, rad2deg(psi), rad2deg(th)]; end
            if abs(rad2deg(th)) > opts.armDeg, break; end
            if E >= 1.95 && a < 20 && ~ok
                ok = true; tReach(i) = k * h; thCatch = rad2deg(th);
                kEnd = k + round(opts.catchSeconds / h);
            end
        end
        reached(i) = ok; closest(i) = best; maxArm(i) = mA;
        caught(i) = ok && abs(rad2deg(wrapToPi_(pi - psi))) < 3;
        traces{i} = log_(1:j, :);
    end
    R = table(opts.umax(:), reached, tReach, caught, closest, maxArm, ...
        'VariableNames', {'umax_deg_s2', 'reached', 't_reach_s', 'caught', 'closest_deg', 'max_arm_deg'});
    R.Properties.UserData = struct('traces', {traces}, 'plant', plant, 'armDeg', opts.armDeg, 'vmax', opts.vmax, ...
        'status', 'SIMULATION ONLY - not run on the rig');
    if opts.plot
        figure('Name', 'PEND C12 energy swing-up (simulation)');
        tiledlayout(2, 1);
        nexttile; hold on;
        for i = 1:n, d = traces{i}; plot(d(:, 1), d(:, 2), 'DisplayName', sprintf('%g deg/s^2', opts.umax(i))); end
        yline(180, 'k:'); ylabel('\psi [deg] (180 = upright)'); legend('Location', 'best'); grid on;
        title('Energy pumping: u = u_{max} sign(\psi'' cos\psi), simulation');
        nexttile; hold on;
        for i = 1:n, d = traces{i}; plot(d(:, 1), d(:, 3)); end
        yline([-1 1] * opts.armDeg, 'r--'); ylabel('arm \theta [deg]'); xlabel('t [s]'); grid on;
    end
end

function a = wrapToPi_(a)
    a = mod(a + pi, 2 * pi) - pi;
end

function T = gainSweep(exp, name, values, plant, opts)
%GAINSWEEP  PEND A6/B8: vary one gain (or the loop rate) and see what survives.
%
%   T = odyssix.pend.gainSweep(exp, name, values)
%   T = odyssix.pend.gainSweep(exp, name, values, plant, opts)
%
%   exp     6, 7, 8 or 23 (inverted) or 9, 10, 21, 22 (suspended)
%   name    any odyssix.sim.defaults field: 'kpp', 'kdp', 'kp', 'kd', 'ki',
%           'div' (loop rate = 500/div Hz), 'ma', 'fdp', ...
%   values  vector of values for that field, the others at their defaults
%   opts    .seconds (default: the experiment's), .base (a cfg to start from)
%
%   For each value: the continuous-time linear verdict (closed-loop poles of
%   odyssix.sim.loop, which knows nothing of sampling, filters, quantisation
%   or limits) and the verdict of the full simulation of the firmware
%   (odyssix.sim.runCtrl): did it end balanced / what aborted it, and the
%   pendulum rms while running. Where the two disagree, the effects missing
%   from the linear model are the reason: that disagreement is the answer to
%   "why does the rig not behave like the textbook" for that gain.
%
%   Returns a table: value, linear_stable, sim_ok, abort, alpha_rms_deg,
%   max_abs_pend_deg, max_rotor_deg.
%
%   Example (PEND A6, the range of pendulum Kp that balances):
%     T = odyssix.pend.gainSweep(6, 'kpp', 40:20:700)
%   Analytic lower bound: the pendulum gain must overcome gravity,
%   kpp wr2 > wg2  ->  kpp > wg2/wr2 (= 69.6 for the Tutorial 5 plant).
    if nargin < 4 || isempty(plant)
        if any(exp == [6 7 8 23 5]), plant = odyssix.sim.plant(5); else, plant = odyssix.sim.plant(3); end
    end
    if nargin < 5, opts = struct(); end
    if isfield(opts, 'base'), base = opts.base; else, base = odyssix.sim.defaults(exp); end
    if isfield(opts, 'seconds'), base.seconds = opts.seconds; end
    inv = any(exp == [6 7 8 23]);
    n = numel(values);
    [linStable, simOk, rmsA, maxP, maxR] = deal(nan(n, 1));
    abortWhy = strings(n, 1);
    for i = 1:n
        c = base; c.(name) = values(i);
        try
            lp = odyssix.sim.loop(c, plant);
            if ~isempty(lp), linStable(i) = lp.stable; end
        catch
        end
        S = odyssix.sim.runCtrl(c, plant);
        U = S.Properties.UserData;
        abortWhy(i) = string(U.abort);
        simOk(i) = strcmp(U.state, 'ACTIVE') || strcmp(U.state, 'FINISHED');
        simOk(i) = simOk(i) && strcmp(U.abort, 'NONE');
        if inv
            w = S.phase >= 2 & S.phase <= 8;
            a = S.alpha(w);
        else
            w = true(height(S), 1); a = S.psi;
        end
        if any(w), rmsA(i) = sqrt(mean(a.^2)); maxP(i) = max(abs(a)); end
        maxR(i) = max(abs(S.rotor));
    end
    T = table(values(:), linStable, simOk, abortWhy, rmsA, maxP, maxR, ...
        'VariableNames', {name, 'linear_stable', 'sim_ok', 'abort', 'alpha_rms_deg', 'max_abs_pend_deg', 'max_rotor_deg'});
    if strcmp(name, 'div'), T.loop_hz = 500 ./ T.div; T = movevars(T, 'loop_hz', 'After', 'div'); end
    T.Properties.Description = sprintf('exp %d sweep of %s, plant wg2 %.2f Q %.1f wr2 %.3f', ...
        exp, name, plant.wg2, plant.Q, plant.wr2);
end

function m = metrics(D, cfg)
%METRICS  Tutorial metrics from a simulated OR measured run, computed identically.
%
%   m = odyssix.sim.metrics(D, cfg)
%   D: table with t, rotor, psi, u, ref, phase (odyssix.sim.runTutorial, or a
%      rig recording mapped to these names). Phase numbering is the firmware's.
%   Returns a struct of named values (NaN when not applicable).
    m = struct();
    t = D.t - D.t(1); th = D.rotor; ps = D.psi; u = D.u; ph = D.phase;
    s = cfg.step;
    switch cfg.exp
        case 1
            w = ph == 2;                                    % after the move out
            m.rotor_after_move_deg = last(th(w));
            m.pend_swing_pp_deg = range_(ps(w));
        case 2
            w = ph == 1; tw = t(w) - firstOr(t(w));
            [m.overshoot_pct, m.peak_time_s, m.settling_s] = stepInfo(tw, th(w), s, 2 * 360 / 3200);
            w3 = ph == 3; tw3 = t(w3); m.dist_offset_deg = NaN;
            if any(w3), m.dist_offset_deg = mean(th(w3 & t >= max(tw3) - 1)); end
            m.dist_offset_pred_deg = cfg.dist / cfg.kp;
            m.u_max = max(abs(u));
        case {3, 4}
            w = ph == 1; tw = t(w) - firstOr(t(w));
            [m.overshoot_pct, m.peak_time_s, m.settling_s] = stepInfo(tw, th(w), s, 2 * 360 / 3200);
            if ~any(w), [m.ce_max, m.ce_power, m.ce_total, m.pend_peak_deg, m.pend_end_deg] = deal(NaN); return; end
            m.ce_max = max(abs(u(w))); m.ce_power = m.ce_max^2;
            m.ce_total = trapz(tw, abs(u(w)));
            m.pend_peak_deg = max(abs(ps(w)));
            m.pend_end_deg = mean(ps(w & t >= max(t(w)) - 1));
        case 5
            al = 180 - ps; al = mod(al + 180, 360) - 180;
            w = ph == 2; tw = t(w) - firstOr(t(w)); y0 = firstOr(th(w));
            m.undershoot_pct = NaN; if any(w), m.undershoot_pct = 100 * min(0, min(th(w) - y0)) / s; end
            [m.overshoot_pct, m.peak_time_s, m.settling_s] = stepInfo(tw, th(w) - y0, s, 2 * 360 / 3200);
            ctl = any(ph == [1 2 3 4], 2);
            m.alpha_peak_deg = NaN; if any(ctl), m.alpha_peak_deg = max(abs(al(ctl))); end
            m.hunting_deg = NaN;                            % aborted before balancing: no samples
            if any(ctl), tail = ctl & t >= max(t(ctl)) - 2; m.hunting_deg = range_(th(tail)) / 2; end
            m.balanced = any(ctl) && ~any(ph == 5);
    end
end

function [os, tp, ts] = stepInfo(t, y, s, minBand)
    if isempty(y) || s == 0, os = NaN; tp = NaN; ts = NaN; return; end
    [pk, k] = max(y * sign(s)); os = 100 * (pk / abs(s) - 1); tp = t(k);
    % 2 % of the step, never tighter than 2 microsteps (the rotor cannot sit closer)
    band = max(0.02 * abs(s), minBand);
    out = abs(y - s) > band;
    if out(end), ts = NaN; elseif ~any(out), ts = 0; else, ts = t(find(out, 1, 'last')); end
end
function v = last(x), if isempty(x), v = NaN; else, v = x(end); end, end
function v = firstOr(x), if isempty(x), v = 0; else, v = x(1); end, end
function r = range_(x), if isempty(x), r = NaN; else, r = max(x) - min(x); end, end

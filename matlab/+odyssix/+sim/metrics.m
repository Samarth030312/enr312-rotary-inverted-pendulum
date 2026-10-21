function m = metrics(D, cfg)
%METRICS  Tutorial metrics from a simulated OR measured run, computed identically.
%
%   m = odyssix.sim.metrics(D, cfg)
%   D: table with t, rotor, psi, u, ref, phase (odyssix.sim.runTutorial, or a
%      rig recording mapped to these names). Phase numbering is the firmware's.
%   Returns a struct of named values (NaN when not applicable).
%   Experiments 6-10 and 21-23 use the phase numbers of enr312_ctrl.c.
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

        % ---- general core (enr312_ctrl.c phases: 2 BALANCE 3 STEP 4 STEP_BACK
        %      5 DIST 6 DIST_OFF 7 IMPULSES 8 HOLD 9 IDLE 10 REGULATE 13 ABORTED)
        case {6, 8, 23}
            al = mod(180 - ps + 180, 360) - 180;
            ctl = ph >= 2 & ph <= 8;
            % relative to where the step starts (the arm may not be exactly at 0)
            w = ph == 3; tw = t(w) - firstOr(t(w)); y0 = firstOr(th(w));
            % 5 % band: balancing upright, the arm keeps a +/-1 deg wobble (stepper
            % quantisation + encoder noise) that a 2 % band would never admit;
            % the wobble itself is reported as rotor_wobble_deg
            [m.overshoot_pct, m.peak_time_s, m.settling_s] = stepInfo(tw, th(w) - y0, s - y0, 2 * 360 / 3200, 0.05);
            m.rotor_wobble_deg = NaN; if any(w), m.rotor_wobble_deg = range_(th(w & t >= max(t(w)) - 2)); end
            m.undershoot_pct = NaN; if any(w), m.undershoot_pct = 100 * min(0, min(th(w) - y0)) / (s - y0); end
            m.ss_error_deg = NaN; if any(w), m.ss_error_deg = s - mean(th(w & t >= max(t(w)) - 2)); end
            m.alpha_rms_deg = NaN; if any(ctl), m.alpha_rms_deg = sqrt(mean(al(ctl).^2)); end
            m.balanced = any(ctl) && ~any(ph == 13);
            if cfg.exp == 8
                w5 = ph == 5; m.ld_peak_deg = NaN; m.ld_final_deg = NaN; m.ld_settling_s = NaN;
                if any(w5)
                    t5 = t(w5) - firstOr(t(w5)); y5 = th(w5);
                    m.ld_peak_deg = max(abs(y5));
                    m.ld_final_deg = mean(y5(t5 >= max(t5) - 2));
                    out = abs(y5 - m.ld_final_deg) > max(0.1 * m.ld_peak_deg, 2 * 360 / 3200);
                    if any(out), m.ld_settling_s = t5(find(out, 1, 'last')); else, m.ld_settling_s = 0; end
                    % without integral action the arm sits at -D/Kp (S_D(0) = 1/Kp,
                    % Tutorial 8; negative in the inverted sign convention, as simulated)
                    m.ld_offset_pred_deg = -cfg.dist / cfg.kp * (cfg.ki == 0);
                end
            end
        case 7
            al = mod(180 - ps + 180, 360) - 180;
            r = odyssix.sim.impulseAverage(t, al, th, ph);
            m.n_impulses = r.n;
            m.pend_peak_deg = r.pendPeak; m.pend_settling_s = r.pendSettle;
            m.rotor_peak_deg = r.rotorPeak; m.rotor_settling_s = r.rotorSettle;
            ctl = ph >= 2 & ph <= 8;
            m.alpha_rms_deg = NaN; if any(ctl), m.alpha_rms_deg = sqrt(mean(al(ctl).^2)); end
            m.balanced = any(ctl) && ~any(ph == 13);
        case {9, 10, 22}
            w = ph == 3; tw = t(w) - firstOr(t(w));
            [m.overshoot_pct, m.peak_time_s, m.settling_s] = stepInfo(tw, th(w), s, 2 * 360 / 3200);
            m.final_value_deg = NaN; m.limit_cycle_deg = NaN;
            if any(w)
                m.final_value_deg = mean(th(w & t >= max(t(w)) - 2));
                m.limit_cycle_deg = range_(th(w & t >= max(t(w)) - 5)) / 2;
            end
            m.pend_peak_deg = max(abs(ps));
        case 21
            w = ph == 10; tw = t(w) - firstOr(t(w)); y = ps(w);
            m.swing_start_deg = NaN; m.stop_time_s = NaN;
            if any(w)
                m.swing_start_deg = max(abs(y(tw <= 1)));
                out = abs(y) > 1.0;
                if ~any(out), m.stop_time_s = 0; elseif out(end), m.stop_time_s = NaN;
                else, m.stop_time_s = tw(find(out, 1, 'last')); end
            end
            m.rotor_peak_deg = max(abs(th(w)));
    end
    % "hold the arm at this angle when asked": cfg.target [deg] commanded at
    % cfg.target_t [s] (live '$ref', experiments 6-8, 21, 23)
    if isfield(cfg, 'target') && isfield(cfg, 'target_t') && isfinite(cfg.target_t)
        w = t >= cfg.target_t;
        m.hold_error_deg = NaN; m.hold_reach_s = NaN;
        if any(w)
            tw = t(w) - cfg.target_t; e = th(w) - cfg.target;
            m.hold_error_deg = mean(e(tw >= max(tw) - 3));
            % 0.5 deg (4-5 microsteps) hanging; 1.5 deg upright, where the arm
            % keeps a +/-1 deg balancing wobble
            band = 0.5; if any(cfg.exp == [5 6 7 8 23]), band = 1.5; end
            m.hold_band_deg = band;
            out = abs(e) > band;
            if ~any(out), m.hold_reach_s = 0; elseif ~out(end), m.hold_reach_s = tw(find(out, 1, 'last') + 1); end
        end
    end
end

function [os, tp, ts] = stepInfo(t, y, s, minBand, frac)
    if nargin < 5, frac = 0.02; end
    if isempty(y) || s == 0, os = NaN; tp = NaN; ts = NaN; return; end
    [pk, k] = max(y * sign(s)); os = 100 * (pk / abs(s) - 1); tp = t(k);
    % frac of the step (2 % default), never tighter than 2 microsteps
    band = max(frac * abs(s), minBand);
    out = abs(y - s) > band;
    if out(end), ts = NaN; elseif ~any(out), ts = 0; else, ts = t(find(out, 1, 'last')); end
end
function v = last(x), if isempty(x), v = NaN; else, v = x(end); end, end
function v = firstOr(x), if isempty(x), v = 0; else, v = x(1); end, end
function r = range_(x), if isempty(x), r = NaN; else, r = max(x) - min(x); end, end

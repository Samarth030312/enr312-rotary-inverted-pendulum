function r = impulseAverage(t, alpha, rotor, phase)
%IMPULSEAVERAGE  Tutorial 7: average the responses to the pendulum-reference impulses.
%
%   r = odyssix.sim.impulseAverage(t, alpha, rotor, phase)
%   The firmware (enr312_ctrl.c, experiment 7) applies an impulse of imp deg for
%   4 ms at the end of every 5 s window of phase 7 (IMPULSES), 8 in all. The
%   response windows [-0.5, 4.5] s around each impulse are aligned on the known
%   timing and averaged (Tutorial 7, section 15: signal averaging), which works
%   for 500 Hz simulation and 50 Hz rig data alike.
%   r.t, r.alpha, r.rotor: averaged responses (rotor relative to its value
%   before the impulse); r.n; peaks and 2-%-of-peak settling times.
    r = struct('t', [], 'alpha', [], 'rotor', [], 'n', 0, 'pendPeak', NaN, ...
               'pendSettle', NaN, 'rotorPeak', NaN, 'rotorSettle', NaN);
    k0 = find(phase == 7, 1);
    if isempty(k0), return; end
    t0 = t(k0);
    tt = (-0.5:0.02:4.5)';
    A = []; R = [];
    for k = 1:8
        ti = t0 + 5 * k - 0.004;
        if ti + 4.5 > t(end), break; end
        A(:, end + 1) = interp1(t, alpha, ti + tt, 'previous'); %#ok<AGROW>
        rr = interp1(t, rotor, ti + tt, 'previous');
        R(:, end + 1) = rr - rr(find(tt < 0, 1, 'last')); %#ok<AGROW>
    end
    if isempty(A), return; end
    r.t = tt; r.alpha = mean(A, 2); r.rotor = mean(R, 2); r.n = size(A, 2);
    a = r.alpha - mean(r.alpha(tt < 0));
    [r.pendPeak, r.pendSettle] = peakSettle(tt, a);
    [r.rotorPeak, r.rotorSettle] = peakSettle(tt, r.rotor);
end

function [pk, ts] = peakSettle(t, y)
    post = t >= 0;
    [~, i] = max(abs(y(post))); yp = y(post); pk = yp(i);
    out = abs(yp) > max(0.1 * abs(pk), 0.15);   % 10 % of the peak, not below one encoder count
    tp = t(post);
    if ~any(out), ts = 0; elseif out(end), ts = NaN; else, ts = tp(find(out, 1, 'last')); end
end

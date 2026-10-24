function out = enr312_simulink(exp, varargin)
%ENR312_SIMULINK  Run one experiment in the Simulink model and plot it.
%
%   enr312_simulink                 list the experiments
%   enr312_simulink(9)              Tutorial 9 on this rig's measured pendulum
%   enr312_simulink(5, 'tutorial')  Tutorial 5 on the Tutorials' pendulum
%   enr312_simulink(P)              your own settings: P = enr312_simulink_params(9); P.k1 = 4;
%   out = enr312_simulink(...)      also return the simulation output
%   enr312_simulink(..., 'animate') then show the rig moving in 3-D
%
%   It sets P in the base workspace, opens the model (so you can see the blocks and
%   the scopes), runs it, and draws arm angle, pendulum angle and plant input with
%   labelled axes. Change a field of P and call enr312_simulink(P) to compare.
    names = experimentNames();
    if nargin == 0
        fprintf('\nExperiments in the Simulink model (enr312_simulink(n)):\n');
        k = cell2mat(names(:, 1));
        for i = 1:numel(k), fprintf('  %2d  %s\n', k(i), names{i, 2}); end
        fprintf(['\nExample:  enr312_simulink(5)                     Tutorial 5, upright balancing\n' ...
                 '          P = enr312_simulink_params(5); P.kpp = 200; enr312_simulink(P)\n\n']);
        if nargout, out = []; end
        return;
    end
    anim = any(strcmpi(varargin, 'animate'));
    rest = varargin(~strcmpi(varargin, 'animate'));
    if isstruct(exp), P = exp; else, P = enr312_simulink_params(exp, rest{:}); end
    here = fileparts(mfilename('fullpath')); mdl = 'enr312_pendulum';
    if ~isfile(fullfile(here, [mdl '.slx'])), build_enr312_simulink(here); end
    assignin('base', 'P', P);
    if usejava('desktop'), open_system(fullfile(here, [mdl '.slx'])); else, load_system(fullfile(here, [mdl '.slx'])); end
    o = sim(mdl, 'SrcWorkspace', 'base');

    nm = names{cell2mat(names(:, 1)) == P.exp, 2};
    f = figure('Color', 'w', 'Name', sprintf('Simulink: %d %s', P.exp, nm), 'NumberTitle', 'off', 'Position', [80 80 1100 720]);
    if exist('theme', 'file'), theme(f, 'light'); end
    tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    up = any(P.exp == [5 6 7 8 23]) || (P.exp == 24);
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    plot(ax, o.theta_deg.Time, o.theta_deg.Data, 'LineWidth', 1.4);
    stairs(ax, o.ref.Time, o.ref.Data, '--', 'Color', [0.5 0.5 0.5]);
    ylabel(ax, 'arm \theta (deg)'); legend(ax, {'arm', 'set-point'}, 'Location', 'best');
    title(ax, sprintf('Experiment %d · %s · pendulum ω_g^2 = %.1f rad^2/s^2', P.exp, nm, P.wg2));
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    ps = o.psi_deg.Data;
    if up && P.exp ~= 24
        plot(ax, o.psi_deg.Time, mod(180 - ps + 180, 360) - 180, 'LineWidth', 1.4, 'Color', [0.85 0.33 0.10]);
        ylabel(ax, 'pendulum from upright \alpha (deg)');
    else
        plot(ax, o.psi_deg.Time, ps, 'LineWidth', 1.4, 'Color', [0.85 0.33 0.10]);
        ylabel(ax, 'pendulum from hanging \psi (deg)');
    end
    ax = nexttile(tl); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    stairs(ax, o.u.Time, o.u.Data, 'Color', [0.2 0.2 0.2]);
    ylabel(ax, 'plant input u (deg/s^2)'); xlabel(ax, 't (s)');
    if anim, animate_enr312_simulink(o); end
    if nargout, out = o; end
end

function n = experimentNames()
    n = {1, 'T1 actuator: open-loop move out and back'
         2, 'T2 sensitivity: arm PD, reference step, load step (pendulum removed)'
         3, 'T3 control effort: hanging, arm PD + pendulum PD, step'
         4, 'T4 MIMO sensitivity: the same loop as T3'
         5, 'T5 inverted: upright, dual PD, held then released'
         6, 'T6 integral action: upright, arm PID + pendulum PD, step'
         7, 'T7 pendulum-loop design: upright, eight pendulum impulses'
         8, 'T8 load disturbance: upright, step and a constant load'
         9, 'T9 pole placement: state feedback on the arm, step'
         10, 'T10 LQR: state feedback on the arm, step'
         21, 'PEND stop a swing: hanging, starts swinging at 20 deg'
         22, 'PEND on-off control: arm step'
         23, 'PEND upright LQR: held, released, step'
         24, 'PEND swing-up: energy pumping, then the LQR catches it upright'};
end

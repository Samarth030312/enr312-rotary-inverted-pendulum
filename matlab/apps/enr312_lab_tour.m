function enr312_lab_tour(syncDir)
%ENR312_LAB_TOUR  Scripted walk-through of enr312_lab (demo video).
%   Simulation for Tutorials 2, 4, 5 with live parameter changes, then the
%   same tutorials on the rig EMULATOR (the firmware's control code on the PC;
%   SYNTHETIC, not hardware) with measurement overlaid on simulation.
    if nargin < 1, syncDir = ''; end
    a = enr312_lab(); drawnow; pause(1);
    if ~isempty(syncDir)
        fclose(fopen(fullfile(syncDir, 'ready'), 'w'));
        while ~isfile(fullfile(syncDir, 'go')), pause(0.1); end
    end
    say(a, 'Tutorial 2: rotor-only PD. Simulation runs the firmware''s own control path, 500 Hz, quantised.', 2);
    a.select(2); pause(1); a.simulate();
    say(a, 'Tinker: raise Kp from 5 to 12. Faster, more overshoot, smaller disturbance offset D/Kp.', 1.5);
    a.set('kp', 12); pause(1); a.simulate();
    say(a, 'Tutorial 4: Nyquist of the loop and the M_S circle. Design A must stay under 1 dB.', 1.5);
    a.select(4); pause(1.5); a.preset('Design A Kp 1.20, Kd 1.50'); pause(3);
    say(a, 'Tutorial 5: inverted. Watch the arm move the WRONG way first: the right-half-plane zero.', 1.5);
    a.select(5); pause(1); a.simulate();
    say(a, 'Now the rig. No board here, so: the emulator, i.e. the firmware''s control code running on the PC.', 2);
    a.startEmulator(); pause(2.5); a.armNoPrompt(); pause(1); a.send('s'); pause(1.5);
    say(a, 'Tutorial 2 on the rig: same gains sent to the board. Blue = measured, grey = simulation.', 1);
    a.select(2); pause(1); a.runRig(); waitRun(a, 21);
    say(a, 'Tutorial 5 on the rig: the pendulum is held upright, captured, balanced, stepped.', 1);
    a.select(5); pause(1); a.send('^'); pause(0.5); a.runRig(); waitRun(a, 19);
    a.link.stopRun(); pause(2);
    say(a, 'Rig and simulation agree, metric by metric. Every slider is yours: enr312_lab.', 3);
    if ~isempty(syncDir), fclose(fopen(fullfile(syncDir, 'done'), 'w')); end
    a.abort(); pause(1); close(a.fig);
end
function say(a, txt, hold), a.ui.caption.Text = txt; drawnow; pause(hold); end
function waitRun(a, s), t0 = tic; while toc(t0) < s, pause(0.1); drawnow; end, end

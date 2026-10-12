function exp005_lab_tour(syncDir)
%EXP005_LAB_TOUR  Scripted walk-through of exp005_lab (used to record the demo video).
%
%   exp005_lab_tour            % just play it
%   exp005_lab_tour(syncDir)   % recording handshake: writes ready, waits for go, writes done
%
%   Every number shown comes from the same simulation a student gets by moving
%   the sliders by hand. See exp005_lab for what is and is not modelled.

    if nargin < 1, syncDir = ''; end
    a = exp005_lab();
    a.caption('EXP005: balance the inverted pendulum. First, Tutorial 5 System 1 as supplied.');
    drawnow; pause(1);
    if ~isempty(syncDir)
        fclose(fopen(fullfile(syncDir, 'ready'), 'w'));
        while ~isfile(fullfile(syncDir, 'go')), pause(0.1); end
    end

    say(a, 'System 1 (Kp 9, Kd 9). Watch the rotor: it moves the WRONG way first. That is the right-half-plane zero at +7.29 rad/s.', 3);
    a.run(); pause(1.5);

    say(a, 'Your turn: raise the rotor Kd from 9 to 15. The plots update instantly. Compare the dip and the margins.', 2);
    a.set('Kd', 15); pause(2.5); a.run(); pause(1.5);

    say(a, 'Tutorial 5 System 2 (Kp 10, Kd 3.33): far less damping. M_S above 10 dB means it is close to instability.', 2);
    a.preset('System 2 (quasi-stable, Tutorial 5)'); pause(2); a.run(); pause(1.5);

    say(a, 'Release the pendulum 4 deg from upright: the inner controller catches it within about half a second.', 2);
    a.preset('System 1 (stable, Tutorial 5)'); a.set('tilt', 4); pause(1.5); a.run(); pause(1.5);

    say(a, 'Untick quantisation: the rotor hunting and actuator chatter vanish. On the real rig they will not: expect the motor to buzz.', 2);
    a.set('tilt', 0); pause(1.5); a.set('quant', false); pause(3.5); a.set('quant', true); pause(1.5);

    say(a, 'A shorter pendulum (L = 0.18 m) falls faster: the unstable pole moves right and the controller has less time.', 2);
    a.set('L', 0.18); pause(2); a.run(); pause(1.5);

    say(a, 'Forget the outer-loop sign inversion and the pendulum falls. The firmware aborts at 15 deg, as it would on the rig.', 2);
    a.preset('Forgot the sign inversion'); pause(1.5); a.run(); pause(2.5);

    say(a, 'Now try your own design. Read the Model limits panel before trusting any result on hardware.', 3);
    if ~isempty(syncDir)
        fclose(fopen(fullfile(syncDir, 'done'), 'w'));
    end
end

function say(a, txt, hold)
    a.caption(txt); drawnow; pause(hold);
end

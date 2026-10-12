function enr312_rig_tour(syncDir)
%ENR312_RIG_TOUR  Scripted walk-through of enr312_rig on the EMULATOR (demo video).
%
%   enr312_rig_tour             % play it
%   enr312_rig_tour(syncDir)    % recording handshake: ready / go / done files
%
%   Everything shown is the rig EMULATOR (synthetic), not hardware.
    if nargin < 1, syncDir = ''; end
    app = enr312_rig();
    drawnow; pause(1);
    if ~isempty(syncDir)
        fclose(fopen(fullfile(syncDir, 'ready'), 'w'));
        while ~isfile(fullfile(syncDir, 'go')), pause(0.1); end
    end
    pause(2);
    app.startEmulator();                pause(3);     % connect: SAFE, streaming
    app.armNoPrompt();                  pause(2);     % ARMED
    app.send('s');                      pause(2);     % RUNNING
    app.send('+');                      pause(3);     % +5 deg: pendulum kicked
    app.send('-');                      pause(3);     % back
    app.abort();                        pause(2);     % SAFE
    app.send('z');                      pause(1);     % zero datums
    app.send('!');                      pause(0.3);   % EMULATOR: pluck 30 deg
    app.record();
    t0 = tic;
    while isempty(app.fit()) && toc(t0) < 25, pause(0.1); end
    pause(5);
    if ~isempty(syncDir), fclose(fopen(fullfile(syncDir, 'done'), 'w')); end
    pause(1);
    close(app.fig);
end

function ok = setup(varargin)
%SETUP  Get this repository ready on this computer, and say what is missing.
%
%   setup              add the MATLAB code to the path for this session and check
%                      everything the lab needs; prints what to install, if anything
%   setup('save')      the same, and keep the path for future sessions (savepath)
%   setup('open')      the same, then open the lab app
%
%   Nothing is installed or changed outside this folder, except the MATLAB path
%   with 'save'. Works on Windows, macOS and Linux. Details: docs/INSTALL.md.
    root = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(root, 'matlab')));
    d = fullfile(root, 'matlab', 'data');                        % recorded runs, not code
    if isfolder(d), rmpath(genpath(d)); end
    fprintf('\nSTEVAL-EDUKIT01 rotary inverted pendulum (ENR312): setup check\n%s\n', repmat('-', 1, 72));
    R = {};
    os = 'Linux'; if ispc, os = 'Windows'; elseif ismac, os = 'macOS'; end

    % ---- MATLAB --------------------------------------------------------------------------
    v = ver('MATLAB'); rel = version('-release');
    R(end+1, :) = {'MATLAB', str2double(rel(1:4)) >= 2023, sprintf('R%s (%s). Tested on R2026a; R2023b or newer recommended', rel, v.Version)};
    R(end+1, :) = {'toolboxes', true, 'none needed (the LQR and the fits are written in base MATLAB)'};
    hasSL = license('test', 'Simulink') && ~isempty(ver('simulink'));
    R(end+1, :) = {'Simulink (optional)', true, ternary(hasSL, 'found: matlab/simulink/ will run', 'not found: only matlab/simulink/ needs it')};
    try
        s = odyssix.sim.runCtrl(odyssix.sim.defaults(9), odyssix.sim.plant(9));
        R(end+1, :) = {'simulation', height(s) > 100, 'runs (the firmware''s control code, in MATLAB)'};
    catch err
        R(end+1, :) = {'simulation', false, err.message};
    end

    % ---- board side ---------------------------------------------------------------------
    T = odyssix.stm32.tools();
    if ~isempty(T.programmer)
        R(end+1, :) = {'STM32 programmer', true, T.programmer};
    else
        R(end+1, :) = {'STM32 programmer', false, 'not found: install STM32CubeProgrammer (free, st.com); needed to flash the board'};
    end
    try
        B = odyssix.stm32.listBoards();
        R(end+1, :) = {'board', true, B.text};
    catch err
        R(end+1, :) = {'board', true, ['not checked: ' err.message]};
    end
    try
        p = serialportlist("available"); if isunix, p = p(~startsWith(p, "/dev/ttyS")); end   % built-in UARTs
        R(end+1, :) = {'serial ports', true, ternary(isempty(p), 'none now (plug the board in to see its port)', strjoin(cellstr(p), ', '))};
    catch
        R(end+1, :) = {'serial ports', false, 'serialportlist failed: MATLAB R2019b or newer is needed'};
    end
    if isunix && ~ismac
        [~, g] = system('id -nG'); inDialout = contains(g, 'dialout');
        R(end+1, :) = {'serial permission', inDialout, ternary(inDialout, 'you are in the dialout group', ...
            'run: sudo usermod -aG dialout $USER  (then log out and in)')};
    end

    % ---- optional tools ------------------------------------------------------------------
    hasCC = ~ispc && system('cc --version > /dev/null 2>&1') == 0;
    R(end+1, :) = {'emulator (optional)', true, ternary(ispc, 'Linux and macOS only (it needs a pseudo-terminal)', ...
        ternary(isempty(T.make) || ~hasCC, 'needs make and a C compiler (docs/INSTALL.md)', 'make and a C compiler found'))};
    R(end+1, :) = {'Arm compiler (optional)', true, ternary(isempty(T.armGccBin), ...
        'not found: only needed to rebuild the firmware; the release image is in the repository', T.armGccBin)};

    % ---- report ---------------------------------------------------------------------------
    for i = 1:size(R, 1)
        mark = ternary(R{i, 2}, ' ok ', 'MISSING');
        fprintf('  %-26s %-8s %s\n', R{i, 1}, mark, R{i, 3});
    end
    need = ~[R{:, 2}];
    fprintf('%s\n', repmat('-', 1, 72));
    if any(need)
        fprintf('  %s: install what is marked MISSING, then run setup again.\n  Step by step: docs/INSTALL.md (section %s)\n', os, os);
    else
        fprintf('  Ready. Start the lab with:  enr312_lab\n');
    end
    if any(strcmp(varargin, 'save')), savepath; fprintf('  The MATLAB path is saved for future sessions.\n'); end
    fprintf('\n');
    ok = ~any(need(1:min(3, end)));   % MATLAB and the simulation are what the simulator needs
    if any(strcmp(varargin, 'open')), enr312_lab; end
    if nargout == 0, clear ok; end
end

function v = ternary(c, a, b), if c, v = a; else, v = b; end, end

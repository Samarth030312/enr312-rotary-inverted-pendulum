function exp005_run_analysis()
%EXP005_RUN_ANALYSIS  Top-level EXP005 (Tutorial 5) entry point.
%
%   addpath(genpath(fullfile(<repo>,'matlab'))); exp005_run_analysis
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.
%
%   SAFETY: this analysis describes the INVERTED (unstable) configuration.
%   Nothing here should be taken to hardware without the procedure in
%   experiments/EXP005/PROCEDURE.md, which requires a second person.

    root   = odyssix.repoRoot();
    figDir = fullfile(root, 'results', 'figures');
    if ~isfolder(figDir), mkdir(figDir); end

    fprintf('EXP005 analysis -- repository root: %s\n', root);
    fprintf('MATLAB %s\n\n', version);

    exp005_validate_inverted();

    designs = { 'Stable System 1',       9.00,  9.00; ...
                'Quasi-Stable System 2', 10.00, 3.33; ...
                'System 1 design',        6.25,  7.00; ...
                'System 2 design',        0.50, 10.75 };
    exp005_plot_inverted(designs, figDir);

    fprintf(['\nEXP005 MATLAB analysis complete.\n' ...
             'Record MATLAB version, toolboxes, date and repository revision in\n' ...
             'experiments/EXP005/MEASUREMENTS.md and change NOT_EXECUTED to EXECUTED.\n\n']);
end

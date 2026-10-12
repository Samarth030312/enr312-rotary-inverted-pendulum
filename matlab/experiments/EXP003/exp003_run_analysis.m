function exp003_run_analysis()
%EXP003_RUN_ANALYSIS  Top-level EXP003 (Tutorial 3) entry point.
%
%   addpath(genpath(fullfile(<repo>,'matlab'))); exp003_run_analysis
%
%   All paths derive from odyssix.repoRoot(); nothing is hardcoded.
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    root   = odyssix.repoRoot();
    figDir = fullfile(root, 'results', 'figures');
    if ~isfolder(figDir), mkdir(figDir); end

    fprintf('EXP003 analysis -- repository root: %s\n', root);
    fprintf('MATLAB %s\n\n', version);

    exp003_validate_mimo_model();

    designs = { 'Design 1', 6.00, 4.800; ...
                'Design 2', 1.50, 1.725; ...
                'Design 3', 0.30, 0.750 };
    exp003_plot_control_effort(designs, figDir);

    fprintf(['\nEXP003 MATLAB analysis complete.\n' ...
             'Record MATLAB version, toolboxes, date and repository revision in\n' ...
             'experiments/EXP003/MEASUREMENTS.md and change NOT_EXECUTED to EXECUTED.\n\n']);
end

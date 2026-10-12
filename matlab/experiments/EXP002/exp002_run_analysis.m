function exp002_run_analysis()
%EXP002_RUN_ANALYSIS  Top-level EXP002 (Tutorial 2) entry point.
%
%   Usage, from any directory:
%       addpath(genpath(fullfile(<repo>,'matlab')));
%       exp002_run_analysis
%
%   All paths derive from odyssix.repoRoot(); nothing is hardcoded.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    root   = odyssix.repoRoot();
    figDir = fullfile(root, 'results', 'figures');
    if ~isfolder(figDir), mkdir(figDir); end

    fprintf('EXP002 analysis -- repository root: %s\n', root);
    fprintf('MATLAB %s\n\n', version);

    exp002_validate_sensitivity_model();

    m1 = exp002_sensitivity_model(5.00, 2.5);   % Tutorial 1 design
    m2 = exp002_sensitivity_model(6.55, 4.0);   % EXP002 selected design
    exp002_plot_sensitivity(m1, m2, figDir);

    fprintf(['\nEXP002 MATLAB analysis complete.\n' ...
             'Record MATLAB version, release, toolboxes, date and repository\n' ...
             'revision in experiments/EXP002/MEASUREMENTS.md, and change the\n' ...
             'execution status from NOT_EXECUTED to EXECUTED.\n\n']);
end

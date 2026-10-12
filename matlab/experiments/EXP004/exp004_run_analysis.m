function exp004_run_analysis()
%EXP004_RUN_ANALYSIS  Top-level EXP004 (Tutorial 4) entry point.
%
%   addpath(genpath(fullfile(<repo>,'matlab'))); exp004_run_analysis
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    root   = odyssix.repoRoot();
    figDir = fullfile(root, 'results', 'figures');
    if ~isfolder(figDir), mkdir(figDir); end

    fprintf('EXP004 analysis -- repository root: %s\n', root);
    fprintf('MATLAB %s\n\n', version);

    exp004_validate_sensitivity();

    designs = { 'Reference (6, 4.8)', 6.00, 4.80; ...
                'Design A (<1 dB)',   1.20, 1.50; ...
                'Design B (<3 dB)',   0.25, 4.80 };
    exp004_plot_sensitivity_nyquist(designs, figDir);

    fprintf(['\nEXP004 MATLAB analysis complete.\n' ...
             'Record MATLAB version, toolboxes, date and repository revision in\n' ...
             'experiments/EXP004/MEASUREMENTS.md and change NOT_EXECUTED to EXECUTED.\n\n']);
end

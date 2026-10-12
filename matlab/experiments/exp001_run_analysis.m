function exp001_run_analysis()
%EXP001_RUN_ANALYSIS  Top-level EXP001 analysis entry point.
%
%   Runs parameter-consistency checking, model validation, and figure
%   generation for EXP001 (Actuator and Angle Sensing).
%
%   Usage, from any directory:
%       addpath(genpath(fullfile(<repo>,'matlab')));
%       exp001_run_analysis
%
%   All paths are derived from odyssix.repoRoot(); nothing is hardcoded.
%
%   WHAT THIS DOES NOT DO. It contains no plant model, no controller and no
%   dynamics -- EXP001 deliberately has none (FIRST_PRINCIPLES.md section 6).
%   It also produces NO experimental results: no measured data exists.
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    root = odyssix.repoRoot();
    figDir = fullfile(root, 'results', 'figures');
    if ~isfolder(figDir)
        mkdir(figDir);
    end

    fprintf('EXP001 analysis -- repository root: %s\n', root);
    fprintf('MATLAB %s\n\n', version);

    % 1. The firmware and the model must agree before anything else is trusted.
    exp001_check_parameter_consistency();

    % 2. Validate the analytic model against hand-derived and simulated values.
    exp001_validate_sensing_model();

    % 3. Figures.
    p = odyssix.rigParams();
    m = exp001_sensing_model(p);
    exp001_plot_quantisation(p, m, figDir);
    exp001_plot_step_rate(p, figDir);

    fprintf(['\nEXP001 MATLAB analysis complete.\n' ...
             'Record MATLAB version, release, toolboxes, date and repository\n' ...
             'revision in experiments/EXP001/MEASUREMENTS.md, and change the\n' ...
             'execution status from NOT_EXECUTED to EXECUTED.\n\n']);
end

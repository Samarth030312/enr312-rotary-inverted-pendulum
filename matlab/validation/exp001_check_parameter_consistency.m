function ok = exp001_check_parameter_consistency()
%EXP001_CHECK_PARAMETER_CONSISTENCY  Verify the three parameter sources agree.
%
%   The same rig constants appear in three places:
%       shared/parameters/edukit01_rig.yaml       (the record of provenance)
%       firmware/enr312/inc/enr312_rig_config.h   (what the target executes)
%       matlab/+odyssix/rigParams.m               (what the model uses)
%
%   The engineering standards (docs/ENGINEERING_STANDARDS.md §13) forbid silently duplicating a parameter with different values.
%   Duplication here is unavoidable -- the three consumers cannot share a file
%   across C, YAML and MATLAB -- so the duplication is made SAFE by checking it
%   rather than by trusting it.
%
%   This function parses the C header (the target's authority on what actually
%   runs) and compares against odyssix.rigParams().
%
%   EXECUTION STATUS: NOT_EXECUTED -- MATLAB EXECUTION ENVIRONMENT REQUIRED.

    root   = odyssix.repoRoot();
    hdr    = fullfile(root, 'firmware', 'enr312', 'inc', 'enr312_rig_config.h');
    if ~isfile(hdr)
        error('odyssix:exp001:missingHeader', 'Not found: %s', hdr);
    end
    txt = fileread(hdr);
    p   = odyssix.rigParams();

    ok = true;
    ok = cmp(ok, 'ENCODER_PPR',              grabInt(txt,'ENR312_ENCODER_PPR'),            p.encoder.ppr);
    ok = cmp(ok, 'ENCODER_DECODE_X',         grabInt(txt,'ENR312_ENCODER_DECODE_X'),       p.encoder.decodeX);
    ok = cmp(ok, 'MOTOR_FULL_STEPS_PER_REV', grabInt(txt,'ENR312_MOTOR_FULL_STEPS_PER_REV'), p.rotor.fullStepsPerRev);
    ok = cmp(ok, 'MOTOR_MICROSTEP_DIVISOR',  grabInt(txt,'ENR312_MOTOR_MICROSTEP_DIVISOR'), p.rotor.microstepDiv);
    ok = cmp(ok, 'ENCODER_COUNTER_BITS',     grabInt(txt,'ENR312_ENCODER_COUNTER_BITS'),   p.encoder.counterBits);
    ok = cmp(ok, 'STEP_TIMER_PRESCALER',     grabInt(txt,'ENR312_STEP_TIMER_PRESCALER'),   p.step.prescaler);
    ok = cmp(ok, 'ENCODER_POLARITY',         grabInt(txt,'ENR312_ENCODER_POLARITY'),       p.encoder.polarity);
    ok = cmp(ok, 'ROTOR_POLARITY',           grabInt(txt,'ENR312_ROTOR_POLARITY'),         p.rotor.polarity);

    if ok
        fprintf('Parameter consistency: firmware header and MATLAB agree.\n');
    else
        error('odyssix:exp001:parameterMismatch', ...
              ['Firmware and MATLAB parameters disagree. Reconcile against ', ...
               'shared/parameters/edukit01_rig.yaml before running anything.']);
    end
end

function v = grabInt(txt, name)
    % Match "#define <name> <optional (> <signed int>" and ignore any comment.
    tok = regexp(txt, ['#define\s+' name '\s+\(?\s*([+-]?\d+)'], 'tokens', 'once');
    if isempty(tok)
        error('odyssix:exp001:defineNotFound', 'No #define for %s', name);
    end
    v = str2double(tok{1});
end

function ok = cmp(ok, name, fromC, fromM)
    match = (fromC == fromM);
    if match
        verdict = 'ok';
    else
        verdict = 'MISMATCH';
    end
    fprintf('  %-26s firmware %-8g matlab %-8g  %s\n', name, fromC, fromM, verdict);
    ok = ok && match;
end

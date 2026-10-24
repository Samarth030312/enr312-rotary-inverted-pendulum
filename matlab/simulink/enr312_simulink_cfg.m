function cfg = enr312_simulink_cfg(P)
%ENR312_SIMULINK_CFG  The firmware configuration (odyssix.sim.defaults form) held in P.
%
%   cfg = enr312_simulink_cfg(P)    P from enr312_simulink_params
%   Every firmware field of odyssix.sim.defaults(P.exp) is taken from P, so a value
%   changed in P (P.kpp = 200) is what the firmware block runs and what the
%   comparison with odyssix.sim.runCtrl uses.
    cfg = odyssix.sim.defaults(P.exp);
    for f = fieldnames(cfg)'
        n = f{1};
        if strcmp(n, 'wg2'), cfg.wg2 = P.fw_wg2;
        elseif strcmp(n, 'seconds'), cfg.seconds = P.stopTime;
        elseif isfield(P, n), cfg.(n) = P.(n);
        end
    end
    if ~isfield(cfg, 'amp'), cfg.amp = 180; end
end

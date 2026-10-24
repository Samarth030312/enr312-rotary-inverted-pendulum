function [v, u, phase, ref, held] = enr312_fw_tick(first, rotor, psiMeas, P)
%ENR312_FW_TICK  One firmware tick, called by the model's Firmware block every 2 ms.
%
%   first = true on the first tick of a simulation: a fresh firmware is started
%   (as at reset). The state lives in an Enr312Firmware object between calls.
    persistent fw
    if first || isempty(fw), fw = Enr312Firmware(P); end
    [v, u, phase, ref, held] = fw.tick(rotor, psiMeas);
    held = double(held);
end

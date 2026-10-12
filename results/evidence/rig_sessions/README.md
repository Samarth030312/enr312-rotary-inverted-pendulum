# Rig session logs (hardware only)

Raw serial transcripts of every session on the physical rig, as written by the
MATLAB apps (`>>` = sent to the board, `D,…` = 50 Hz telemetry, other lines =
firmware messages). Compressed with gzip; read with `zcat file.log.gz | less`.

Telemetry line: `D,<tick 2 ms>,<rotor mdeg>,<pendulum mdeg>,<encoder raw>,<faults>,<state>,<run exp>,<phase>,<u deg/s^2>,<ref mdeg>,<isr_max_us>`.

`flash_*.log` are the programmer transcripts of each verified flash (device ID,
image SHA-256). Emulator sessions are not kept here.

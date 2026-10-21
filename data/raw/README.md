# Raw rig data (read-only)

One folder per experiment, one CSV per run, exactly as the rig sent it. Files here are
never changed or deleted. Anything derived from them goes to `../processed/`. Each run
has a metadata file with the same name in `../metadata/`.

Columns, units, naming and how to load a run: [`../README.md`](../README.md).

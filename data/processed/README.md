# Processed Data

Derived from `../raw/`. Every processed dataset must identify its source raw dataset and
the processing script and revision that produced it.

No processed datasets are stored yet: every figure and table in `results/` is computed straight from `../raw/` by the scripts in `matlab/plotting/` and `matlab/experiments/`.

Running `python3 scripts/exp001_process_measurements.py --selftest` writes
`EXP001_selftest_synthetic.csv` here. That file is **synthetic**, is git-ignored, and
exists only to exercise the parser and acceptance logic. It is not evidence of anything.

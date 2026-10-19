# Data

`raw/` holds the six CSV files produced by `src/generate_data.py`. They contain deliberately injected data-quality problems that the cleaning layer must fix. See `docs/data_dictionary.md`.

The answer key (`ground_truth/`) is not committed. Generate it locally with `python src/generate_data.py`.

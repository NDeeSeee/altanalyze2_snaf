## GTEx Data Processing Scripts

This directory contains a streamlined, production-focused set of tools to organize GTEx v10 samples, generate WDL inputs, and validate BAM/BAI file availability before running splicing analysis.

### Scripts

- **`organize_gtex_samples.py`**: Parse GTEx sample annotations and produce per-tissue directories with `sample_ids.csv` and `metadata.txt`.
  - Usage:
    ```bash
    python organize_gtex_samples.py
    ```
  - Output:
    - `gtex_organized/`

- **`generate_input_jsons.py`**: Create WDL input JSON files per tissue using organized sample IDs and default config.
  - Usage:
    ```bash
    python generate_input_jsons.py
    ```
  - Output:
    - `../../workflows/splicing_analysis/inputs/gtex_v10/` with files named `{tissue}_{count}.json`
  - Notes:
    - Uses default configuration from `../../inputs/default_configs.json` if present; otherwise falls back to sensible defaults.

- **`validate_and_filter_inputs.py`**: Check that BAM/BAI files exist in Google Cloud Storage (`gsutil stat`), then write filtered inputs and reports.
  - Usage:
    ```bash
    # Validate all tissues (requires gsutil)
    python validate_and_filter_inputs.py

    # Validate a specific tissue
    python validate_and_filter_inputs.py --tissue cervix_uteri_88

    # Custom directories
    python validate_and_filter_inputs.py \
      --input-dir ../../workflows/splicing_analysis/inputs/gtex_v10 \
      --output-dir ../../workflows/splicing_analysis/inputs/gtex_v10_validated \
      --report-dir ./validation_reports
    ```
  - Output:
    - `../../workflows/splicing_analysis/inputs/gtex_v10_validated/` filtered JSON files
    - `validation_reports/` summaries and per-tissue reports

- **`realistic_validation_demo.py`**: Canonical demonstration using the actual Terra failure list for cervix uteri (88 samples). Produces a filtered JSON and a concise analysis report that mirrors real-world outcomes.
  - Usage:
    ```bash
    python realistic_validation_demo.py
    ```
  - Output (created on run):
    - `realistic_output/cervix_uteri_validated_55samples.json`
    - `realistic_reports/cervix_uteri_realistic_analysis.txt`

### Recommended Workflow

1. Organize data: `python organize_gtex_samples.py`
2. Generate inputs: `python generate_input_jsons.py`
3. Validate inputs (recommended): `python validate_and_filter_inputs.py`
4. Use validated inputs: run WDL using files from `../../workflows/splicing_analysis/inputs/gtex_v10_validated/`

### Why validation matters

- Some GTEx samples listed in metadata lack BAM/BAI files in the bucket; running without validation can cause widespread task failures.
- Validation ensures inputs reference only existing files, improving success rates and saving cost/time.

### Requirements

- Python 3.6+
- Google Cloud SDK (`gsutil`) for real validation
- Read access to the GTEx GCS bucket

### Notes on cleanup

- Legacy demo scripts and generated demo artifacts were removed to avoid confusion. The authoritative demo is `realistic_validation_demo.py`.

### File structure (key items)

```
data/gtex/
├── GTEx_Analysis_2022-06-06_v10_Annotations_SampleAttributesDS.txt
├── organize_gtex_samples.py
├── generate_input_jsons.py
├── validate_and_filter_inputs.py
├── realistic_validation_demo.py
├── gtex_organized/
└── validation_reports/
```
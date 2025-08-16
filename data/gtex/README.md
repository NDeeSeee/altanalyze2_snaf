## GTEx Data Processing Scripts

This directory contains tools to organize GTEx v10 samples, generate WDL inputs, and validate BAM/BAI file availability before running splicing analysis.

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

- **`validate_and_filter_inputs.py`**: Production validator. Checks that BAM/BAI files exist in Google Cloud Storage (`gsutil stat` with concurrency and retries), then writes filtered inputs and reports. Defaults tuned for GTEx and requester pays.
  - Usage:
    ```bash
    # Validate all tissues (requires gsutil; defaults include billing project snaf-workflow-wdl)
    python validate_and_filter_inputs.py --all

    # Validate a specific tissue
    python validate_and_filter_inputs.py --tissue cervix_uteri_88

    # Custom directories and tuning
    python validate_and_filter_inputs.py \
      --input-dir ../../workflows/splicing_analysis/inputs/gtex_v10 \
      --output-dir ../../workflows/splicing_analysis/inputs/gtex_v10_validated \
      --report-dir ./validation_reports \
      --billing-project snaf-workflow-wdl \
      --max-workers 32 --stat-timeout-seconds 20 --stat-retries 3
    ```
  - Output:
    - `../../workflows/splicing_analysis/inputs/gtex_v10_validated/` filtered JSON files (only existing files)
    - `validation_reports/`:
      - `validation_summary.json` and `validation_summary.txt`
      - `{tissue}_validation_report.json`
      - `{tissue}_summary.txt` (concise human-readable summary)

### Recommended Workflow

1. Organize data: `python organize_gtex_samples.py`
2. Generate inputs: `python generate_input_jsons.py`
3. Validate inputs: `python validate_and_filter_inputs.py`
4. Use validated inputs: run WDL using files from `../../workflows/splicing_analysis/inputs/gtex_v10_validated/`

### Why validation matters

- Some GTEx samples listed in metadata lack BAM/BAI files in the bucket; running without validation can cause widespread task failures.
- Validation ensures inputs reference only existing files, improving success rates and saving cost/time.

### Requirements

- Python 3.6+
- Google Cloud SDK (`gsutil`) for real validation
- Read access to the GTEx GCS bucket

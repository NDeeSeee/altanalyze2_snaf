## GTEx Data Processing and Validation (GTEx v10)

This directory contains tools to organize GTEx v10 samples, generate WDL inputs, and validate BAM/BAI file availability before running splicing analysis. It also documents how to approximate the set of “valid” samples directly from GTEx annotation files without hitting GCS.

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
  - Annotations-only mode (no GCS access required):
    ```bash
    # Produce annotations metrics in data/gtex/validation_reports
    python validate_and_filter_inputs.py --annotations-only \
      --annotations-summary-dir ./validation_reports
    ```
    - Writes: `valid_ids.txt` (if any validated IDs already exist), `validity_by_columns.tsv`, `columns_overview_SAMPLE.tsv`, `columns_overview_SUBJECT.tsv`, and per-column value counts under `validation_reports/counts/`.

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

### What is a “valid” sample here?

Operationally, a sample is treated as valid when both its BAM and BAI exist at the exact path pattern used by `generate_input_jsons.py`:

```
gs://<workspace-bucket>/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files/<SAMPID>.Aligned.sortedByCoord.out.patched.md.bam(.bai)
```

The validation reports summarize existence checks per tissue. In our latest run (2025-08-16) we observed:

- Total original rows in annotations: 48,231
- Total validated: 22,970 (overall ~47.6%)

### Can we predict the 22,970 without checking GCS?

Yes—very closely—by using only columns from `GTEx_Analysis_2022-06-06_v10_Annotations_SampleAttributesDS.txt`. The following rule matches ≥99.99% of the validated set and yields no false positives on our data:

- Include rows where:
  - `ANALYTE_TYPE == "RNA:Total RNA"`, and
  - `SMGEBTCHT == "TruSeq.v1"`, and
  - `SAMPID` prefix is not `BMS` (exclude `BMS-…` samples), and
  - `SMOMTRLTP != "Whole Blood: Whole Blood"`.

Using this rule on the annotations:

- Predicted positives: 22,968
- True positives vs validated list: 22,968
- False positives: 0
- False negatives: 2
- Precision: 1.0000, Recall: 0.9999

Those two false negatives are edge cases visible in annotations:

- `GTEX-1N2DV-0006-SM-GPRXT` (Whole blood PAXgene RNA-seq; validated but excluded by the strict “not Whole Blood: Whole Blood” clause)
- `GTEX-O5YV-0526-SM-2D7VZ` (PAXgene RNA with `SMGEBTCHT == Tech Dev`; annotated as RNA-seq-like but not `TruSeq.v1`)

If we slightly relax the rule to allow `SMGEBTCHT` in {`TruSeq.v1`, `Tech Dev`} and still exclude `BMS` and `Whole Blood: Whole Blood`, recall becomes 1.0000 with ~0.1% false positives.

#### Why does this rule work?

- All validated samples are `RNA:Total RNA` and overwhelmingly have `SMGEBTCHT == TruSeq.v1` (the bulk RNA-seq prep for GTEx v10).
- All `BMS-…` samples in the annotations are absent from the workspace bucket used here, so excluding prefix `BMS` matches observed validation.
- `Whole Blood: Whole Blood` rows are present in annotations but do not correspond to the BAMs present at the expected path in the workspace bucket; excluding them aligns with observed validation.

#### Additional observed patterns (annotations-only comparisons)

- By prefix: `K-…` (K-562 cell line) have a ~93.6% validation rate; `BMS-…` 0%; `GTEX-…` ~49% overall.
- By tissue subtype (`SMTSD`): rates vary across subtypes in a pattern similar to the per-tissue validation summary (e.g., blood lower, adipose higher) but largely explained by the rule above plus bucket presence.
- RNA quality (`SMRIN`) has no strong discriminative power between validated vs non (means ~7.26 vs ~7.28 among rows with values).

### Practical use

- To approximate the validated set without GCS access, filter the annotations using the rule above. The result will very closely match the `validation_reports` counts produced by real GCS checks.
- The authoritative truth still comes from object existence checks; bucket content or path conventions may change.

### Files of interest

- `validation_reports/validation_summary.(txt|csv|json)` — overall counts and per-tissue success rates
- `gtex_organized/*/validated/sample_ids.csv` — validated SAMPID lists per tissue
- `GTEx_Analysis_2022-06-06_v10_Annotations_SampleAttributesDS.txt` — source used for prediction without GCS
- `validation_reports/valid_ids.txt` — combined validated sample IDs aggregated from per-tissue outputs (if available)
- `validation_reports/validity_by_columns.tsv` — validation rates by key annotation columns (produced with `--emit-annotations-metrics` or `--annotations-only`)
- `validation_reports/columns_overview_SAMPLE.tsv`, `validation_reports/columns_overview_SUBJECT.tsv` — per-file column overviews (unique values, fill rates, total rows)
- `validation_reports/counts/` — per-column value counts as TSV files for Sample and Subject annotation files

### Generate annotations-only metrics

To write `validity_by_columns.tsv`, `columns_overview_*.tsv`, and per-column counts under `validation_reports/counts/` alongside validation reports after a validation run:

```bash
python validate_and_filter_inputs.py --all --emit-annotations-metrics \
  --report-dir ./validation_reports \
  --annotations-summary-dir ./validation_reports
```

Or, without running validation (no GCS access needed):

```bash
python validate_and_filter_inputs.py --annotations-only \
  --annotations-summary-dir ./validation_reports
```

This mode reads `GTEx_Analysis_2022-06-06_v10_Annotations_SampleAttributesDS.txt` (and `...SubjectPhenotypesDS.txt` if present) located in this directory.

### Directory hygiene recommendations

- Keep generated, bulky per-column counts under `validation_reports/counts/` to avoid clutter.
- Consider adding `.gitignore` entries to exclude `validation_reports/counts/` if repository size becomes a concern.
- Reserve `gtex_organized/*/validated/` for final validated lists; avoid storing large intermediates there.

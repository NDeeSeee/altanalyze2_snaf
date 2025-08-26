# Terra shared utilities

- Use `workflows/terra/env.example.sh` as the global environment template. Copy it to `workflows/terra/env.sh` and fill in your workspace details. Workflow-specific scripts will source this if present.
- Validators:
  - You can run `workflows/splicing_analysis/terra_runs/validate_inputs_against_wdl.py` to check inputs against the current WDL.
  - `workflows/splicing_analysis/terra_runs/fix_gtex_inputs.py` removes legacy keys from GTEx JSONs.

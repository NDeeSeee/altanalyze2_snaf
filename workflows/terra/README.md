# Terra shared utilities

- Use `workflows/terra/env.example.sh` as the global environment template. Copy it to `workflows/terra/env.sh` and fill in your workspace details. Workflow-specific scripts will source this if present.
- Validators:
  - You can run `workflows/splicing_analysis/terra_runs/validate_inputs_against_wdl.py` to check inputs against the current WDL.
  - `workflows/splicing_analysis/terra_runs/fix_gtex_inputs.py` removes legacy keys from GTEx JSONs.

## Importing TCGA (GDC) files into Terra data tables

You can populate Terra data tables (sample and sample_set) from GDC sheets/manifests or DRS TSVs and then submit workflows referencing table attributes.

1) Build Terra TSVs from GDC DRS or manifest:
```bash
python workflows/terra/build_terra_tables.py \
  --drs-tsv data/tcga/uvm/drs.tsv \
  --set-name tcga_uvm_set \
  --out-dir workflows/terra/exports

# or, from a GDC manifest + your bucket prefix
python workflows/terra/build_terra_tables.py \
  --gdc-manifest data/tcga/uvm/gdc_manifest.2025-08-12.184644.txt \
  --prefix gs://YOUR_BUCKET/tcga/uvm \
  --set-name tcga_uvm_set \
  --out-dir workflows/terra/exports
```

This writes:
- `entities_sample.tsv` with columns like `entity:sample_id`, `bam`, `bai`
- `entities_sample_set.tsv` linking all samples under `tcga_uvm_set`

2) Import TSVs into Terra workspace (GUI: Data tab → Import table). CLI via FISS:
```bash
fissfc upload_entities -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" \
  -t sample -f workflows/terra/exports/entities_sample.tsv

fissfc upload_entities -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" \
  -t sample_set -f workflows/terra/exports/entities_sample_set.tsv
```

3) Submit workflow using table attributes (via config or Rawls input expressions), e.g.:
- Set inputs to expressions like `this.bam` and `this.bai`
- Run against the `sample_set` entity selecting `tcga_uvm_set` as the row

You can automate step 3 using `workflows/splicing_analysis/terra_runs/terra_rawls_submit.sh` by first creating/updating a method config whose inputs are set to `this.*` expressions.

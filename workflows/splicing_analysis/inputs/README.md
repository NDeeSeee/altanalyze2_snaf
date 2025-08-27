# SplicingAnalysis inputs

- `splicing_analysis.input.example.json` is validated against the current `workflows/splicing_analysis/splicing_analysis.wdl`.
- GTEx tissue JSONs are large, prevalidated sets. They should not contain keys not present in the WDL. If you see legacy keys like `*_disk_space`, run:

```bash
python3 workflows/splicing_analysis/terra_runs/fix_gtex_inputs.py
```

- To use a different AltAnalyze image, edit `SplicingAnalysis.docker_image` in your JSON or set `ALTANALYZE_DOCKER_DEFAULT` in `terra_runs/env.sh`.

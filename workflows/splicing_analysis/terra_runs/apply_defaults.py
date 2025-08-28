#!/usr/bin/env python3
"""
Apply defaults from a single JSON file to all GTEx validated input files.
- Merges keys (defaults override or fill missing values)
- Strips non-WDL metadata and legacy keys
- Keeps filenames aligned with <tissue>_<validcount>.json

Usage:
  python workflows/splicing_analysis/terra_runs/apply_defaults.py \
    --defaults workflows/splicing_analysis/inputs/gtex_defaults.json \
    --inputs-dir workflows/splicing_analysis/inputs/gtex_v10_validated

You can edit gtex_defaults.json once and re-run to update all.
"""
import argparse
import json
from pathlib import Path
from data.gtex.validate_and_filter_inputs import (
    ensure_validated_filename_matches,
    strip_metadata_and_inject_defaults_inplace,
)

def merge_defaults(data: dict, defaults: dict) -> dict:
    updated = data.copy()
    for k, v in defaults.items():
        # If key missing or value differs, set to defaults (explicit override)
        if k not in updated or updated.get(k) != v:
            updated[k] = v
    return updated


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--defaults", required=True)
    p.add_argument("--inputs-dir", required=True)
    args = p.parse_args()

    defaults_path = Path(args.defaults)
    inputs_dir = Path(args.inputs_dir)

    defaults = json.loads(defaults_path.read_text())

    changed = 0
    for jf in sorted(inputs_dir.glob("*.json")):
        try:
            data = json.loads(jf.read_text())
        except Exception:
            continue
        # Merge defaults, strip metadata/non-WDL keys, ensure docker/extra_bed present
        merged = merge_defaults(data, defaults)
        merged, _ = strip_metadata_and_inject_defaults_inplace(merged)
        if merged != data:
            jf.write_text(json.dumps(merged, indent=2) + "\n")
            ensure_validated_filename_matches(jf)
            changed += 1
    print(f"Updated {changed} JSON files under {inputs_dir}")

if __name__ == "__main__":
    main()

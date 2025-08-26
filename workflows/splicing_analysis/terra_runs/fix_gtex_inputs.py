#!/usr/bin/env python3
"""
Removes invalid disk_space keys from GTEx input JSONs to match current WDL.
- Removes: 
  - SplicingAnalysis.bam_to_bed_disk_space
  - SplicingAnalysis.junction_analysis_disk_space
Writes changes in place; creates a .bak copy for safety.
"""
import json
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
INPUT_DIRS = [
    BASE / "inputs" / "gtex_v10_validated",
    BASE / "inputs" / "gtex_v10",
]

INVALID_KEYS = {
    "SplicingAnalysis.bam_to_bed_disk_space",
    "SplicingAnalysis.junction_analysis_disk_space",
}

def process_file(path: Path) -> bool:
    try:
        text = path.read_text()
        data = json.loads(text)
    except Exception as e:
        print(f"[SKIP] {path}: cannot parse JSON ({e})")
        return False

    before = set(k for k in data.keys() if k in INVALID_KEYS)
    if not before:
        return False

    # Remove keys
    for k in list(before):
        data.pop(k, None)

    # Write back (compact but stable ordering)
    with path.open("w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"[FIXED] {path.name}: removed {', '.join(sorted(before))}")
    return True


def main() -> int:
    changed = 0
    seen_any = False
    for input_dir in INPUT_DIRS:
        if not input_dir.is_dir():
            continue
        seen_any = True
        for p in sorted(input_dir.glob("*.json")):
            if process_file(p):
                changed += 1

    if not seen_any:
        print("No GTEx input directories found.", file=sys.stderr)
        return 1

    print(f"Done. Files changed: {changed}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

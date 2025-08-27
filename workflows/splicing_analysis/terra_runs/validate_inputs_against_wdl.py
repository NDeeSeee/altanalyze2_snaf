#!/usr/bin/env python3
"""
Validate JSON inputs against the workflow input variables in splicing_analysis.wdl.
- Extracts the names from the `workflow SplicingAnalysis` input block
- Flags unknown keys in JSON (those not present in WDL)
- Checks BAM/BAI array length equality (if both provided)
Usage:
  python3 workflows/splicing_analysis/terra_runs/validate_inputs_against_wdl.py [json_or_dir ...]
If no arguments are given, validates all *.json under inputs/gtex_v10_validated and inputs/gtex_v10.
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path
from typing import Iterable, Set, Tuple

RE_WORKFLOW_START = re.compile(r"^\s*workflow\s+SplicingAnalysis\s*{\s*$")
RE_INPUT_START = re.compile(r"^\s*input\s*{\s*$")
RE_BLOCK_END = re.compile(r"^\s*}\s*$")
RE_VAR_LINE = re.compile(r"^\s*[A-Za-z\[\]0-9_, ]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*(=|$)")

ROOT = Path(__file__).resolve().parents[1]
WDL_PATH = ROOT / "splicing_analysis.wdl"
DEFAULT_DIRS = [
    ROOT / "inputs" / "gtex_v10_validated",
    ROOT / "inputs" / "gtex_v10",
]


def read_wdl_input_names(path: Path) -> Set[str]:
    names: Set[str] = set()
    in_workflow = False
    in_input = False
    for line in path.read_text().splitlines():
        if not in_workflow:
            if RE_WORKFLOW_START.match(line):
                in_workflow = True
            continue
        if in_workflow and not in_input:
            if RE_INPUT_START.match(line):
                in_input = True
            continue
        if in_workflow and in_input:
            if RE_BLOCK_END.match(line):
                break
            m = RE_VAR_LINE.match(line)
            if m:
                names.add(m.group(1))
    return names


def discover_json_files(args: Iterable[str]) -> Iterable[Path]:
    if args:
        for a in args:
            p = Path(a)
            if p.is_dir():
                yield from p.glob("*.json")
            elif p.is_file() and p.suffix == ".json":
                yield p
    else:
        for d in DEFAULT_DIRS:
            if d.is_dir():
                yield from d.glob("*.json")


def validate_json(path: Path, allowed: Set[str]) -> Tuple[int, int, int]:
    unknown = 0
    missing = 0
    failures = 0
    try:
        data = json.loads(path.read_text())
    except Exception as e:
        print(f"[ERROR] {path}: cannot parse JSON: {e}")
        return (0, 0, 1)

    keys = set(data.keys())
    # Only check keys under SplicingAnalysis.*
    unknown_keys = sorted(k for k in keys if k.startswith("SplicingAnalysis.") and k.split('.', 1)[1] not in allowed)
    if unknown_keys:
        print(f"[WARN] {path.name}: unknown keys: {', '.join(unknown_keys)}")
        unknown += len(unknown_keys)

    # BAM/BAI length equality if provided
    bam = data.get("SplicingAnalysis.bam_files")
    bai = data.get("SplicingAnalysis.bai_files")
    if isinstance(bam, list) and isinstance(bai, list):
        if len(bam) != len(bai):
            print(f"[WARN] {path.name}: BAM/BAI count mismatch: {len(bam)} vs {len(bai)}")
            failures += 1

    return (unknown, missing, failures)


def main(argv: list[str]) -> int:
    if not WDL_PATH.is_file():
        print(f"WDL not found: {WDL_PATH}", file=sys.stderr)
        return 2
    allowed = read_wdl_input_names(WDL_PATH)
    if not allowed:
        print("Could not extract workflow input names.", file=sys.stderr)
        return 2

    total_unknown = total_missing = total_fail = 0
    count = 0
    for jf in sorted(discover_json_files(argv[1:])):
        u, m, f = validate_json(jf, allowed)
        total_unknown += u
        total_missing += m
        total_fail += f
        count += 1

    print(f"Validated {count} JSON files. Unknown keys: {total_unknown}. Failures: {total_fail}.")
    return 0 if total_fail == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

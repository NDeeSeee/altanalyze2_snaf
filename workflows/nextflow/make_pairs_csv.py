#!/usr/bin/env python3
"""
Generate a Nextflow pairs CSV (sample,bam,bai) from a WDL inputs JSON file
for the SplicingAnalysis workflow.

- Reads keys:
  - SplicingAnalysis.bam_files (array)
  - SplicingAnalysis.bai_files (array)
- Derives sample name from BAM basename without .bam if no explicit sample provided.

Usage:
  python workflows/nextflow/make_pairs_csv.py --wdl-json input.json --output pairs.csv
"""
from __future__ import annotations
import argparse
import csv
import json
import os
from typing import List


def derive_sample_name(bam_path: str) -> str:
    base = os.path.basename(bam_path)
    if base.endswith('.bam'):
        base = base[:-4]
    return base


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--wdl-json', required=True, help='Path to WDL inputs JSON')
    parser.add_argument('--output', required=True, help='Output CSV path')
    args = parser.parse_args()

    with open(args.wdl_json, 'r') as f:
        data = json.load(f)

    bam_files: List[str] = data.get('SplicingAnalysis.bam_files', [])
    bai_files: List[str] = data.get('SplicingAnalysis.bai_files', [])

    if len(bam_files) != len(bai_files):
        raise SystemExit(
            f'BAM/BAI length mismatch: {len(bam_files)} vs {len(bai_files)}'
        )

    with open(args.output, 'w', newline='') as out:
        writer = csv.writer(out)
        writer.writerow(['sample', 'bam', 'bai'])
        for bam, bai in zip(bam_files, bai_files):
            sample = derive_sample_name(bam)
            writer.writerow([sample, bam, bai])


if __name__ == '__main__':
    main()

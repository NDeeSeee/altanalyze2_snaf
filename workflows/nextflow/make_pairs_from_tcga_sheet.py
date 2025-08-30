#!/usr/bin/env python3
"""
Convert a GDC sample sheet (TSV) or UUID/filename mapping into a Nextflow pairs CSV
(sample,bam,bai) for the splicing Nextflow pipeline.

Inputs supported:
- GDC sample sheet TSV (columns include "File Name", "Sample ID" or "Case ID")
- uuid_and_filename_cleaned.tsv (two-column TSV: uuid_and_filename, entity_name)

You must provide a --prefix (local dir, gs://, or s3://) where the BAM/BAI are stored.
The tool will construct full URIs as: {prefix}/{filename} and {prefix}/{filename}.bai

Usage:
  python workflows/nextflow/make_pairs_from_tcga_sheet.py \
    --sheet data/tcga/uvm/gdc_sample_sheet.2025-08-12.tsv \
    --prefix gs://YOUR_BUCKET/tcga/uvm \
    --output pairs.tcga.csv

Advanced:
  --bam-column "File Name" --sample-column "Sample ID"

Note:
  Ensure that the .bai objects exist alongside the .bam at the given prefix.
"""
from __future__ import annotations
import argparse
import csv
import os
from typing import Iterable, Tuple


def read_gdc_sheet(path: str, bam_col: str, sample_col: str | None) -> Iterable[Tuple[str, str]]:
    with open(path, newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if bam_col not in reader.fieldnames:
            raise SystemExit(f"Column '{bam_col}' not found in {path}. Columns: {reader.fieldnames}")
        for row in reader:
            bam_name = row[bam_col].strip()
            sample = None
            if sample_col and sample_col in row and row[sample_col].strip():
                sample = row[sample_col].strip()
            if not sample:
                sample = os.path.basename(bam_name).removesuffix(".bam")
            yield sample, bam_name


def read_uuid_mapping(path: str) -> Iterable[Tuple[str, str]]:
    # For uuid_and_filename_cleaned.tsv: use the 'entity_name' (filename) for both sample and bam name stem
    with open(path, newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        # Expect columns: uuid_and_filename, entity_name
        if "entity_name" not in reader.fieldnames:
            raise SystemExit(f"Expected 'entity_name' column in {path}. Columns: {reader.fieldnames}")
        for row in reader:
            filename = row["entity_name"].strip()
            sample = os.path.basename(filename).removesuffix(".bam")
            yield sample, filename


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", required=True, help="Path to GDC sample sheet TSV or uuid mapping TSV")
    ap.add_argument("--prefix", required=True, help="Prefix for BAM/BAI (local dir, gs://bucket/..., or s3://bucket/...)")
    ap.add_argument("--output", required=True, help="Output CSV path")
    ap.add_argument("--bam-column", default="File Name", help="Column name for BAM filename in GDC sheet")
    ap.add_argument("--sample-column", default=None, help="Optional sample id column (e.g., 'Sample ID' or 'Case ID')")
    ap.add_argument("--mode", choices=["gdc_sheet", "uuid_mapping", "auto"], default="auto",
                    help="Input mode: detect automatically, or force a schema")
    args = ap.parse_args()

    # Detect mode
    mode = args.mode
    if mode == "auto":
        with open(args.sheet, newline="") as f:
            reader = csv.reader(f, delimiter="\t")
            header = next(reader)
        if "File Name" in header:
            mode = "gdc_sheet"
        elif "entity_name" in header:
            mode = "uuid_mapping"
        else:
            raise SystemExit(f"Could not detect input schema for {args.sheet}. Header: {header}")

    if mode == "gdc_sheet":
        pairs_iter = read_gdc_sheet(args.sheet, args.bam_column, args.sample_column)
    else:
        pairs_iter = read_uuid_mapping(args.sheet)

    prefix = args.prefix.rstrip("/")
    with open(args.output, "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["sample", "bam", "bai"])
        count = 0
        for sample, bam_name in pairs_iter:
            bam_uri = f"{prefix}/{bam_name}"
            bai_uri = f"{bam_uri}.bai"
            w.writerow([sample, bam_uri, bai_uri])
            count += 1
    print(f"Wrote {count} rows to {args.output}")


if __name__ == "__main__":
    main()

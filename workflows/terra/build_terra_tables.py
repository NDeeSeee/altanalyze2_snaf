#!/usr/bin/env python3
"""
Build Terra data model TSVs (sample and sample_set) from GDC inputs.

Inputs supported:
- --drs-tsv: a TSV with columns: entity:drs_id, drs_uri, filename, ...
- --gdc-manifest: the GDC manifest (columns: id, filename, md5, size, state)
- --gdc-sample-sheet: the GDC sample sheet TSV (columns include File Name, Case ID, Sample ID)

Outputs:
- entities_sample.tsv  (header: entity:sample_id, bam, bai, case_id, filename, drs_id, drs_uri)
- entities_sample_set.tsv (header: membership:sample_set_id, sample)

Usage examples:
  python workflows/terra/build_terra_tables.py \
    --drs-tsv data/tcga/uvm/drs.tsv \
    --set-name tcga_uvm_set \
    --out-dir workflows/terra/exports

  python workflows/terra/build_terra_tables.py \
    --gdc-manifest data/tcga/uvm/gdc_manifest.2025-08-12.184644.txt \
    --prefix gs://YOUR_BUCKET/tcga/uvm \
    --set-name tcga_uvm_set \
    --out-dir workflows/terra/exports

Notes:
- For DRS, we set bam to the DRS URI; Terra will resolve it when used via data tables.
- BAI URIs are assumed to be filename + .bai alongside the BAM; adjust if you have explicit index files.
"""
from __future__ import annotations
import argparse
import csv
import os
from pathlib import Path
from typing import Iterable, Tuple, Dict


def ensure_out_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def rows_from_drs_tsv(path: Path) -> Iterable[Dict[str, str]]:
    with path.open(newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for r in reader:
            yield r


def rows_from_manifest(path: Path) -> Iterable[Dict[str, str]]:
    with path.open(newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for r in reader:
            yield r


def write_sample_tsv(rows: Iterable[Dict[str, str]], out_path: Path, *, prefix: str | None, from_drs: bool) -> int:
    header = [
        "entity:sample_id",
        "bam",
        "bai",
        "case_id",
        "filename",
        "drs_id",
        "drs_uri",
    ]
    count = 0
    with out_path.open("w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(header)
        for r in rows:
            if from_drs:
                drs_id = r.get("entity:drs_id") or r.get("drs_id") or ""
                drs_uri = r.get("drs_uri") or ""
                filename = r.get("filename") or os.path.basename(drs_uri) or drs_id
                sample_id = os.path.basename(filename).removesuffix(".bam")
                bam = drs_uri
                bai = f"{drs_uri}.bai"  # Terra/AnVIL can resolve associated index; override if needed
                case_id = r.get("case_id", "")
            else:
                file_id = r["id"].strip()
                filename = r["filename"].strip()
                sample_id = os.path.basename(filename).removesuffix(".bam")
                bam = f"{prefix.rstrip('/')}/{filename}"
                bai = f"{bam}.bai"
                case_id = r.get("case_id", "")
                drs_id = ""; drs_uri = ""
            w.writerow([sample_id, bam, bai, case_id, filename, (drs_id if from_drs else drs_id), (drs_uri if from_drs else drs_uri)])
            count += 1
    return count


def write_sample_set_tsv(set_name: str, sample_ids: Iterable[str], out_path: Path) -> int:
    with out_path.open("w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["membership:sample_set_id", "sample"])
        count = 0
        for sid in sample_ids:
            w.writerow([set_name, sid])
            count += 1
    return count


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--drs-tsv", help="Path to drs.tsv with DRS URIs")
    ap.add_argument("--gdc-manifest", help="Path to GDC manifest .txt")
    ap.add_argument("--gdc-sample-sheet", help="Optional: enhance with Case/Sample ID from GDC sample sheet TSV")
    ap.add_argument("--prefix", help="For manifest mode: gs:// or s3:// prefix where files reside")
    ap.add_argument("--set-name", required=True, help="Name of the Terra sample_set to create")
    ap.add_argument("--out-dir", required=True, help="Directory to write TSVs into")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    ensure_out_dir(out_dir)

    if args.drs_tsv:
        rows = list(rows_from_drs_tsv(Path(args.drs_tsv)))
        from_drs = True
        prefix = None
    elif args.gdc_manifest:
        if not args.prefix:
            raise SystemExit("--prefix is required with --gdc-manifest")
        rows = list(rows_from_manifest(Path(args.gdc_manifest)))
        from_drs = False
        prefix = args.prefix
    else:
        raise SystemExit("Provide either --drs-tsv or --gdc-manifest")

    samples_path = out_dir / "entities_sample.tsv"
    n = write_sample_tsv(rows, samples_path, prefix=prefix, from_drs=from_drs)

    # Collect sample_ids for set table
    sample_ids: list[str] = []
    with samples_path.open() as f:
        reader = csv.DictReader(f, delimiter="\t")
        for r in reader:
            sample_ids.append(r["entity:sample_id"])

    set_path = out_dir / "entities_sample_set.tsv"
    m = write_sample_set_tsv(args.set_name, sample_ids, set_path)

    print(f"Wrote {n} samples to {samples_path}")
    print(f"Wrote {m} memberships to {set_path}")


if __name__ == "__main__":
    main()

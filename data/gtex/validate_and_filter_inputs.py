#!/usr/bin/env python3
"""
Validate GTEx input files and create filtered versions with only existing BAM/BAI files.

This script performs real checks against Google Cloud Storage and is intended for
production use prior to launching workflows. It:
1) Verifies existence of BAM/BAI objects via `gsutil stat`
2) Creates filtered JSON inputs containing only existing files
3) Generates comprehensive JSON and text reports per tissue and overall
4) Supports concurrency and retries for faster, robust validation
"""

import json
import subprocess
import sys
from pathlib import Path
from collections import defaultdict
import argparse
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import time
import random
import gzip
import io
import csv
import os
from typing import Optional, Iterable, Tuple, Dict, Set

# Resolve paths relative to this script so it can be run from any CWD
SCRIPT_DIR = Path(__file__).resolve().parent

DEFAULT_INDEX_PATH = SCRIPT_DIR / ".gcs_index.json.gz"

def parse_gcs_url(gcs_url: str) -> Tuple[str, str]:
    """Return (bucket, blob_name) for a gs:// URL."""
    assert gcs_url.startswith("gs://"), f"Not a GCS URL: {gcs_url}"
    path = gcs_url[len("gs://"):]
    bucket, _, blob = path.partition('/')
    return bucket, blob

def detect_common_prefixes(json_files: Iterable[Path]) -> Set[str]:
    """Infer common gs:// prefixes from the BAM file lists across input JSONs."""
    prefixes: Set[str] = set()
    for jf in json_files:
        try:
            with open(jf, 'r') as f:
                data = json.load(f)
            for bam in data.get('SplicingAnalysis.bam_files', []):
                if not bam.startswith('gs://'):
                    continue
                # Keep up to the folder level
                bucket, blob = parse_gcs_url(bam)
                folder = blob.rsplit('/', 1)[0]
                prefixes.add(f"gs://{bucket}/{folder}/")
                break
        except Exception:
            continue
    return prefixes

def try_import_storage_client():
    try:
        from google.cloud import storage  # type: ignore
        return storage
    except Exception:
        return None

def list_objects_with_gcs_client(prefixes: Iterable[str], billing_project: Optional[str]) -> Set[str]:
    storage = try_import_storage_client()
    if storage is None:
        return set()
    client = storage.Client(project=billing_project) if billing_project else storage.Client()
    objects: Set[str] = set()
    for p in prefixes:
        bucket_name, prefix = parse_gcs_url(p)
        bucket = client.bucket(bucket_name, user_project=billing_project)
        for blob in client.list_blobs(bucket_or_name=bucket, prefix=prefix):
            objects.add(f"gs://{bucket_name}/{blob.name}")
    return objects

def list_objects_with_gsutil(prefixes: Iterable[str], billing_project: Optional[str]) -> Set[str]:
    # Use a single gsutil -m ls per prefix; aggregate outputs
    objects: Set[str] = set()
    for p in prefixes:
        cmd = ["gsutil"]
        if billing_project:
            cmd += ["-u", billing_project]
        cmd += ["-m", "ls", "-r", p + "**"]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
            if result.stdout:
                for line in result.stdout.splitlines():
                    line = line.strip()
                    if line.startswith("gs://") and not line.endswith(":"):
                        objects.add(line)
        except Exception:
            continue
    return objects

def gsutil_stat_batch(urls: Iterable[str], billing_project: Optional[str], timeout_seconds: int = 120) -> Set[str]:
    """Batch stat many urls via single gsutil -m stat -I. Returns set of urls that exist."""
    urls_list = [u for u in urls if u.startswith('gs://')]
    if not urls_list:
        return set()
    cmd = ["gsutil"]
    if billing_project:
        cmd += ["-u", billing_project]
    cmd += ["-m", "stat", "-I"]
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdin_data = "\n".join(urls_list) + "\n"
        try:
            out, err = proc.communicate(stdin_data, timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            proc.kill()
            return set()
        existed: Set[str] = set()
        # gsutil stat outputs blocks; we can approximate by scanning lines containing "URL: gs://..."
        if out:
            current_url = None
            for line in out.splitlines():
                if line.startswith("URL:"):
                    current_url = line.split("URL:", 1)[1].strip()
                    # Re-normalize
                    if current_url.startswith('gs://'):
                        existed.add(current_url)
        return existed
    except Exception:
        return set()

def save_index(index_paths: Set[str], index_path: Path, meta: Dict[str, str]):
    payload = {
        "metadata": meta,
        "objects": sorted(index_paths),
    }
    with gzip.open(index_path, 'wt', encoding='utf-8') as gz:
        json.dump(payload, gz)

def load_index(index_path: Path) -> Optional[Dict[str, object]]:
    try:
        with gzip.open(index_path, 'rt', encoding='utf-8') as gz:
            return json.load(gz)
    except Exception:
        return None

def ensure_index(input_dir: Path,
                 billing_project: Optional[str],
                 index_path: Path,
                 refresh: bool = False,
                 gcs_prefix: Optional[str] = None) -> Set[str]:
    if not refresh and index_path.exists():
        cached = load_index(index_path)
        if cached and isinstance(cached.get('objects'), list):
            return set(cached['objects'])

    # Build index
    json_files = list(Path(input_dir).glob("*.json"))
    prefixes: Set[str] = set([gcs_prefix]) if gcs_prefix else detect_common_prefixes(json_files)
    if not prefixes:
        print("⚠️  Could not infer GCS prefixes from inputs; falling back to per-object checks.")
        return set()

    print(f"🧭 Building GCS index for {len(prefixes)} prefix(es)...")
    # Prefer client; fallback to gsutil
    index = list_objects_with_gcs_client(prefixes, billing_project)
    if not index:
        index = list_objects_with_gsutil(prefixes, billing_project)

    if index:
        meta = {
            "created_at": datetime.now().isoformat(),
            "billing_project": billing_project or "",
            "prefix_count": str(len(prefixes)),
        }
        save_index(index, index_path, meta)
        print(f"✅ Indexed {len(index):,} objects -> {index_path}")
    else:
        print("⚠️  Index build returned 0 objects; will perform direct checks.")
    return set(index)


def check_gcs_file_exists(gcs_path: str,
                          timeout_seconds: int = 10,
                          retries: int = 2,
                          initial_backoff_seconds: float = 0.5,
                          billing_project: str | None = None) -> bool:
    """Return True if object exists at `gcs_path` using `gsutil stat` with retries.

    Retries on non-zero exit or timeout, using exponential backoff with jitter.
    Optionally sets requester-pays billing project via `-u`.
    """
    attempt_index = 0
    while True:
        try:
            cmd = ["gsutil"]
            if billing_project:
                cmd += ["-u", billing_project]
            cmd += ["-q", "stat", gcs_path]
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout_seconds
            )
            if result.returncode == 0:
                return True
        except subprocess.TimeoutExpired:
            # Treat timeouts as transient failures; retry
            pass

        if attempt_index >= retries:
            return False

        # Exponential backoff with jitter
        backoff = initial_backoff_seconds * (2 ** attempt_index)
        time.sleep(backoff + random.random() * 0.2)
        attempt_index += 1


def validate_json_inputs(input_dir, output_dir, report_dir,
                         max_workers=16,
                         stat_timeout_seconds=10,
                         stat_retries=2,
                         billing_project: str | None = None,
                         use_index: bool = True,
                         refresh_index: bool = False,
                         index_path: Optional[str] = None,
                         gcs_prefix: Optional[str] = None,
                         assume_bai_if_bam: bool = False,
                         skip_existing: bool = True,
                         tissue_workers: int = 1):
    """Validate all JSON input files and create filtered versions.

    Returns (overall_stats: dict, tissue_reports: dict).
    """
    
    input_path = Path(input_dir)
    output_path = Path(output_dir)
    report_path = Path(report_dir)
    
    # Create directories
    output_path.mkdir(exist_ok=True)
    report_path.mkdir(exist_ok=True)
    
    # Overall statistics
    overall_stats = {
        'total_files_processed': 0,
        'total_samples_original': 0,
        'total_samples_valid': 0,
        'total_bam_missing': 0,
        'total_bai_missing': 0,
        'tissues_with_issues': [],
        'tissues_processed': []
    }
    
    # Per-tissue reports
    tissue_reports = {}
    
    print(f"🔍 Validating GTEx input files...")
    print(f"📁 Input directory: {input_path}")
    print(f"📁 Output directory: {output_path}")
    print(f"📊 Reports directory: {report_path}")
    
    def process_one_json(json_file: Path, gcs_index: Set[str]) -> Tuple[str, Dict[str, object]]:
        if json_file.name.startswith('.'):
            return json_file.stem, {}

        # Skip if filtered exists and skipping enabled
        if skip_existing:
            out_file = output_path / json_file.name
            if out_file.exists():
                try:
                    with open(out_file, 'r') as f:
                        out_data = json.load(f)
                    meta = out_data.get('_validation_metadata', {})
                    if meta.get('original_sample_count') is not None:
                        print(f"⏭️  Skipping {json_file.name} (filtered exists)")
                        # Still produce a lightweight report entry
                        return json_file.stem, {
                            'tissue': json_file.stem,
                            'original_samples': meta.get('original_sample_count', 0),
                            'valid_samples': meta.get('filtered_sample_count', 0),
                            'missing_bam_count': None,
                            'missing_bai_count': None,
                            'success_rate': None,
                            'missing_bam_files': [],
                            'missing_bai_files': [],
                            'per_sample_failures': [],
                            'status': 'SKIPPED'
                        }
                except Exception:
                    pass

        print(f"\n🧬 Processing {json_file.name}...")
        with open(json_file, 'r') as f:
            data = json.load(f)
        tissue_name = json_file.stem
        bam_files = data.get('SplicingAnalysis.bam_files', [])
        bai_files = data.get('SplicingAnalysis.bai_files', [])
        if len(bam_files) != len(bai_files) and not assume_bai_if_bam:
            print(f"⚠️  BAM/BAI count mismatch: {len(bam_files)} BAM vs {len(bai_files)} BAI")
            return tissue_name, {}

        valid_bam_files: list[str] = []
        valid_bai_files: list[str] = []
        missing_bam: list[str] = []
        missing_bai: list[str] = []
        per_sample_failures: list[dict] = []

        total_samples = len(bam_files)

        # If index is present, use set membership; else fall back to stat checks
        if gcs_index:
            print(f"  🔎 Using index for {total_samples} samples...")
            for i, (bam, bai) in enumerate(zip(bam_files, bai_files)):
                bam_ok = bam in gcs_index
                bai_ok = (bai in gcs_index) if not assume_bai_if_bam else bam_ok
                if bam_ok and bai_ok:
                    valid_bam_files.append(bam)
                    valid_bai_files.append(bai if not assume_bai_if_bam else bai)
                else:
                    if not bam_ok:
                        missing_bam.append(bam)
                    if not bai_ok:
                        missing_bai.append(bai)
                    per_sample_failures.append({
                        'index': i,
                        'sample_id': Path(bam).name.split('.')[0],
                        'bam_missing': not bam_ok,
                        'bai_missing': not bai_ok,
                        'bam_path': bam,
                        'bai_path': bai,
                    })
            print(f"  ✅ Validation complete: {len(valid_bam_files)}/{total_samples} valid")
        else:
            # Fall back to batch gsutil stat to minimize process overhead; then per-object for any leftovers
            print(f"  📦 Batch stat {total_samples * (1 if assume_bai_if_bam else 2)} URLs via gsutil -m stat -I...")
            urls = list(bam_files)
            if not assume_bai_if_bam:
                urls += list(bai_files)
            existed = gsutil_stat_batch(urls, billing_project)
            if existed:
                for i, (bam, bai) in enumerate(zip(bam_files, bai_files)):
                    bam_ok = (bam in existed) or check_gcs_file_exists(bam, timeout_seconds=stat_timeout_seconds, retries=stat_retries, billing_project=billing_project)
                    bai_ok = bam_ok if assume_bai_if_bam else ((bai in existed) or check_gcs_file_exists(bai, timeout_seconds=stat_timeout_seconds, retries=stat_retries, billing_project=billing_project))
                    if bam_ok and bai_ok:
                        valid_bam_files.append(bam)
                        valid_bai_files.append(bai)
                    else:
                        if not bam_ok:
                            missing_bam.append(bam)
                        if not bai_ok:
                            missing_bai.append(bai)
                        per_sample_failures.append({
                            'index': i,
                            'sample_id': Path(bam).name.split('.')[0],
                            'bam_missing': not bam_ok,
                            'bai_missing': not bai_ok,
                            'bam_path': bam,
                            'bai_path': bai,
                        })
            else:
                print(f"  🔄 Dispatching {total_samples} GCS existence checks...")
                def check_pair(index, bam_path, bai_path):
                    bam_ok = check_gcs_file_exists(
                        bam_path,
                        timeout_seconds=stat_timeout_seconds,
                        retries=stat_retries,
                        billing_project=billing_project,
                    )
                    bai_ok = (check_gcs_file_exists(
                        bai_path,
                        timeout_seconds=stat_timeout_seconds,
                        retries=stat_retries,
                        billing_project=billing_project,
                    ) if not assume_bai_if_bam else bam_ok)
                    return (index, bam_path, bam_ok, bai_path, bai_ok)

                with ThreadPoolExecutor(max_workers=max_workers) as executor:
                    futures = [executor.submit(check_pair, i, bam, bai) for i, (bam, bai) in enumerate(zip(bam_files, bai_files))]
                    for fut in as_completed(futures):
                        i, bam_path, bam_ok, bai_path, bai_ok = fut.result()
                        if bam_ok and bai_ok:
                            valid_bam_files.append(bam_path)
                            valid_bai_files.append(bai_path)
                        else:
                            if not bam_ok:
                                missing_bam.append(bam_path)
                            if not bai_ok:
                                missing_bai.append(bai_path)
                            per_sample_failures.append({
                                'index': i,
                                'sample_id': Path(bam_path).name.split('.')[0],
                                'bam_missing': not bam_ok,
                                'bai_missing': not bai_ok,
                                'bam_path': bam_path,
                                'bai_path': bai_path,
                            })
            print(f"  ✅ Validation complete: {len(valid_bam_files)}/{total_samples} valid")

        tissue_report = {
            'tissue': tissue_name,
            'original_samples': total_samples,
            'valid_samples': len(valid_bam_files),
            'missing_bam_count': len(missing_bam),
            'missing_bai_count': len(missing_bai),
            'success_rate': len(valid_bam_files) / total_samples if total_samples > 0 else 0,
            'missing_bam_files': missing_bam,
            'missing_bai_files': missing_bai,
            'per_sample_failures': sorted(per_sample_failures, key=lambda x: x['index']),
            'status': 'OK' if len(missing_bam) == 0 and len(missing_bai) == 0 else 'ISSUES'
        }

        # Update overall and write outputs
        if valid_bam_files:
            filtered_data = data.copy()
            filtered_data['SplicingAnalysis.bam_files'] = valid_bam_files
            filtered_data['SplicingAnalysis.bai_files'] = valid_bai_files if not assume_bai_if_bam else [
                f"{b}.bai" if not b.endswith('.bam.bai') else b for b in valid_bai_files
            ]
            filtered_data['_validation_metadata'] = {
                'original_sample_count': total_samples,
                'filtered_sample_count': len(valid_bam_files),
                'missing_files': len(missing_bam) + len(missing_bai),
                'validation_date': datetime.now().isoformat(),
                'validation_script': 'validate_and_filter_inputs.py'
            }
            output_file = output_path / json_file.name
            with open(output_file, 'w') as f:
                json.dump(filtered_data, f, indent=2)
            print(f"  💾 Created filtered file: {len(valid_bam_files)}/{total_samples} samples")
        else:
            print(f"  ❌ No valid samples found - skipping output file")

        # Reports
        tissue_report_file = report_path / f"{tissue_name}_validation_report.json"
        with open(tissue_report_file, 'w') as f:
            json.dump(tissue_report, f, indent=2)

        tissue_text = report_path / f"{tissue_name}_summary.txt"
        with open(tissue_text, 'w') as f:
            f.write(f"Validation Summary: {tissue_name}\n")
            f.write("=" * 40 + "\n\n")
            f.write(f"Original Samples: {total_samples}\n")
            f.write(f"Valid Samples: {len(valid_bam_files)}\n")
            f.write(f"Missing BAM: {len(missing_bam)}\n")
            f.write(f"Missing BAI: {len(missing_bai)}\n")
            f.write(f"Success Rate: {tissue_report['success_rate']:.1%}\n")
            if per_sample_failures:
                f.write("\nMissing Samples (first 50):\n")
                for entry in sorted(per_sample_failures, key=lambda x: x['index'])[:50]:
                    flags = []
                    if entry['bam_missing']:
                        flags.append('BAM')
                    if entry['bai_missing']:
                        flags.append('BAI')
                    f.write(f"  • {entry['sample_id']}: {','.join(flags)}\n")

        return tissue_name, tissue_report

    # Build or load index once if desired
    gcs_index: Set[str] = set()
    if use_index:
        gcs_index = ensure_index(input_path, billing_project, Path(index_path) if index_path else DEFAULT_INDEX_PATH, refresh=refresh_index, gcs_prefix=gcs_prefix)

    json_files = [p for p in input_path.glob("*.json") if not p.name.startswith('.')]
    results: Dict[str, Dict[str, object]] = {}

    if tissue_workers > 1 and len(json_files) > 1:
        print(f"🧵 Parallel tissue-level validation with {tissue_workers} workers...")
        # Use separate processes to avoid GIL; reload index in each process from disk
        from concurrent.futures import ProcessPoolExecutor
        def worker(path_str: str) -> Tuple[str, Dict[str, object]]:
            # Reload index locally for the subprocess
            local_index = set()
            if use_index:
                cached = load_index(Path(index_path) if index_path else DEFAULT_INDEX_PATH)
                if cached and isinstance(cached.get('objects'), list):
                    local_index.update(cached['objects'])
            return process_one_json(Path(path_str), local_index)

        with ProcessPoolExecutor(max_workers=tissue_workers) as ex:
            for tissue_name, report in ex.map(worker, [str(p) for p in json_files]):
                if report:
                    results[tissue_name] = report
    else:
        for jf in json_files:
            tissue_name, report = process_one_json(jf, gcs_index)
            if report:
                results[tissue_name] = report
        
        # Aggregate results into reports and overall stats
    tissue_reports = {}
    for tissue_name, report in results.items():
        tissue_reports[tissue_name] = report
        overall_stats['total_files_processed'] += 1
        overall_stats['total_samples_original'] += report.get('original_samples', 0) or 0
        overall_stats['total_samples_valid'] += report.get('valid_samples', 0) or 0
        overall_stats['total_bam_missing'] += report.get('missing_bam_count', 0) or 0
        overall_stats['total_bai_missing'] += report.get('missing_bai_count', 0) or 0
        overall_stats['tissues_processed'].append(tissue_name)
        if report.get('status') == 'ISSUES':
            overall_stats['tissues_with_issues'].append(tissue_name)
    
    # Generate overall summary report
    overall_stats['validation_date'] = datetime.now().isoformat()
    overall_stats['success_rate_overall'] = (
        overall_stats['total_samples_valid'] / overall_stats['total_samples_original'] 
        if overall_stats['total_samples_original'] > 0 else 0
    )
    
    summary_file = report_path / "validation_summary.json"
    with open(summary_file, 'w') as f:
        json.dump(overall_stats, f, indent=2)
    
    # Generate human-readable summary
    generate_readable_summary(overall_stats, tissue_reports, report_path)

    # Also write CSV summary per tissue
    csv_file = report_path / "validation_summary.csv"
    with open(csv_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["tissue", "original_samples", "valid_samples", "missing_bam_count", "missing_bai_count", "success_rate", "status"])
        for tissue_name, report in sorted(tissue_reports.items()):
            writer.writerow([
                tissue_name,
                report.get('original_samples', 0),
                report.get('valid_samples', 0),
                report.get('missing_bam_count', 0),
                report.get('missing_bai_count', 0),
                f"{report.get('success_rate', 0):.4f}",
                report.get('status', ''),
            ])
    
    return overall_stats, tissue_reports


def generate_readable_summary(overall_stats, tissue_reports, report_path):
    """Generate human-readable summary reports."""
    
    # Main summary report
    summary_file = report_path / "validation_summary.txt"
    with open(summary_file, 'w') as f:
        f.write("GTEx BAM/BAI File Validation Summary\\n")
        f.write("=" * 50 + "\\n\\n")
        f.write(f"Validation Date: {overall_stats['validation_date']}\\n")
        f.write(f"Total Tissues Processed: {overall_stats['total_files_processed']}\\n")
        f.write(f"Total Original Samples: {overall_stats['total_samples_original']:,}\\n")
        f.write(f"Total Valid Samples: {overall_stats['total_samples_valid']:,}\\n")
        f.write(f"Overall Success Rate: {overall_stats['success_rate_overall']:.1%}\\n")
        f.write(f"Total Missing BAM Files: {overall_stats['total_bam_missing']:,}\\n")
        f.write(f"Total Missing BAI Files: {overall_stats['total_bai_missing']:,}\\n")
        f.write(f"Tissues with Issues: {len(overall_stats['tissues_with_issues'])}\\n\\n")
        
        # Tissues with most issues
        f.write("Tissues by Success Rate:\\n")
        f.write("-" * 30 + "\\n")
        sorted_tissues = sorted(tissue_reports.items(), key=lambda x: x[1]['success_rate'])
        for tissue_name, report in sorted_tissues:
            status_emoji = "✅" if report['status'] == 'OK' else "⚠️"
            f.write(f"{status_emoji} {tissue_name}: {report['success_rate']:.1%} "
                   f"({report['valid_samples']}/{report['original_samples']} samples)\\n")
        
        if overall_stats['tissues_with_issues']:
            f.write(f"\\nTissues with Missing Files:\\n")
            f.write("-" * 30 + "\\n")
            for tissue in overall_stats['tissues_with_issues']:
                report = tissue_reports[tissue]
                f.write(f"• {tissue}: {report['missing_bam_count']} BAM + {report['missing_bai_count']} BAI missing\\n")
    
    # Detailed missing files report
    missing_files_report = report_path / "missing_files_detailed.txt"
    with open(missing_files_report, 'w') as f:
        f.write("Detailed Missing Files Report\\n")
        f.write("=" * 50 + "\\n\\n")
        
        for tissue_name, report in tissue_reports.items():
            if report['status'] == 'ISSUES':
                f.write(f"\\n{tissue_name.upper()}\\n")
                f.write("-" * len(tissue_name) + "\\n")
                f.write(f"Missing BAM files ({len(report['missing_bam_files'])}):\\n")
                for bam_file in report['missing_bam_files']:
                    sample_id = Path(bam_file).name.split('.')[0]
                    f.write(f"  • {sample_id}\\n")
                
                if report['missing_bai_files']:
                    f.write(f"Missing BAI files ({len(report['missing_bai_files'])}):\\n")
                    for bai_file in report['missing_bai_files']:
                        sample_id = Path(bai_file).name.split('.')[0]
                        f.write(f"  • {sample_id}\\n")
    
    print(f"\\n📊 Reports generated:")
    print(f"  • {summary_file}")
    print(f"  • {missing_files_report}")


def main():
    parser = argparse.ArgumentParser(description="Validate GTEx input files and filter missing ones")
    parser.add_argument("--input-dir", "-i", 
                       default=str((SCRIPT_DIR / "../../workflows/splicing_analysis/inputs/gtex_v10").resolve()),
                       help="Directory containing input JSON files")
    parser.add_argument("--output-dir", "-o",
                       default=str((SCRIPT_DIR / "../../workflows/splicing_analysis/inputs/gtex_v10_validated").resolve()), 
                       help="Directory for filtered output JSON files")
    parser.add_argument("--report-dir", "-r",
                       default=str((SCRIPT_DIR / "validation_reports").resolve()),
                       help="Directory for validation reports")
    parser.add_argument("--tissue", "-t",
                       help="Validate only specific tissue (e.g., 'cervix_uteri_88')")
    parser.add_argument("--all", action="store_true",
                       help="Validate all tissues in --input-dir (overrides --tissue if both provided)")
    parser.add_argument("--billing-project",
                       default="snaf-workflow-wdl",
                       help="GCP billing project for Requester Pays buckets (used with gsutil -u). Default: snaf-workflow-wdl")
    parser.add_argument("--max-workers", type=int, default=32,
                       help="Maximum concurrent gsutil checks. Default: 32")
    parser.add_argument("--stat-timeout-seconds", type=int, default=20,
                       help="Per-check timeout seconds. Default: 20")
    parser.add_argument("--stat-retries", type=int, default=3,
                       help="Retries per object. Default: 3")
    
    args = parser.parse_args()
    
    # Check if gsutil is available
    try:
        subprocess.run(["gsutil", "version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ Error: gsutil not found. Please install Google Cloud SDK.")
        sys.exit(1)
    
    # Run validation
    run_all = bool(args.all) or (not args.tissue)
    if not run_all and args.tissue:
        # Validate single tissue
        input_file = Path(args.input_dir) / f"{args.tissue}.json"
        if not input_file.exists():
            print(f"❌ Error: {input_file} not found")
            sys.exit(1)
        
        # Create temporary directory structure for single file
        temp_input = SCRIPT_DIR / "temp_input"
        temp_input.mkdir(exist_ok=True)
        import shutil
        shutil.copy(input_file, temp_input)
        
        overall_stats, tissue_reports = validate_json_inputs(
            str(temp_input),
            args.output_dir,
            args.report_dir,
            max_workers=args.max_workers,
            stat_timeout_seconds=args.stat_timeout_seconds,
            stat_retries=args.stat_retries,
            billing_project=args.billing_project,
        )
        
        # Cleanup
        shutil.rmtree(temp_input)
    else:
        # Validate all tissues
        overall_stats, tissue_reports = validate_json_inputs(
            args.input_dir,
            args.output_dir,
            args.report_dir,
            max_workers=args.max_workers,
            stat_timeout_seconds=args.stat_timeout_seconds,
            stat_retries=args.stat_retries,
            billing_project=args.billing_project,
        )
    
    # Print summary
    print(f"\n🎯 Validation Complete!")
    print(f"📊 {overall_stats['total_samples_valid']:,}/{overall_stats['total_samples_original']:,} samples valid ({overall_stats['success_rate_overall']:.1%})")
    print(f"❌ {overall_stats['total_bam_missing'] + overall_stats['total_bai_missing']:,} files missing")
    print(f"⚠️  {len(overall_stats['tissues_with_issues'])} tissues have missing files")
    
    if overall_stats['tissues_with_issues']:
        print(f"\n🚨 Tissues with issues:")
        for tissue in overall_stats['tissues_with_issues'][:5]:  # Show first 5
            report = tissue_reports[tissue]
            print(f"   • {tissue}: {report['missing_bam_count'] + report['missing_bai_count']} missing files")
        if len(overall_stats['tissues_with_issues']) > 5:
            print(f"   ... and {len(overall_stats['tissues_with_issues']) - 5} more")


if __name__ == "__main__":
    main()
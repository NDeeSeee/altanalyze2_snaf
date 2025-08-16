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

# Resolve paths relative to this script so it can be run from any CWD
SCRIPT_DIR = Path(__file__).resolve().parent


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
                         billing_project: str | None = None):
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
    
    # Process each JSON file
    for json_file in input_path.glob("*.json"):
        if json_file.name.startswith('.'):
            continue
            
        print(f"\n🧬 Processing {json_file.name}...")
        
        # Load JSON
        with open(json_file, 'r') as f:
            data = json.load(f)
        
        # Extract tissue name and sample count from filename
        tissue_name = json_file.stem
        
        bam_files = data.get('SplicingAnalysis.bam_files', [])
        bai_files = data.get('SplicingAnalysis.bai_files', [])
        
        if len(bam_files) != len(bai_files):
            print(f"⚠️  BAM/BAI count mismatch: {len(bam_files)} BAM vs {len(bai_files)} BAI")
            continue
        
        # Validate each file pair
        valid_bam_files = []
        valid_bai_files = []
        missing_bam = []
        missing_bai = []
        
        total_samples = len(bam_files)
        
        # Concurrent (and retried) checks
        per_sample_failures = []
        print(f"  🔄 Dispatching {total_samples} GCS existence checks...")

        def check_pair(index, bam_path, bai_path):
            bam_ok = check_gcs_file_exists(
                bam_path,
                timeout_seconds=stat_timeout_seconds,
                retries=stat_retries,
                billing_project=billing_project,
            )
            bai_ok = check_gcs_file_exists(
                bai_path,
                timeout_seconds=stat_timeout_seconds,
                retries=stat_retries,
                billing_project=billing_project,
            )
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
        
        # Generate tissue report
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
        
        tissue_reports[tissue_name] = tissue_report
        
        # Update overall statistics
        overall_stats['total_files_processed'] += 1
        overall_stats['total_samples_original'] += total_samples
        overall_stats['total_samples_valid'] += len(valid_bam_files)
        overall_stats['total_bam_missing'] += len(missing_bam)
        overall_stats['total_bai_missing'] += len(missing_bai)
        overall_stats['tissues_processed'].append(tissue_name)
        
        if tissue_report['status'] == 'ISSUES':
            overall_stats['tissues_with_issues'].append(tissue_name)
        
        # Create filtered JSON with only valid files
        if valid_bam_files:
            filtered_data = data.copy()
            filtered_data['SplicingAnalysis.bam_files'] = valid_bam_files
            filtered_data['SplicingAnalysis.bai_files'] = valid_bai_files
            
            # Add metadata about filtering
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
        
        # Create individual tissue report
        tissue_report_file = report_path / f"{tissue_name}_validation_report.json"
        with open(tissue_report_file, 'w') as f:
            json.dump(tissue_report, f, indent=2)

        # Also write a concise human-readable summary per tissue
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
#!/usr/bin/env python3
"""
Validate GTEx input files and create filtered versions with only existing BAM/BAI files.

This script:
1. Checks which BAM/BAI files actually exist in the Google Cloud bucket
2. Creates filtered JSON inputs with only existing files
3. Generates comprehensive reports of missing/found files
4. Provides smart summaries per tissue type
"""

import json
import subprocess
import sys
from pathlib import Path
from collections import defaultdict
import argparse
from datetime import datetime


def check_gcs_file_exists(gcs_path):
    """Check if a file exists in Google Cloud Storage."""
    try:
        result = subprocess.run(
            ["gsutil", "-q", "stat", gcs_path],
            capture_output=True,
            text=True,
            timeout=10  # Reduced timeout
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return False


def validate_json_inputs(input_dir, output_dir, report_dir):
    """Validate all JSON input files and create filtered versions."""
    
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
        
        for i, (bam_file, bai_file) in enumerate(zip(bam_files, bai_files)):
            print(f"  📋 Checking {i+1}/{total_samples}...", end='\\r')
            
            bam_exists = check_gcs_file_exists(bam_file)
            bai_exists = check_gcs_file_exists(bai_file)
            
            if bam_exists and bai_exists:
                valid_bam_files.append(bam_file)
                valid_bai_files.append(bai_file)
            else:
                if not bam_exists:
                    missing_bam.append(bam_file)
                if not bai_exists:
                    missing_bai.append(bai_file)
        
        print(f"  ✅ Validation complete                    ")
        
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
                       default="../../workflows/splicing_analysis/inputs/gtex_v10",
                       help="Directory containing input JSON files")
    parser.add_argument("--output-dir", "-o",
                       default="../../workflows/splicing_analysis/inputs/gtex_v10_validated", 
                       help="Directory for filtered output JSON files")
    parser.add_argument("--report-dir", "-r",
                       default="./validation_reports",
                       help="Directory for validation reports")
    parser.add_argument("--tissue", "-t",
                       help="Validate only specific tissue (e.g., 'cervix_uteri_88')")
    
    args = parser.parse_args()
    
    # Check if gsutil is available
    try:
        subprocess.run(["gsutil", "version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ Error: gsutil not found. Please install Google Cloud SDK.")
        sys.exit(1)
    
    # Run validation
    if args.tissue:
        # Validate single tissue
        input_file = Path(args.input_dir) / f"{args.tissue}.json"
        if not input_file.exists():
            print(f"❌ Error: {input_file} not found")
            sys.exit(1)
        
        # Create temporary directory structure for single file
        temp_input = Path("temp_input")
        temp_input.mkdir(exist_ok=True)
        import shutil
        shutil.copy(input_file, temp_input)
        
        overall_stats, tissue_reports = validate_json_inputs(
            str(temp_input), args.output_dir, args.report_dir
        )
        
        # Cleanup
        shutil.rmtree(temp_input)
    else:
        # Validate all tissues
        overall_stats, tissue_reports = validate_json_inputs(
            args.input_dir, args.output_dir, args.report_dir
        )
    
    # Print summary
    print(f"\\n🎯 Validation Complete!")
    print(f"📊 {overall_stats['total_samples_valid']:,}/{overall_stats['total_samples_original']:,} samples valid ({overall_stats['success_rate_overall']:.1%})")
    print(f"❌ {overall_stats['total_bam_missing'] + overall_stats['total_bai_missing']:,} files missing")
    print(f"⚠️  {len(overall_stats['tissues_with_issues'])} tissues have missing files")
    
    if overall_stats['tissues_with_issues']:
        print(f"\\n🚨 Tissues with issues:")
        for tissue in overall_stats['tissues_with_issues'][:5]:  # Show first 5
            report = tissue_reports[tissue]
            print(f"   • {tissue}: {report['missing_bam_count'] + report['missing_bai_count']} missing files")
        if len(overall_stats['tissues_with_issues']) > 5:
            print(f"   ... and {len(overall_stats['tissues_with_issues']) - 5} more")


if __name__ == "__main__":
    main()
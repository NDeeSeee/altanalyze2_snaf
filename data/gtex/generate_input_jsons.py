#!/usr/bin/env python3
"""
Generate input JSON files for GTEx splicing analysis per tissue type.

This script:
1. Reads organized GTEx sample data
2. Creates JSON input files for each tissue type
3. Generates file paths for BAM and BAI files based on sample IDs
4. Saves files to workflows/splicing_analysis/inputs/gtex_v10/ directory
"""

import json
import os
import csv
from pathlib import Path


def sanitize_filename(name):
    """Sanitize filename by replacing problematic characters."""
    return name.replace(' ', '_').replace('-', '_').replace('(', '').replace(')', '').replace('/', '_').lower()


def load_default_configs():
    """Load default configuration from file."""
    default_config_path = Path("../../inputs/default_configs.json")
    
    if not default_config_path.exists():
        print(f"Warning: {default_config_path} not found, using hardcoded defaults")
        return {
            "SplicingAnalysis.extra_bed_files": [],
            "SplicingAnalysis.species": "Hs",
            "SplicingAnalysis.bam_to_bed_cpu_cores": 1,
            "SplicingAnalysis.bam_to_bed_memory": "8 GB",
            "SplicingAnalysis.bam_to_bed_disk_space": "50",
            "SplicingAnalysis.bam_to_bed_disk_type": "HDD",
            "SplicingAnalysis.bam_to_bed_preemptible": 3,
            "SplicingAnalysis.bam_to_bed_max_retries": 2,
            "SplicingAnalysis.junction_analysis_cpu_cores": 1,
            "SplicingAnalysis.junction_analysis_memory": "8 GB",
            "SplicingAnalysis.junction_analysis_disk_space": "50",
            "SplicingAnalysis.junction_analysis_disk_type": "HDD",
            "SplicingAnalysis.junction_analysis_preemptible": 1,
            "SplicingAnalysis.junction_analysis_max_retries": 1
        }
    
    with open(default_config_path, 'r') as f:
        return json.load(f)


def create_json_input(tissue_name, sample_ids, default_configs, output_dir):
    """Create JSON input file for a tissue type."""
    
    # Base GS bucket path from the example
    base_path = "gs://fc-secure-e0503432-75b9-4674-8e6d-2597dc529c4c/GTEx_Analysis_2022-06-06_v10_RNAseq_BAM_files"
    
    # Generate BAM and BAI file paths
    bam_files = []
    bai_files = []
    
    for sample_id in sample_ids:
        bam_file = f"{base_path}/{sample_id}.Aligned.sortedByCoord.out.patched.md.bam"
        bai_file = f"{base_path}/{sample_id}.Aligned.sortedByCoord.out.patched.md.bam.bai"
        bam_files.append(bam_file)
        bai_files.append(bai_file)
    
    # Start with default configurations
    json_data = default_configs.copy()
    
    # Add the tissue-specific file paths
    json_data["SplicingAnalysis.bam_files"] = bam_files
    json_data["SplicingAnalysis.bai_files"] = bai_files
    
    # Create filename: {tissue}_{count}.json
    tissue_clean = sanitize_filename(tissue_name)
    filename = f"{tissue_clean}_{len(sample_ids)}.json"
    output_file = output_dir / filename
    
    # Write JSON file
    with open(output_file, 'w') as f:
        json.dump(json_data, f, indent=2)
    
    return output_file


def main():
    # Paths
    organized_data_dir = Path("gtex_organized")
    output_dir = Path("../../workflows/splicing_analysis/inputs/gtex_v10")
    
    # Create output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if not organized_data_dir.exists():
        print(f"Error: {organized_data_dir} not found. Run organize_gtex_samples.py first.")
        return
    
    # Load default configurations
    print("Loading default configurations...")
    default_configs = load_default_configs()
    print(f"Loaded {len(default_configs)} configuration parameters")
    
    print("Generating JSON input files for each tissue type...")
    
    generated_files = []
    
    # Process each tissue directory
    for tissue_dir in organized_data_dir.iterdir():
        if not tissue_dir.is_dir():
            continue
            
        # Skip if it's just the overall metadata
        if tissue_dir.name == "overall_metadata.txt":
            continue
            
        # Read sample IDs from CSV
        sample_csv = tissue_dir / "sample_ids.csv"
        if not sample_csv.exists():
            print(f"Warning: {sample_csv} not found, skipping {tissue_dir.name}")
            continue
        
        # Read sample IDs
        sample_ids = []
        with open(sample_csv, 'r') as f:
            reader = csv.reader(f)
            next(reader)  # Skip header
            for row in reader:
                if row:  # Skip empty rows
                    sample_ids.append(row[0])
        
        if not sample_ids:
            print(f"Warning: No sample IDs found in {sample_csv}, skipping")
            continue
        
        # Convert directory name back to original tissue name
        tissue_name = tissue_dir.name.replace('_', ' ')
        
        print(f"Processing {tissue_name}: {len(sample_ids)} samples")
        
        # Generate JSON file
        output_file = create_json_input(tissue_name, sample_ids, default_configs, output_dir)
        generated_files.append(output_file)
        
        print(f"  Created: {output_file.name}")
    
    print(f"\nGeneration complete!")
    print(f"Created {len(generated_files)} JSON input files in {output_dir}")
    print(f"\nGenerated files:")
    for file_path in sorted(generated_files):
        print(f"  {file_path.name}")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""
Organize GTEx samples by tissue type.

This script:
1. Reads GTEx sample annotations file
2. Creates subdirectories named by SMTS (broad tissue category)
3. Creates sample ID files in each subdirectory
4. Generates metadata files with SMTSD counts per tissue type
"""

import os
import sys
from collections import defaultdict, Counter
from pathlib import Path


def sanitize_dirname(name):
    """Sanitize directory name by replacing problematic characters."""
    return name.replace(' ', '_').replace('-', '_').replace('(', '').replace(')', '').replace('/', '_')


def main():
    # Input file path
    input_file = "GTEx_Analysis_2022-06-06_v10_Annotations_SampleAttributesDS.txt"
    
    if not os.path.exists(input_file):
        print(f"Error: Input file {input_file} not found")
        sys.exit(1)
    
    # Output directory
    output_dir = Path("gtex_organized")
    output_dir.mkdir(exist_ok=True)
    
    # Data structures to store parsed data
    tissue_samples = defaultdict(list)  # SMTS -> [(SAMPID, SMTSD), ...]
    tissue_subtypes = defaultdict(Counter)  # SMTS -> Counter of SMTSD
    total_subtypes = Counter()  # Overall SMTSD counts
    
    print("Reading GTEx sample annotations...")
    
    # Parse the input file
    with open(input_file, 'r') as f:
        header = f.readline().strip().split('\t')
        
        # Find column indices
        try:
            sampid_idx = header.index('SAMPID')
            smts_idx = header.index('SMTS')
            smtsd_idx = header.index('SMTSD')
        except ValueError as e:
            print(f"Error: Required column not found in header: {e}")
            sys.exit(1)
        
        # Process each sample
        for line_num, line in enumerate(f, 2):
            fields = line.strip().split('\t')
            
            if len(fields) <= max(sampid_idx, smts_idx, smtsd_idx):
                print(f"Warning: Skipping malformed line {line_num}")
                continue
            
            sampid = fields[sampid_idx]
            smts = fields[smts_idx]
            smtsd = fields[smtsd_idx]
            
            # Skip empty values
            if not all([sampid, smts, smtsd]):
                continue
            
            # Store data
            tissue_samples[smts].append((sampid, smtsd))
            tissue_subtypes[smts][smtsd] += 1
            total_subtypes[smtsd] += 1
    
    print(f"Processed {sum(len(samples) for samples in tissue_samples.values())} samples")
    print(f"Found {len(tissue_samples)} tissue types")
    
    # Create directories and files for each tissue type
    for smts, samples in tissue_samples.items():
        # Create sanitized directory name
        dir_name = sanitize_dirname(smts)
        tissue_dir = output_dir / dir_name
        tissue_dir.mkdir(exist_ok=True)
        
        print(f"Processing {smts} ({len(samples)} samples)...")
        
        # Create single CSV file with all sample IDs for this tissue
        samples_csv = tissue_dir / "sample_ids.csv"
        with open(samples_csv, 'w') as f:
            f.write("sample_id\n")
            for sampid, smtsd in samples:
                f.write(f"{sampid}\n")
        
        # Create metadata file with SMTSD counts for this tissue type
        metadata_file = tissue_dir / "metadata.txt"
        with open(metadata_file, 'w') as f:
            f.write(f"Tissue Type: {smts}\n")
            f.write(f"Total Samples: {len(samples)}\n")
            f.write("\nSubtype Counts:\n")
            f.write("-" * 50 + "\n")
            
            # Sort subtypes by count (descending)
            for smtsd, count in tissue_subtypes[smts].most_common():
                f.write(f"{count:>6} {smtsd}\n")
            
            f.write("-" * 50 + "\n")
            f.write(f"{'Total':>6} {len(samples)}\n")
    
    # Create overall metadata file
    overall_metadata = output_dir / "overall_metadata.txt"
    with open(overall_metadata, 'w') as f:
        f.write("GTEx Sample Organization Summary\n")
        f.write("=" * 50 + "\n\n")
        
        f.write("Tissue Type Counts (SMTS):\n")
        f.write("-" * 50 + "\n")
        
        # Sort tissue types by sample count
        tissue_counts = [(smts, len(samples)) for smts, samples in tissue_samples.items()]
        tissue_counts.sort(key=lambda x: x[1], reverse=True)
        
        for smts, count in tissue_counts:
            f.write(f"{count:>6} {smts}\n")
        
        f.write("-" * 50 + "\n")
        f.write(f"{'Total':>6} {sum(count for _, count in tissue_counts)}\n\n")
        
        f.write("All Subtype Counts (SMTSD):\n")
        f.write("-" * 50 + "\n")
        
        for smtsd, count in total_subtypes.most_common():
            f.write(f"{count:>6} {smtsd}\n")
        
        f.write("-" * 50 + "\n")
        f.write(f"{'Total':>6} {sum(total_subtypes.values())}\n")
    
    print(f"\nOrganization complete!")
    print(f"Output directory: {output_dir}")
    print(f"Created {len(tissue_samples)} tissue type directories")
    print(f"Created {sum(len(samples) for samples in tissue_samples.values())} sample files")
    print(f"Created metadata files for each tissue type")
    print(f"Created overall metadata file: {overall_metadata}")


if __name__ == "__main__":
    main()
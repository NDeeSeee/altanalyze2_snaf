#!/usr/bin/env python3
"""
Generate submission-ready JSON files that use Terra data table entities.
Replaces large bam_files/bai_files arrays with entity expressions.

Usage: python3 generate_submission_jsons.py
"""

import json
import re
from pathlib import Path

# Configuration
INPUT_DIR = Path("workflows/splicing_analysis/inputs/gtex_v10_validated")
OUTPUT_DIR = Path("workflows/splicing_analysis/inputs/gtex_entity_based")


def extract_tissue_name(filename):
    """Extract tissue name from filename"""
    match = re.match(r'(.+?)_(\d+)(?:_.*)?\.json$', filename)
    if match:
        return match.group(1)
    return None


def convert_to_entity_based(input_json_path):
    """Convert a JSON file to use entity expressions instead of arrays"""
    
    tissue_name = extract_tissue_name(input_json_path.name)
    if not tissue_name:
        return None, f"Could not parse filename: {input_json_path.name}"
    
    # Read original JSON
    try:
        with open(input_json_path) as f:
            data = json.load(f)
    except Exception as e:
        return None, f"Failed to read JSON: {e}"
    
    # Check if it has the arrays we need to replace
    if "SplicingAnalysis.bam_files" not in data or "SplicingAnalysis.bai_files" not in data:
        return None, "Missing bam_files or bai_files in JSON"
    
    sample_count = len(data["SplicingAnalysis.bam_files"])
    
    # Create new JSON with entity expressions
    entity_json = data.copy()

    # Replace arrays with Rawls entity expressions so they survive the
    # terra_rawls_submit conversion step without being double-quoted.
    entity_json["SplicingAnalysis.bam_files"] = {
        "__rawls_expr__": "this.samples.bam_file"
    }
    entity_json["SplicingAnalysis.bai_files"] = {
        "__rawls_expr__": "this.samples.bai_file"
    }
    
    # Generate output filename
    output_filename = f"{tissue_name}_{sample_count}_entity.json"
    output_path = OUTPUT_DIR / output_filename
    
    # Save the new JSON
    try:
        with open(output_path, 'w') as f:
            json.dump(entity_json, f, indent=2)
    except Exception as e:
        return None, f"Failed to write JSON: {e}"
    
    return output_path, f"Created entity-based JSON with {sample_count} samples"


def main():
    print("=" * 70)
    print("🔧 Generate Entity-Based Submission JSONs")
    print("=" * 70)
    
    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"\n📁 Output directory: {OUTPUT_DIR}")
    
    # Find all JSON files (same filtering as bulk_create_tables.py)
    json_files = [
        f for f in INPUT_DIR.glob("*.json")
        if not f.name.startswith("_") 
        and "_fixed" not in f.name 
        and "_partial" not in f.name
        and "bedonly" not in f.name
        and "mem" not in f.name
        and "rerun" not in f.name
        and "compatible" not in f.name
        and "_entity" not in f.name  # Don't process already-converted files
    ]
    
    json_files.sort()
    
    print(f"📂 Found {len(json_files)} tissue JSON files to convert\n")
    
    if not json_files:
        print("❌ No JSON files found!")
        return
    
    # Process each file
    results = []
    for json_path in json_files:
        tissue_name = extract_tissue_name(json_path.name)
        print(f"🔄 Processing: {tissue_name}...")
        
        output_path, message = convert_to_entity_based(json_path)
        
        if output_path:
            print(f"   ✓ {message}")
            print(f"   📄 Saved to: {output_path.name}")
            results.append((json_path.name, True, output_path))
        else:
            print(f"   ❌ {message}")
            results.append((json_path.name, False, None))
        print()
    
    # Print summary
    print("=" * 70)
    print("📊 SUMMARY")
    print("=" * 70)
    
    successful = sum(1 for _, s, _ in results if s)
    failed = len(results) - successful
    
    print(f"\n✅ Generated: {successful} entity-based JSON files")
    print(f"❌ Failed: {failed}")
    
    if successful > 0:
        print(f"\n📁 All files saved to: {OUTPUT_DIR}/")
        print("\n🚀 Ready to submit! Use these commands:\n")
        
        # Show example submission commands
        for filename, success, output_path in results[:3]:  # Show first 3 as examples
            if success and output_path:
                tissue_name = extract_tissue_name(filename)
                sample_set_name = f"{tissue_name}_samples"
                print(f"# {tissue_name.replace('_', ' ').title()}")
                print(f"workflows/splicing_analysis/terra_runs/dockstore_run.sh \\")
                print(f"  -m AltAnalyze3_SNAF/splicing_analysis/<VERSION> \\")
                print(f"  -i {output_path} \\")
                print(f"  -e {sample_set_name} \\")
                print(f"  -d 'GTEx {tissue_name} via data tables'\n")
        
        if successful > 3:
            print(f"... and {successful - 3} more tissues\n")
    
    print("=" * 70)
    print("✨ Done!")
    print("=" * 70)
    
    # Print detailed next steps
    print("\n📋 Next Steps:")
    print("   1. Verify data tables exist in Terra workspace")
    print("   2. For each tissue, submit using the entity-based JSON:")
    print("      • Use -i flag with the _entity.json file")
    print("      • Use -e flag with the sample_set name (e.g., 'pancreas_samples')")
    print("   3. Terra will automatically expand this.samples.bam_file expressions")
    print("   4. Monitor submissions in Terra UI")


if __name__ == "__main__":
    main()
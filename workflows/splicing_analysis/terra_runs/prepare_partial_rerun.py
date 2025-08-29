#!/usr/bin/env python3
"""
Prepare a partial re-run input JSON from a previous submission.
- Fetches BamToBed shard results via Rawls API
- Uses successful BEDs as extra_bed_files
- Keeps only failed BAM/BAI pairs to recompute
- Optionally bumps resources if space/OOM errors were detected

Usage:
  python workflows/splicing_analysis/terra_runs/prepare_partial_rerun.py \
    --submission-id 93e1101e-... \
    --input-json workflows/splicing_analysis/inputs/gtex_v10_validated/cervix_uteri_55.json \
    --out workflows/splicing_analysis/inputs/cervix_uteri_55_partial_rerun.json

Env (or flags):
  WORKSPACE_PROJECT, WORKSPACE_NAME or --project/--workspace
"""
import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

API = "https://api.firecloud.org/api"


def get_access_token() -> str:
    r = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True)
    if r.returncode != 0:
        print("gcloud auth required", file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()


def get_json(url: str, token: str) -> dict:
    r = subprocess.run(["curl", "-s", "-X", "GET", url, "-H", f"Authorization: Bearer {token}"], capture_output=True, text=True)
    r.check_returncode()
    try:
        return json.loads(r.stdout)
    except Exception:
        print(f"Failed to parse JSON from {url}", file=sys.stderr)
        print(r.stdout[:500], file=sys.stderr)
        sys.exit(1)


def stem_from_path(p: str) -> str:
    # GTEX-XXX.Aligned.sortedByCoord.out.patched.md__junction.bed -> GTEX-XXX
    bn = p.split('/')[-1]
    return bn.split('.')[0]


def load_input(path: Path) -> dict:
    return json.loads(path.read_text())


def build_sample_map(data: dict) -> Dict[str, Tuple[str, str]]:
    mapping: Dict[str, Tuple[str, str]] = {}
    bams = data.get('SplicingAnalysis.bam_files', []) or []
    bais = data.get('SplicingAnalysis.bai_files', []) or []
    for bam, bai in zip(bams, bais):
        mapping[stem_from_path(bam)] = (bam, bai)
    return mapping


def collect_bed_outputs(calls_obj: dict) -> Tuple[List[str], List[str]]:
    produced: List[str] = []
    failed_stems: List[str] = []
    bam_calls = calls_obj.get('SplicingAnalysis.BamToBedScatter') or calls_obj.get('BamToBedScatter') or []
    for it in bam_calls:
        status = it.get('executionStatus')
        shard_beds = (it.get('outputs') or {}).get('bed_files') or []
        if status == 'Done' and shard_beds:
            produced.extend(shard_beds)
        elif status == 'Failed':
            # try to infer stem from stderr or attempt localization
            stderr = it.get('stderr') or ''
            guess = ''
            if stderr:
                # path includes .../<sample>.__junction.bed
                parts = stderr.split('/')
                for comp in parts:
                    if comp.endswith('__junction.bed'):
                        guess = comp.split('.')[0]
                        break
            if not guess:
                # fallback to attempt to parse localized bam path if present
                guess = stem_from_path((it.get('inputs') or {}).get('bam_file', 'x.bam'))
            if guess:
                failed_stems.append(guess)
    # unique
    produced = sorted(set(produced))
    failed_stems = sorted(set(failed_stems))
    return produced, failed_stems


def adjust_resources(data: dict, failures: List[str], workflow_calls: dict) -> dict:
    # Heuristic bumps if specific errors detected
    # Scan messages for 'No space left' / OOM-like patterns
    text = json.dumps(workflow_calls)
    bump_disk = 'No space left' in text or 'no space left' in text
    bump_mem = ('exit code 137' in text) or ('Killed' in text)
    updated = dict(data)
    if bump_disk:
        updated['SplicingAnalysis.bam_to_bed_disk_multiplier'] = max(1.5, float(updated.get('SplicingAnalysis.bam_to_bed_disk_multiplier', 1.5)) + 0.2)
        updated['SplicingAnalysis.bam_to_bed_disk_buffer_gb'] = int(updated.get('SplicingAnalysis.bam_to_bed_disk_buffer_gb', 30)) + 10
    if bump_mem:
        # Simple step-up; keep conservative
        updated['SplicingAnalysis.bam_to_bed_memory'] = '12 GB'
    return updated


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--submission-id', required=True)
    p.add_argument('--input-json', required=True)
    p.add_argument('--out', required=True)
    p.add_argument('--project', default=os.environ.get('WORKSPACE_PROJECT', 'AltAnalyze3_SNAF'))
    p.add_argument('--workspace', default=os.environ.get('WORKSPACE_NAME', 'AltAnalyze3_SNAF'))
    args = p.parse_args()

    token = get_access_token()
    sub = get_json(f"{API}/workspaces/{args.project}/{args.workspace}/submissions/{args.submission_id}", token)
    wf_id = sub.get('workflows', [{}])[0].get('workflowId')
    if not wf_id:
        print('Cannot determine workflowId', file=sys.stderr)
        sys.exit(1)
    wf = get_json(f"{API}/workspaces/{args.project}/{args.workspace}/submissions/{args.submission_id}/workflows/{wf_id}", token)

    produced_beds, failed_stems = collect_bed_outputs(wf.get('calls') or {})

    src = Path(args.input_json)
    data = load_input(src)
    sample_map = build_sample_map(data)

    # Build new arrays: keep only failed BAM/BAI
    keep_bams: List[str] = []
    keep_bais: List[str] = []
    for stem, (bam, bai) in sample_map.items():
        if stem in failed_stems:
            keep_bams.append(bam)
            keep_bais.append(bai)
    # Merge produced beds with any existing extra beds
    extra_beds = sorted(set((data.get('SplicingAnalysis.extra_bed_files') or []) + produced_beds))

    new_data = dict(data)
    new_data['SplicingAnalysis.bam_files'] = keep_bams
    new_data['SplicingAnalysis.bai_files'] = keep_bais
    new_data['SplicingAnalysis.extra_bed_files'] = extra_beds
    # Ensure bed_only remains false to allow recomputing remaining BAMs
    new_data['SplicingAnalysis.bed_only'] = False
    new_data['SplicingAnalysis.stop_on_missing_beds'] = True

    new_data = adjust_resources(new_data, failed_stems, wf.get('calls') or {})

    Path(args.out).write_text(json.dumps(new_data, indent=2) + "\n")
    print(f"Wrote partial rerun inputs: {args.out}")
    print(f"  failed_bams: {len(keep_bams)} | extra_beds: {len(extra_beds)}")


if __name__ == '__main__':
    main()

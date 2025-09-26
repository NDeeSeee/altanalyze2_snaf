#!/bin/bash
set -euo pipefail
CSV="workflows/splicing_analysis/terra_runs/runs/submissions.csv"
if [[ ! -f "$CSV" ]]; then
  echo "No runs recorded yet."; exit 0
fi
tac "$CSV" | column -s, -t | less -S

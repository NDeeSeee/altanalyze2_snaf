#!/bin/bash
# Consolidated Terra submission monitor
# Creates one log file with status of all recent submissions, updated every minute
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SUBMISSIONS_CSV="$BASE_DIR/runs/submissions.csv"
CONSOLIDATED_LOG="$BASE_DIR/consolidated_status.log"
PROJECT="${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}"
WORKSPACE="${WORKSPACE_NAME:-AltAnalyze3_SNAF}"

# How many days back to monitor (only recent submissions)
DAYS_BACK=7

print_header() {
  echo "=== Terra Workflow Consolidated Monitor ===" | tee -a "$CONSOLIDATED_LOG"
  echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$CONSOLIDATED_LOG"
  echo "Monitoring submissions from last $DAYS_BACK days" | tee -a "$CONSOLIDATED_LOG"
  echo "" | tee -a "$CONSOLIDATED_LOG"
}

get_recent_submissions() {
  if [[ ! -f "$SUBMISSIONS_CSV" ]]; then
    echo "No submissions.csv found" >&2
    return 1
  fi

  # Get submissions from last N days that have submission_id (macOS compatible)
  cutoff_date=$(date -u -v-${DAYS_BACK}d +%Y-%m-%dT%H:%M:%SZ)
  awk -F, -v cutoff="$cutoff_date" '
    NR>1 && $1 >= cutoff && $5 != "" {
      print $2 "," $5 "," $9  # run_id,submission_id,description
    }' "$SUBMISSIONS_CSV"
}

check_submission_status() {
  local run_id="$1"
  local sub_id="$2"
  local description="$3"

  local status_info
  status_info=$(curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "https://api.firecloud.org/api/workspaces/$PROJECT/$WORKSPACE/submissions/$sub_id" 2>/dev/null | \
    python3 -c "
import sys, json
try:
  j = json.load(sys.stdin)
  status = j.get('status', 'UNKNOWN')
  cost = j.get('cost', 0)
  wf_count = len(j.get('workflows', []))

  # Count workflow statuses
  wf_statuses = {}
  for wf in j.get('workflows', []):
    wf_status = wf.get('status', 'UNKNOWN')
    wf_statuses[wf_status] = wf_statuses.get(wf_status, 0) + 1

  # Create summary
  wf_summary = ' '.join([f'{status}:{count}' for status, count in wf_statuses.items()])
  print(f'{status}|${cost:.2f}|{wf_count}|{wf_summary}')
except:
  print('ERROR|$0.00|0|API_FAIL:1')
" || echo "ERROR|\$0.00|0|NETWORK_FAIL:1")

  echo "$run_id|$sub_id|$status_info|$description"
}

update_status() {
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "[$timestamp] Checking submissions..." | tee -a "$CONSOLIDATED_LOG"

  local submissions
  submissions=$(get_recent_submissions)

  if [[ -z "$submissions" ]]; then
    echo "No recent submissions found" | tee -a "$CONSOLIDATED_LOG"
    return
  fi

  local active_count=0
  printf "%-22s %-40s %-12s %-8s %-4s %-20s %s\n" \
    "RUN_ID" "SUBMISSION_ID" "STATUS" "COST" "WFs" "WF_STATUS" "DESCRIPTION" | tee -a "$CONSOLIDATED_LOG"
  echo "$(printf '%*s' 120 '' | tr ' ' '-')" | tee -a "$CONSOLIDATED_LOG"

  while IFS=',' read -r run_id sub_id description; do
    local result
    result=$(check_submission_status "$run_id" "$sub_id" "$description")

    IFS='|' read -r r_run_id r_sub_id r_status r_cost r_wf_count r_wf_summary r_desc <<< "$result"

    # Count as active if not in terminal state
    if [[ "$r_status" =~ ^(Submitted|Evaluating|Running)$ ]]; then
      ((active_count++))
    fi

    printf "%-22s %-40s %-12s %-8s %-4s %-20s %s\n" \
      "$r_run_id" "$r_sub_id" "$r_status" "$r_cost" "$r_wf_count" "$r_wf_summary" "$r_desc" | tee -a "$CONSOLIDATED_LOG"

  done <<< "$submissions"

  echo "" | tee -a "$CONSOLIDATED_LOG"
  echo "Active submissions: $active_count" | tee -a "$CONSOLIDATED_LOG"
  echo "$(printf '%*s' 80 '' | tr ' ' '=')" | tee -a "$CONSOLIDATED_LOG"
  echo "" | tee -a "$CONSOLIDATED_LOG"
}

# Initialize log
print_header

echo "Starting consolidated monitoring (Ctrl+C to stop)..."
echo "Log file: $CONSOLIDATED_LOG"

# Main monitoring loop
while true; do
  update_status
  sleep 60  # Update every minute
done
#!/bin/bash
# Minimal Terra failure report: prints only high-signal errors
# Usage: quick_failure_report.sh -s SUBMISSION_ID [-p PROJECT] [-w WORKSPACE] [-t N_TAIL]
# Defaults: PROJECT=AltAnalyze3_SNAF, WORKSPACE=AltAnalyze3_SNAF, N_TAIL=0 (no log fetch)

set -euo pipefail

SUB_ID=""
PROJECT="${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}"
WORKSPACE="${WORKSPACE_NAME:-AltAnalyze3_SNAF}"
TAIL_N=0

while getopts ":s:p:w:t:h" opt; do
  case $opt in
    s) SUB_ID="$OPTARG" ;;
    p) PROJECT="$OPTARG" ;;
    w) WORKSPACE="$OPTARG" ;;
    t) TAIL_N="$OPTARG" ;;
    h)
      sed -n '1,20p' "$0"; exit 0 ;;
    :) echo "Missing arg for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ -z "$SUB_ID" ]]; then
  echo "❌ -s SUBMISSION_ID is required" >&2
  exit 2
fi

TOKEN=$(gcloud auth print-access-token)
BASE="https://api.firecloud.org/api"

# 1) Submission summary (minimal fields)
SUB_JSON=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "$BASE/workspaces/$PROJECT/$WORKSPACE/submissions/$SUB_ID")

python3 - "$SUB_JSON" <<'PY'
import json, sys
j=json.loads(sys.argv[1])
print(f"Submission: {j.get('submissionId')}  Status: {j.get('status')}  Cost: ${j.get('cost',0)}")
uc=j.get('userComment')
if uc: print(f"Comment: {uc}")
print(f"Date: {j.get('submissionDate')}")
print("")
print("Workflows:")
for wf in j.get('workflows',[]):
    print(f"- {wf.get('workflowId')}  {wf.get('status')}  Cost: ${wf.get('cost',0)}")
PY

# Early exit if nothing failed
if ! echo "$SUB_JSON" | python3 -c 'import sys,json; j=json.load(sys.stdin); import anyio' 2>/dev/null; then :; fi
FAILED_IDS=$(echo "$SUB_JSON" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(" ".join([w['workflowId'] for w in j.get('workflows',[]) if w.get('status')=='Failed']))
PY
)

if [[ -z "${FAILED_IDS// }" ]]; then
  echo "No failed workflows."
  exit 0
fi

# 2) For each failed workflow, fetch ONLY the failures tree and print concise lines
for WID in $FAILED_IDS; do
  echo ""
  echo "Failure details for $WID:";
  META=$(curl -sf -H "Authorization: Bearer $TOKEN" \
    "$BASE/workflows/v1/$WID/metadata?expandSubWorkflows=false&includeKey=failures&includeKey=status")
  echo "$META" | python3 - <<'PY'
import sys, json
m=json.load(sys.stdin)
print(f"Status: {m.get('status')}")
# Flatten failure messages
msgs=[]
for f in m.get('failures',[]):
    stack=[f]
    while stack:
        cur=stack.pop()
        msg=cur.get('message')
        if msg and msg not in msgs:
            msgs.append(msg)
        stack.extend(cur.get('causedBy',[]) or [])
print("Top errors:")
for i, msg in enumerate(msgs[:5],1):
    print(f"  {i}. {msg}")
PY

  # Optionally show a short tail of the main workflow log (very compact)
  if [[ "${TAIL_N}" != "0" ]]; then
    WS_JSON=$(curl -sf -H "Authorization: Bearer $TOKEN" "$BASE/workspaces/$PROJECT/$WORKSPACE")
    BUCKET=$(python3 -c 'import sys,json;print(json.load(sys.stdin).get("bucketName",""))' <<< "$WS_JSON")
    if [[ -n "$BUCKET" ]]; then
      LOG_URI=$(gsutil ls "gs://$BUCKET/submissions/$SUB_ID/workflow.logs/workflow.$WID.log" 2>/dev/null | head -1 || true)
      if [[ -n "$LOG_URI" ]]; then
        echo "Log tail ($TAIL_N lines): $LOG_URI"
        gsutil cat "$LOG_URI" | tail -n "$TAIL_N" || true
      else
        echo "(No workflow log yet)"
      fi
    fi
  fi

done

#!/bin/bash
# Submit a workflow via Terra Rawls API with submission toggles
# - Updates/creates a method config from a JSON inputs file
# - Submits with deleteIntermediateOutputFiles=true (and preserves call cache)
#
# Usage:
#   workflows/splicing_analysis/terra_runs/terra_rawls_submit.sh -i <inputs.json> \
#     -d "Description" [-p PROJECT] [-w WORKSPACE] [-n CONFIG_NAME] [-m NAMESPACE/method/version]
#
set -euo pipefail

INPUT_JSON=""
DESCRIPTION=""
CONFIG_NAME="snaf_cli"
METHOD_REF="${NAMESPACE:-AltAnalyze3_SNAF}/splicing_analysis/${SPLICING_METHOD_VERSION:-1}"
OVERRIDE_PROJECT=""
OVERRIDE_WORKSPACE=""

while getopts ":i:d:n:m:p:w:h" opt; do
  case $opt in
    i) INPUT_JSON="$OPTARG" ;;
    d) DESCRIPTION="$OPTARG" ;;
    n) CONFIG_NAME="$OPTARG" ;;
    m) METHOD_REF="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    h)
      echo "Usage: $0 -i INPUT_JSON -d DESCRIPTION [-n CONFIG_NAME] [-m NAMESPACE/method/version] [-p PROJECT] [-w WORKSPACE]";
      exit 0 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ -z "$INPUT_JSON" || -z "$DESCRIPTION" ]]; then
  echo "❌ -i and -d are required" >&2; exit 2
fi

# Load env
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [[ -f "$ENV_FILE" ]]; then source "$ENV_FILE"; break; fi
done

WORKSPACE_PROJECT="${OVERRIDE_PROJECT:-${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}}"
WORKSPACE_NAME="${OVERRIDE_WORKSPACE:-${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
NAMESPACE_PART=$(echo "$METHOD_REF" | cut -d/ -f1)
METHOD_NAME=$(echo "$METHOD_REF" | cut -d/ -f2)
METHOD_VER=$(echo "$METHOD_REF" | cut -d/ -f3)

TMP_DIR=$(mktemp -d)
INPUTS_ESC_JSON="$TMP_DIR/inputs_expressions.json"
CONFIG_JSON="$TMP_DIR/method_config.json"
TOKEN=$(gcloud auth print-access-token)
BASE_URL="https://api.firecloud.org/api"

# Convert INPUT_JSON values to method config input expressions
python3 - "$INPUT_JSON" > "$INPUTS_ESC_JSON" <<'PY'
import json, sys
src=sys.argv[1]
with open(src) as f:
    d=json.load(f)
out={}
for k,v in d.items():
    if not isinstance(k,str):
        continue
    # Skip non-WDL keys defensively
    if k.startswith('_'):
        continue
    try:
        out[k]=json.dumps(v)
    except Exception:
        continue
print(json.dumps(out, indent=2))
PY

# Build/Upsert method config payload
python3 - "$WORKSPACE_PROJECT" "$CONFIG_NAME" "$NAMESPACE_PART" "$METHOD_NAME" "$METHOD_VER" "$INPUTS_ESC_JSON" > "$CONFIG_JSON" <<'PY'
import json, sys, pathlib
proj, cfg_name, ns, mname, mver, inputs_path = sys.argv[1:7]
inputs = json.load(open(inputs_path))
config = {
  "namespace": proj,
  "name": cfg_name,
  "methodRepoMethod": {
    "methodNamespace": ns,
    "methodName": mname,
    "methodVersion": int(mver)
  },
  # Required by Rawls for config upsert
  "methodConfigVersion": 1,
  "rootEntityType": None,
  "prerequisites": {},
  "inputs": inputs,
  "outputs": {},
  "deleted": False
}
print(json.dumps(config))
PY

# Upsert method config
cfg_path_enc=$(python3 - <<PY
import urllib.parse as u
print(u.quote("$WORKSPACE_PROJECT"), u.quote("$CONFIG_NAME"))
PY
)
CFG_NS=$(echo "$cfg_path_enc" | awk '{print $1}')
CFG_NAME=$(echo "$cfg_path_enc" | awk '{print $2}')

# Try PUT (update); if 404, POST (create)
if ! curl -sf -X PUT "$BASE_URL/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/methodconfigs/$CFG_NS/$CFG_NAME" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @"$CONFIG_JSON" >/dev/null; then
  curl -sf -X POST "$BASE_URL/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/methodconfigs" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @"$CONFIG_JSON" >/dev/null
fi

echo "✅ Method config ready: $WORKSPACE_PROJECT/$CONFIG_NAME -> $METHOD_REF"

# Create submission with toggles
SUB_JSON="$TMP_DIR/submission.json"
cat > "$SUB_JSON" <<EOF
{
  "methodConfigurationNamespace": "$WORKSPACE_PROJECT",
  "methodConfigurationName": "$CONFIG_NAME",
  "entity": null,
  "useCallCache": true,
  "deleteIntermediateOutputFiles": true,
  "useReferenceDisks": false,
  "memoryRetryMultiplier": 1.0,
  "userComment": "$DESCRIPTION"
}
EOF

SUB_RESP=$(curl -s -X POST "$BASE_URL/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/submissions" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @"$SUB_JSON")

SUB_ID=$(echo "$SUB_RESP" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("submissionId",""))')
if [[ -z "$SUB_ID" ]]; then
  echo "❌ Submission failed" >&2
  echo "$SUB_RESP" >&2
  exit 1
fi

JOB_URL="https://app.terra.bio/#workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME/job_history/$SUB_ID"
echo "🚀 Submitted via Rawls: $JOB_URL"

rm -rf "$TMP_DIR"

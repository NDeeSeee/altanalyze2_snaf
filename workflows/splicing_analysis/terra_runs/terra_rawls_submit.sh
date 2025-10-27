#!/bin/bash
# Submit a workflow via Terra Rawls API with submission toggles
# - Updates/creates a method config from a JSON inputs file
# - Submits with deleteIntermediateOutputFiles=true (and preserves call cache)
#
# Usage:
#   workflows/splicing_analysis/terra_runs/terra_rawls_submit.sh -i <inputs.json> \
#     -d "Description" [-p PROJECT] [-w WORKSPACE] [-n CONFIG_NAME] [-m NAMESPACE/method/version] [-C MAX_COST_USD] [-R MEMORY_RETRY_MULTIPLIER] [-e ENTITY_NAME] [-E ENTITY_TYPE]
#
set -euo pipefail

INPUT_JSON=""
DESCRIPTION=""
CONFIG_NAME="snaf_cli"
METHOD_REF="${NAMESPACE:-AltAnalyze3_SNAF}/splicing_analysis/${SPLICING_METHOD_VERSION:-8}"
OVERRIDE_PROJECT=""
OVERRIDE_WORKSPACE=""
MAX_COST_USD=""
MEMORY_RETRY_MULTIPLIER="1.0"
ENTITY_NAME=""
ENTITY_TYPE=""

while getopts ":i:d:n:m:p:w:C:R:e:E:h" opt; do
  case $opt in
    i) INPUT_JSON="$OPTARG" ;;
    d) DESCRIPTION="$OPTARG" ;;
    n) CONFIG_NAME="$OPTARG" ;;
    m) METHOD_REF="$OPTARG" ;;
    p) OVERRIDE_PROJECT="$OPTARG" ;;
    w) OVERRIDE_WORKSPACE="$OPTARG" ;;
    C) MAX_COST_USD="$OPTARG" ;;
    R) MEMORY_RETRY_MULTIPLIER="$OPTARG" ;;
    e) ENTITY_NAME="$OPTARG" ;;
    E) ENTITY_TYPE="$OPTARG" ;;
    h)
      echo "Usage: $0 -i INPUT_JSON -d DESCRIPTION [-n CONFIG_NAME] [-m NAMESPACE/method/version] [-p PROJECT] [-w WORKSPACE] [-C MAX_COST_USD] [-R MEMORY_RETRY_MULTIPLIER] [-e ENTITY_NAME] [-E ENTITY_TYPE]";
      exit 0 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 2 ;;
    \?) echo "Unknown option -$OPTARG" >&2; exit 2 ;;
  esac
done

if [[ -z "$INPUT_JSON" || -z "$DESCRIPTION" ]]; then
  echo "❌ -i and -d are required" >&2; exit 2
fi

if [[ -n "$ENTITY_NAME" && -z "$ENTITY_TYPE" ]]; then
  ENTITY_TYPE="sample_set"
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
INPUT_COPY="$TMP_DIR/input.json"
cp "$INPUT_JSON" "$INPUT_COPY"
INPUT_JSON="$INPUT_COPY"
INPUTS_ESC_JSON="$TMP_DIR/inputs_expressions.json"
CONFIG_JSON="$TMP_DIR/method_config.json"
TOKEN=$(gcloud auth print-access-token)
BASE_URL="https://api.firecloud.org/api"

if [[ -z "${RUN_ID:-}" ]]; then
  RUN_ID="$(date +%Y%m%d-%H%M%S)-$RANDOM"
  export RUN_ID
fi

if [[ -z "${WORKSPACE_BUCKET:-}" ]]; then
  WORKSPACE_BUCKET=$(curl -s -X GET "$BASE_URL/workspaces/$WORKSPACE_PROJECT/$WORKSPACE_NAME" \
    -H "Authorization: Bearer $TOKEN" |
    python3 -c 'import sys,json; data=json.load(sys.stdin); print(data.get("workspace",{}).get("bucketName",""))')
  if [[ -n "$WORKSPACE_BUCKET" ]]; then
    export WORKSPACE_BUCKET
  fi
fi

if [[ -n "${WORKSPACE_BUCKET:-}" ]]; then
  MANIFEST=$(python3 - "$INPUT_JSON" <<'PY'
import json, sys, os, pathlib
json_path = pathlib.Path(sys.argv[1])
data = json.load(open(json_path))
bucket = os.environ['WORKSPACE_BUCKET']
run_id = os.environ.get('RUN_ID', 'staging')
threshold = int(os.environ.get('STAGING_LIST_THRESHOLD', '50'))
staged = []
for key, value in list(data.items()):
    if key.startswith('_'):
        continue
    if isinstance(value, list) and len(value) > threshold:
        suffix = key.replace('.', '_')
        local = json_path.parent / f"{suffix}.json"
        json.dump(value, open(local, 'w'))
        gs = f"gs://{bucket}/gtex_staged_inputs/{run_id}/{suffix}.json"
        data[key] = {"__rawls_expr__": f'read_json("{gs}")'}
        staged.append((str(local), gs))

if staged:
    json.dump(data, open(json_path, 'w'), indent=2)
    manifest = json_path.parent / 'staged_manifest.tsv'
    with open(manifest, 'w') as fh:
        for local, gs in staged:
            fh.write(f"{local}\t{gs}\n")
    print(manifest)
else:
    print('')
PY
)
  if [[ -n "$MANIFEST" ]]; then
    echo "📤 Uploading staged inputs"
    while IFS=$'\t' read -r local_path gs_path; do
      [[ -z "$local_path" ]] && continue
      gsutil cp "$local_path" "$gs_path" >/dev/null
    done < "$MANIFEST"
  fi
fi

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
    if isinstance(v, dict) and '__rawls_expr__' in v:
        out[k]=v['__rawls_expr__']
        continue
    try:
        out[k]=json.dumps(v)
    except Exception:
        continue
print(json.dumps(out, indent=2))
PY

# Build/Upsert method config payload
RAWLS_ENTITY_TYPE="$ENTITY_TYPE" python3 - <<'PY' "$WORKSPACE_PROJECT" "$CONFIG_NAME" "$NAMESPACE_PART" "$METHOD_NAME" "$METHOD_VER" "$INPUTS_ESC_JSON" > "$CONFIG_JSON"
import json, os, sys
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
  "rootEntityType": os.environ.get("RAWLS_ENTITY_TYPE"),
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

python3 - <<'PY' "$ENTITY_NAME" "$ENTITY_TYPE" "$SUB_JSON" "$WORKSPACE_PROJECT" "$CONFIG_NAME" "$DESCRIPTION" "$MEMORY_RETRY_MULTIPLIER"
import json, sys
entity_name, entity_type, out_path, workspace_project, config_name, description, memory_retry = sys.argv[1:8]
payload = {
    "methodConfigurationNamespace": workspace_project,
    "methodConfigurationName": config_name,
    "entity": None,
    "useCallCache": True,
    "deleteIntermediateOutputFiles": False,
    "useReferenceDisks": False,
    "memoryRetryMultiplier": float(memory_retry),
    "userComment": description,
}
if entity_name:
    resolved_type = entity_type or "sample_set"
    payload["entity"] = {
        "entityType": resolved_type,
        "entityName": entity_name,
    }
    payload["rootEntityType"] = resolved_type
else:
    payload["rootEntityType"] = None
with open(out_path, "w") as fh:
    json.dump(payload, fh, indent=2)
PY

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

# Persist server-side cost threshold hint (not enforced by Rawls, shown for audit)
if [[ -n "$MAX_COST_USD" ]]; then
  echo "{"submissionId":"$SUB_ID","max_cost_usd":$MAX_COST_USD}" > "$TMP_DIR/max_cost_hint.json"
  echo "ℹ️  Cost threshold hint attached locally (not enforced by server): $$MAX_COST_USD"
fi

rm -rf "$TMP_DIR"

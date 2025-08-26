#!/bin/bash
# Preflight checks for Terra workflows
# - Verifies env configuration
# - Validates JSON inputs against WDL
# - Checks Terra access

set -euo pipefail

# Load env (global preferred, then local)
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

: "${WORKSPACE_PROJECT:?WORKSPACE_PROJECT required}"
: "${WORKSPACE_NAME:?WORKSPACE_NAME required}"
: "${NAMESPACE:?NAMESPACE required}"

WDL="workflows/splicing_analysis/splicing_analysis.wdl"
VALIDATOR="workflows/splicing_analysis/terra_runs/validate_inputs_against_wdl.py"

echo "🧪 Preflight checks..."

# 1) WDL presence
[ -f "$WDL" ] || { echo "❌ Missing WDL: $WDL"; exit 1; }

# 2) Terra access
if fissfc space_list 2>/dev/null | grep -q "$WORKSPACE_NAME"; then
  echo "✅ Terra workspace visible: $WORKSPACE_PROJECT/$WORKSPACE_NAME"
else
  echo "❌ Terra workspace not visible: $WORKSPACE_PROJECT/$WORKSPACE_NAME"; exit 1
fi

# 3) Methods presence (namespace)
if fissfc meth_list -n "$NAMESPACE" 2>/dev/null | grep -q "splicing_analysis"; then
  echo "✅ Method present in namespace: $NAMESPACE/splicing_analysis"
else
  echo "⚠️ Method not found in namespace: $NAMESPACE/splicing_analysis (you may need to upload)"
fi

# 4) Input validation (default GTEx sets if exist)
if [ -x "$(command -v python3)" ] && [ -f "$VALIDATOR" ]; then
  python3 "$VALIDATOR" || echo "⚠️ Input validation warnings (see above)"
else
  echo "ℹ️ Validator not available; skipping input validation"
fi

echo "✅ Preflight complete"

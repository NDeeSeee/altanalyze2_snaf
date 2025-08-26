#!/bin/bash
# Terra CLI Authentication Setup
# Complete authentication and environment verification for Terra workflow execution

set -euo pipefail

echo "🔐 Setting up Terra CLI Authentication..."

# Optional: source env for workspace names to validate (prefer global, then local)
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

# ============================================================================
# Step 1: Verify Google Cloud SDK Installation
# ============================================================================
echo "📋 Step 1: Verifying Google Cloud SDK..."

if ! command -v gcloud &> /dev/null; then
    echo "❌ Google Cloud SDK not found!"
    echo "Install: brew install google-cloud-sdk"
    exit 1
fi

gcloud --version
echo "✅ Google Cloud SDK installed"

# ============================================================================
# Step 2: Verify Altocumulus Installation
# ============================================================================
echo "📋 Step 2: Verifying Altocumulus installation..."

if ! command -v alto &> /dev/null; then
    echo "❌ Altocumulus not found!"
    echo "Install: pip install altocumulus"
    exit 1
fi

alto --version
fissfc --version
gsutil version -l | head -5
echo "✅ Altocumulus and dependencies installed"

# ============================================================================
# Step 3: Google Cloud Authentication
# ============================================================================
echo "📋 Step 3: Setting up Google Cloud authentication..."

# User authentication for gcloud commands
echo "Setting up user authentication..."
gcloud auth login
echo "✅ User authentication complete"

# Application Default Credentials (CRITICAL for Alto)
echo "Setting up Application Default Credentials..."
gcloud auth application-default login
echo "✅ Application Default Credentials set"

# Verify authentication
echo "Verifying authentication..."
echo "Active accounts:"
gcloud auth list

echo "Testing application default credentials..."
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "✅ Application default credentials working"
else
    echo "❌ Application default credentials failed"
    exit 1
fi

# ============================================================================
# Step 4: Verify Terra Access
# ============================================================================
echo "📋 Step 4: Verifying Terra workspace access..."

echo "Testing Terra workspace access..."
WORKSPACE_NAME_CHECK=${WORKSPACE_NAME:-AltAnalyze3_SNAF}
WORKSPACE_PROJECT_CHECK=${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}
if fissfc space_list | grep -q "$WORKSPACE_NAME_CHECK"; then
    echo "✅ Terra workspace accessible"
else
    echo "❌ Cannot access Terra workspace"
    echo "Ensure you have access to $WORKSPACE_PROJECT_CHECK/$WORKSPACE_NAME_CHECK workspace"
    exit 1
fi

# Get workspace details
echo "Workspace information:"
fissfc space_info -w "$WORKSPACE_NAME_CHECK" -p "$WORKSPACE_PROJECT_CHECK"

# ============================================================================
# Step 5: Test Basic Commands
# ============================================================================
echo "📋 Step 5: Testing basic CLI commands..."

# Test alto terra commands
echo "Testing alto terra commands..."
alto terra --help >/dev/null
echo "✅ Alto terra commands working"

# Test storage estimation
echo "Testing storage estimation..."
alto terra storage_estimate --output /tmp/test_storage.tsv --access owner
if [ -f /tmp/test_storage.tsv ]; then
    echo "✅ Storage estimation working"
    rm -f /tmp/test_storage.tsv
else
    echo "⚠️ Storage estimation may have issues"
fi

# Test gsutil access
echo "Testing Google Cloud Storage access..."
if gsutil ls >/dev/null 2>&1; then
    echo "✅ Google Cloud Storage accessible"
else
    echo "⚠️ Google Cloud Storage access may be limited"
fi

echo ""
echo "🎉 Authentication setup complete!"
echo ""
echo "Next steps:"
echo "1. Run: source 02_workflow_management.sh"
echo "2. Upload your workflows to Terra"
echo "3. Submit jobs for processing"

# ============================================================================
# Environment Summary
# ============================================================================
echo ""
echo "📊 Environment Summary:"
echo "========================"
echo "Google Cloud SDK: $(gcloud --version | head -1)"
echo "Altocumulus: $(alto --version)"
echo "FISS: $(fissfc --version)"
echo "gsutil: $(gsutil version | head -1)"
echo "Active account: $(gcloud config get-value account)"
echo "Workspace access: ✅ ${WORKSPACE_PROJECT_CHECK}/${WORKSPACE_NAME_CHECK}"
echo "========================"
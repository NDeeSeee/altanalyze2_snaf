#!/bin/bash
# Terra Workflow Management
# Upload, manage, and version control workflows in Terra's Broad Methods Repository

set -euo pipefail

echo "⚙️ Terra Workflow Management..."

# Configuration (source env if available, then set safe defaults)
for ENV_FILE in workflows/terra/env.sh workflows/splicing_analysis/terra_runs/env.sh; do
  if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    break
  fi
done

: "${NAMESPACE:=${NAMESPACE:-AltAnalyze3_SNAF}}"
: "${WORKSPACE:=${WORKSPACE_PROJECT:-AltAnalyze3_SNAF}/${WORKSPACE_NAME:-AltAnalyze3_SNAF}}"
WDL_PATH="workflows/splicing_analysis/splicing_analysis.wdl"
STAR_WDL_PATH="workflows/star_alignment/star_alignment.wdl"

# ============================================================================
# Step 1: Verify Workflow Files Exist
# ============================================================================
echo "📋 Step 1: Verifying workflow files..."

if [ ! -f "$WDL_PATH" ]; then
    echo "❌ Splicing analysis WDL not found: $WDL_PATH"
    exit 1
fi

if [ ! -f "$STAR_WDL_PATH" ]; then
    echo "❌ STAR alignment WDL not found: $STAR_WDL_PATH"
    exit 1
fi

echo "✅ Workflow files found"
echo "  - Splicing: $WDL_PATH"
echo "  - STAR: $STAR_WDL_PATH"

# ============================================================================
# Step 2: List Current Methods in Namespace
# ============================================================================
echo "📋 Step 2: Checking existing methods in namespace..."

echo "Current methods in $NAMESPACE:"
if fissfc meth_list -n "$NAMESPACE" 2>/dev/null; then
    echo "✅ Namespace accessible"
else
    echo "⚠️ No existing methods or namespace access issues"
fi

# ============================================================================
# Step 3: Upload Splicing Analysis Workflow
# ============================================================================
echo "📋 Step 3: Uploading splicing analysis workflow..."

echo "Uploading $WDL_PATH to namespace $NAMESPACE..."
if alto terra add_method -n "$NAMESPACE" "$WDL_PATH"; then
    echo "✅ Splicing analysis workflow uploaded successfully"
    
    # Get the method URL for reference
    echo "Method details:"
    fissfc meth_list -n "$NAMESPACE" | grep splicing_analysis || echo "Method uploaded but listing may be delayed"
else
    echo "❌ Failed to upload splicing analysis workflow"
    exit 1
fi

# ============================================================================
# Step 4: Upload STAR Alignment Workflow
# ============================================================================
echo "📋 Step 4: Uploading STAR alignment workflow..."

echo "Uploading $STAR_WDL_PATH to namespace $NAMESPACE..."
if alto terra add_method -n "$NAMESPACE" "$STAR_WDL_PATH"; then
    echo "✅ STAR alignment workflow uploaded successfully"
else
    echo "❌ Failed to upload STAR alignment workflow"
    exit 1
fi

# ============================================================================
# Step 5: Verify Uploaded Methods
# ============================================================================
echo "📋 Step 5: Verifying uploaded methods..."

echo "All methods in namespace $NAMESPACE:"
fissfc meth_list -n "$NAMESPACE"

# Check specific methods
EXPECTED_METHODS=("splicing_analysis" "star_alignment")
for method in "${EXPECTED_METHODS[@]}"; do
    if fissfc meth_list -n "$NAMESPACE" | grep -q "$method"; then
        echo "✅ $method uploaded and accessible"
    else
        echo "❌ $method not found in namespace"
    fi
done

# ============================================================================
# Step 6: Method Version Information
# ============================================================================
echo "📋 Step 6: Method version information..."

echo ""
echo "🔧 Method Management Commands:"
echo "=============================="

echo "List all methods:"
echo "  fissfc meth_list -n $NAMESPACE"
echo ""

echo "Use specific version:"
echo "  alto terra run -m \"$NAMESPACE/splicing_analysis/1\" -w \"$WORKSPACE\" -i input.json"
echo ""

echo "Use latest version:"
echo "  alto terra run -m \"$NAMESPACE/splicing_analysis\" -w \"$WORKSPACE\" -i input.json"
echo ""

echo "Upload new version:"
echo "  alto terra add_method -n $NAMESPACE $WDL_PATH  # Creates version 2"
echo ""

echo "Version selection examples:"
echo "  - Version 1: $NAMESPACE/splicing_analysis/1"
echo "  - Latest:   $NAMESPACE/splicing_analysis"
echo "  - Version 2: $NAMESPACE/splicing_analysis/2 (after re-upload)"

# ============================================================================
# Step 7: Create Method Reference
# ============================================================================
echo "📋 Step 7: Creating method reference file..."

cat > workflows/splicing_analysis/terra_runs/method_info.txt << EOF
# Terra Method Information
# Generated: $(date)

Namespace: $NAMESPACE
Workspace: $WORKSPACE

Available Methods:
==================

Splicing Analysis:
  Name: splicing_analysis
  Current Version: 1
  Method Reference: $NAMESPACE/splicing_analysis/1
  WDL Source: $WDL_PATH

STAR Alignment:
  Name: star_alignment  
  Current Version: 1
  Method Reference: $NAMESPACE/star_alignment/1
  WDL Source: $STAR_WDL_PATH

Usage Examples:
===============

# Submit splicing analysis
alto terra run \\
  -m "$NAMESPACE/splicing_analysis/1" \\
  -w "$WORKSPACE" \\
  -i "input.json"

# Submit STAR alignment
alto terra run \\
  -m "$NAMESPACE/star_alignment/1" \\
  -w "$WORKSPACE" \\
  -i "star_input.json"

Method URLs:
============
$(fissfc meth_list -n "$NAMESPACE" 2>/dev/null | while read -r ns method version; do
  if [ "$ns" = "$NAMESPACE" ]; then
    echo "$method v$version: https://api.firecloud.org/ga4gh/v1/tools/$ns:$method/versions/$version/plain-WDL/descriptor"
  fi
done)

EOF

echo "✅ Method reference saved to workflows/splicing_analysis/terra_runs/method_info.txt"

echo ""
echo "🎉 Workflow management complete!"
echo ""
echo "Next steps:"
echo "1. Run: source 03_job_submission.sh"
echo "2. Submit jobs using uploaded workflows"
echo "3. Monitor execution with 04_monitoring_commands.sh"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "📊 Upload Summary:"
echo "=================="
echo "Namespace: $NAMESPACE"
echo "Methods uploaded:"
fissfc meth_list -n "$NAMESPACE"
echo "=================="
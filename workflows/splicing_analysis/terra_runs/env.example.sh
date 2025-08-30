#!/bin/bash
# Copy to env.sh and customize for your Terra workspace
# Usage: source workflows/splicing_analysis/terra_runs/env.sh

# Required identifiers
export NAMESPACE="AltAnalyze3_SNAF"
export WORKSPACE_PROJECT="AltAnalyze3_SNAF"
export WORKSPACE_NAME="AltAnalyze3_SNAF"
export WORKSPACE="${WORKSPACE_PROJECT}/${WORKSPACE_NAME}"

# Workspace bucket (name without gs://)
# Tip: fissfc space_info -w "$WORKSPACE_NAME" -p "$WORKSPACE_PROJECT" | grep bucketName
export WORKSPACE_BUCKET="fc-secure-29923ebe-0f0e-4caa-ac05-e39f9484b26f"

# Methods and versions
export SPLICING_METHOD_NAME="splicing_analysis"
export STAR_METHOD_NAME="star_alignment"
# Use a specific version or leave empty to use "latest"
export SPLICING_METHOD_VERSION="1"
export STAR_METHOD_VERSION="1"

# Docker image default (can be overridden in input JSON)
export ALTANALYZE_DOCKER_DEFAULT="ndeeseee/altanalyze:v1.6.39"

# Helper to build method strings
terra_method_ref() {
  local method_name="$1"
  local ver="$2"
  if [[ -n "$ver" ]]; then
    echo "${NAMESPACE}/${method_name}/${ver}"
  else
    echo "${NAMESPACE}/${method_name}"
  fi
}

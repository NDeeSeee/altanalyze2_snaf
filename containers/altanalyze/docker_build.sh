#!/bin/bash

##############################################################################
# Build and Test Script for AltAnalyze Splicing Analysis Container
##############################################################################
# Description: Builds Docker image and runs basic validation tests
# Usage: bash docker_build.sh [--skip-build] [--skip-test] [--tag TAG]
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="ndeeseee/altanalyze"
IMAGE_TAG="latest"

# Parse command line arguments
SKIP_BUILD=false
SKIP_TEST=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-build] [--skip-test] [--tag TAG]"
            exit 1
            ;;
    esac
done

FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

# Function to check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon is not running"
        exit 1
    fi
}

# Function to prepare build context
prepare_build_context() {
    echo "Preparing build context..."
    
    # Copy optional resource monitor into build context for embedding
    if [[ -f "${PROJECT_ROOT}/containers/resource-monitor/monitor.sh" ]]; then
        cp "${PROJECT_ROOT}/containers/resource-monitor/monitor.sh" "${SCRIPT_DIR}/monitor.sh"
    fi

    # Optionally copy AltAnalyze.sh override if provided in scripts/ (legacy path)
    if [[ -f "${PROJECT_ROOT}/scripts/AltAnalyze.sh" ]]; then
        cp "${PROJECT_ROOT}/scripts/AltAnalyze.sh" "${SCRIPT_DIR}/AltAnalyze.sh"
    fi
    
    # Create a minimal prune.py script if it doesn't exist
    if [[ ! -f "${SCRIPT_DIR}/prune.py" ]]; then
        cat > "${SCRIPT_DIR}/prune.py" << 'EOF'
#!/usr/bin/env python3
"""
Prune raw junction count matrix to contain only PSI junctions
This is a placeholder script - implement specific pruning logic as needed
"""
import sys
import os

def main():
    print("Pruning junction count matrix...")
    # Add specific pruning logic here
    print("Pruning completed.")

if __name__ == "__main__":
    main()
EOF
        chmod +x "${SCRIPT_DIR}/prune.py"
    fi
}

# Function to build Docker image
build_image() {
    echo "Building Docker image: ${FULL_IMAGE}"
    echo "Build context: ${SCRIPT_DIR}"
    
    prepare_build_context
    
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --tag "${FULL_IMAGE}" \
        --file "${SCRIPT_DIR}/Dockerfile" \
        "${SCRIPT_DIR}"
    
    echo "Docker image built successfully: ${FULL_IMAGE}"
    docker images "${IMAGE_NAME}" | head -5
}

# Function to test the container
test_container() {
    echo "Testing container functionality..."
    
    # Test 1: Check if Python is available
    echo "Test 1: Checking Python installation"
    if docker run --rm "${FULL_IMAGE}" python3 --version; then
        echo "✅ Python installation verified"
    else
        echo "❌ Python installation test failed"
        return 1
    fi
    
    # Test 2: Check if AltAnalyze directory exists
    echo "Test 2: Checking AltAnalyze installation"
    if docker run --rm "${FULL_IMAGE}" ls /usr/src/app/altanalyze/AltAnalyze.py; then
        echo "✅ AltAnalyze installation verified"
    else
        echo "❌ AltAnalyze installation test failed"
        return 1
    fi
    
    # Test 3: Check if AltAnalyze.sh script is executable
    echo "Test 3: Checking AltAnalyze.sh script"
    if docker run --rm "${FULL_IMAGE}" bash -c "test -x /usr/src/app/AltAnalyze.sh"; then
        echo "✅ AltAnalyze.sh script is executable"
    else
        echo "❌ AltAnalyze.sh script test failed"
        return 1
    fi
    
    # Test 4: Check required Python packages
    echo "Test 4: Checking Python dependencies"
    if docker run --rm "${FULL_IMAGE}" python3 -c "import numpy, scipy, pandas; print('All required packages available')"; then
        echo "✅ Python dependencies verified"
    else
        echo "❌ Python dependencies test failed"
        return 1
    fi
    
    # Test 5: Check container security (running as non-root)
    echo "Test 5: Checking security (non-root user)"
    USER_ID=$(docker run --rm "${FULL_IMAGE}" id -u)
    if [[ "${USER_ID}" != "0" ]]; then
        echo "✅ Container runs as non-root user (UID: ${USER_ID})"
    else
        echo "⚠️  Container runs as root user"
    fi
    
    # Test 6: Check GNU Parallel availability
    echo "Test 6: Checking GNU Parallel installation"
    if docker run --rm "${FULL_IMAGE}" parallel --version | grep -q "GNU parallel"; then
        echo "✅ GNU Parallel installation verified"
    else
        echo "❌ GNU Parallel installation test failed"
        return 1
    fi
    
    echo "All container tests completed successfully"
}

# Function to show usage information
show_usage() {
    echo "Container Usage Examples:"
    echo ""
    echo "1. BAM to BED conversion:"
    echo "   docker run --rm \\"
    echo "     -v /path/to/data:/mnt \\"
    echo "     ${FULL_IMAGE} \\"
    echo "     bam_to_bed bam/sample.bam"
    echo ""
    echo "2. BED to junction analysis:"
    echo "   docker run --rm \\"
    echo "     -v /path/to/data:/mnt \\"
    echo "     ${FULL_IMAGE} \\"
    echo "     bed_to_junction bed_folder"
    echo ""
    echo "3. Complete pipeline (identify mode):"
    echo "   docker run --rm \\"
    echo "     -v /path/to/data:/mnt \\"
    echo "     ${FULL_IMAGE} \\"
    echo "     identify bam_folder 4"
    echo ""
    echo "4. WDL workflow execution:"
    echo "   Use the workflows/splicing_analysis.wdl with Cromwell or Terra"
    echo ""
    echo "5. Available modes:"
    echo "   - bam_to_bed: Convert BAM to BED files"
    echo "   - bed_to_junction: Analyze junctions from BED files"
    echo "   - identify: Full pipeline with parallelization"
    echo "   - DE: Differential expression analysis"
    echo "   - GO: Gene ontology enrichment"
    echo "   - DAS: Differential alternative splicing"
}

# Function to cleanup build context
cleanup() {
    echo "Cleaning up build context..."
    rm -f "${SCRIPT_DIR}/AltAnalyze.sh"
    rm -f "${SCRIPT_DIR}/monitor.sh"
    rm -f "${SCRIPT_DIR}/prune.py"
}

# Main execution
main() {
    echo "AltAnalyze Splicing Analysis Container Build and Test"
    echo "===================================================="
    echo "Image: ${FULL_IMAGE}"
    echo ""
    
    # Set trap to cleanup on exit
    trap cleanup EXIT
    
    check_docker
    
    if [[ "${SKIP_BUILD}" == "false" ]]; then
        build_image
    else
        echo "Skipping build step"
    fi
    
    if [[ "${SKIP_TEST}" == "false" ]]; then
        test_container
    else
        echo "Skipping test step"
    fi
    
    show_usage
    
    echo ""
    echo "Build and test completed successfully!"
    echo "Image: ${FULL_IMAGE}"
    echo ""
    echo "To push to registry:"
    echo "  docker push ${FULL_IMAGE}"
}

# Run main function
main "$@"
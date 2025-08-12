#!/bin/bash

##############################################################################
# Build and Test Script for STAR 2-Pass Alignment Container
##############################################################################
# Description: Builds Docker image and runs basic validation tests
# Usage: bash build_and_test.sh [--skip-build] [--skip-test]
##############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="ndeeseee/star-aligner"
IMAGE_TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-build] [--skip-test]"
            exit 1
            ;;
    esac
done

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

# Function to build Docker image
build_image() {
    echo "Building Docker image: ${FULL_IMAGE}"
    echo "Build context: ${SCRIPT_DIR}"
    
    docker build \
        --tag "${FULL_IMAGE}" \
        --file "${SCRIPT_DIR}/Dockerfile" \
        "${SCRIPT_DIR}"
    
    echo "Docker image built successfully: ${FULL_IMAGE}"
    docker images "${IMAGE_NAME}"
}

# Function to test the container
test_container() {
    echo "Testing container functionality..."
    
    # Test 1: Check if STAR is available and shows version
    echo "Test 1: Checking STAR installation"
    if docker run --rm "${FULL_IMAGE}" bash -c "STAR --version"; then
        echo "✅ STAR installation verified"
    else
        echo "❌ STAR installation test failed"
        return 1
    fi
    
    # Test 2: Check help message
    echo "Test 2: Checking help message"
    if docker run --rm "${FULL_IMAGE}" --help | grep -q "Usage:"; then
        echo "✅ Help message test passed"
    else
        echo "❌ Help message test failed"
        return 1
    fi
    
    # Test 3: Check container security (running as non-root)
    echo "Test 3: Checking security (non-root user)"
    USER_ID=$(docker run --rm "${FULL_IMAGE}" id -u)
    if [[ "${USER_ID}" != "0" ]]; then
        echo "✅ Container runs as non-root user (UID: ${USER_ID})"
    else
        echo "⚠️  Container runs as root user"
    fi
    
    echo "All container tests completed successfully"
}

# Function to show usage information
show_usage() {
    echo "Container Usage Examples:"
    echo ""
    echo "1. Run with help:"
    echo "   docker run --rm ${FULL_IMAGE} --help"
    echo ""
    echo "2. Run alignment (with volume mounts):"
    echo "   docker run --rm \\"
    echo "     -v /path/to/data:/data \\"
    echo "     ${FULL_IMAGE} \\"
    echo "     /data/input/sample.1.fastq.gz \\"
    echo "     /data/reference/star_index \\"
    echo "     /data/reference/genome.fa \\"
    echo "     /data/output"
    echo ""
    echo "3. WDL workflow execution:"
    echo "   Use the star_2pass_alignment.wdl with Cromwell or Terra"
}

# Main execution
main() {
    echo "STAR 2-Pass Alignment Container Build and Test"
    echo "=============================================="
    
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
}

# Run main function
main "$@"
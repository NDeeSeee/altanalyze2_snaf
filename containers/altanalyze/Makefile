# AltAnalyze Docker Container Makefile
# Usage: make [target]

# Configuration
IMAGE_NAME := ndeeseee/altanalyze
IMAGE_TAG := latest
FULL_IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)

# Default target
.PHONY: help
help:
	@echo "AltAnalyze Docker Container Management"
	@echo "====================================="
	@echo ""
	@echo "Available targets:"
	@echo "  build          Build the Docker image"
	@echo "  test           Test the built image"
	@echo "  build-test     Build and test the image"
	@echo "  push           Push image to registry"
	@echo "  clean          Remove local image"
	@echo "  run            Run container interactively"
	@echo "  shell          Open bash shell in container"
	@echo "  help           Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make build IMAGE_TAG=v1.5.1"
	@echo "  make test"
	@echo "  make push"

# Build the Docker image
.PHONY: build
build:
	@echo "Building Docker image: $(FULL_IMAGE)"
	./docker_build.sh --skip-test

# Test the Docker image
.PHONY: test
test:
	@echo "Testing Docker image: $(FULL_IMAGE)"
	./docker_build.sh --skip-build

# Build and test
.PHONY: build-test
build-test:
	@echo "Building and testing Docker image: $(FULL_IMAGE)"
	./docker_build.sh

# Push image to registry
.PHONY: push
push:
	@echo "Pushing Docker image: $(FULL_IMAGE)"
	docker push $(FULL_IMAGE)

# Clean up local image
.PHONY: clean
clean:
	@echo "Removing Docker image: $(FULL_IMAGE)"
	docker rmi $(FULL_IMAGE) || true

# Run container with volume mount
.PHONY: run
run:
	@echo "Running container: $(FULL_IMAGE)"
	docker run --rm -it -v $(shell pwd)/..:/mnt $(FULL_IMAGE) --help

# Open shell in container
.PHONY: shell
shell:
	@echo "Opening shell in container: $(FULL_IMAGE)"
	docker run --rm -it -v $(shell pwd)/..:/mnt --entrypoint /bin/bash $(FULL_IMAGE)

# Check if Docker is available
.PHONY: check-docker
check-docker:
	@command -v docker >/dev/null 2>&1 || { echo "Error: Docker is not installed"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "Error: Docker daemon is not running"; exit 1; }

# Ensure dependencies before other targets
build test build-test push clean run shell: check-docker

# Show image info
.PHONY: info
info:
	@echo "Docker Image Information"
	@echo "========================"
	@echo "Image Name: $(IMAGE_NAME)"
	@echo "Image Tag:  $(IMAGE_TAG)"
	@echo "Full Image: $(FULL_IMAGE)"
	@echo ""
	@echo "Local Images:"
	@docker images $(IMAGE_NAME) 2>/dev/null || echo "No local images found"
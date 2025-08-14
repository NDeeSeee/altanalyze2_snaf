##############################################################################
# AltAnalyze Splicing Analysis Docker Image
##############################################################################
# Multi-stage build for optimized container size and security
# Base: Ubuntu 22.04 LTS for stability and long-term support
# Includes: Python, AltAnalyze, GNU Parallel, and analysis scripts
##############################################################################

# Build stage: Download and setup AltAnalyze dependencies
FROM ubuntu:22.04 AS builder

# Set non-interactive frontend to avoid tzdata prompts
ARG DEBIAN_FRONTEND=noninteractive

# Install build and runtime dependencies
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    wget \
    unzip \
    git \
    ca-certificates \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /usr/src/app

# Download and setup AltAnalyze
RUN wget --progress=dot:giga https://github.com/nsalomonis/altanalyze/archive/refs/heads/master.zip \
    && unzip master.zip \
    && mv altanalyze-master altanalyze \
    && rm master.zip

# Install Python dependencies for AltAnalyze
RUN pip3 install --no-cache-dir \
    numpy \
    scipy \
    matplotlib \
    pandas \
    networkx \
    scikit-learn

##############################################################################
# Runtime stage: Minimal image with runtime dependencies
##############################################################################
FROM ubuntu:22.04 AS runtime

# Metadata labels following OCI specification
LABEL org.opencontainers.image.title="AltAnalyze Splicing Analysis" \
      org.opencontainers.image.description="Containerized AltAnalyze for alternative splicing analysis from RNA-seq data" \
      org.opencontainers.image.version="2.1.4" \
      org.opencontainers.image.authors="Valerii Pavlov <valerii.pavlov@fccc.com>" \
      org.opencontainers.image.url="https://hub.docker.com/r/frankligy123/altanalyze" \
      org.opencontainers.image.source="https://github.com/NDeeSeee/altanalyze2_snaf" \
      org.opencontainers.image.documentation="http://altanalyze.readthedocs.io/" \
      org.opencontainers.image.vendor="Cincinnati Children's Hospital Medical Center - Salomonis Lab" \
      org.opencontainers.image.licenses="Apache-2.0"

# Set non-interactive frontend
ARG DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    bash \
    parallel \
    gzip \
    tar \
    coreutils \
    sed \
    grep \
    findutils \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Python runtime dependencies
RUN pip3 install --no-cache-dir \
    numpy \
    scipy \
    matplotlib \
    pandas \
    networkx \
    scikit-learn

# Copy AltAnalyze from builder stage
COPY --from=builder /usr/src/app/altanalyze /usr/src/app/altanalyze

# Create application directories
WORKDIR /usr/src/app

# Copy analysis scripts
COPY AltAnalyze.sh /usr/src/app/AltAnalyze.sh
COPY prune.py /usr/src/app/prune.py

# Make scripts executable
RUN chmod +x /usr/src/app/AltAnalyze.sh

# Create non-root user for security
RUN groupadd -r altanalyze && useradd -r -g altanalyze altanalyze

# Create working directories with proper permissions
RUN mkdir -p /mnt/bam /mnt/altanalyze_output /data/input /data/output \
    && chown -R altanalyze:altanalyze /mnt /data /usr/src/app

# Set working directory
WORKDIR /mnt

# Switch to non-root user
USER altanalyze

# Health check to verify Python and AltAnalyze installation
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 -c "import sys; print(sys.version)" && \
        ls /usr/src/app/altanalyze/AltAnalyze.py || exit 1

# Default entrypoint
ENTRYPOINT ["/usr/src/app/AltAnalyze.sh"]

# Default command shows usage
CMD ["--help"]

##############################################################################
# Usage:
# Pull:  docker pull frankligy123/altanalyze:latest
# Build: docker build -t frankligy123/altanalyze:latest .
# Run:   docker run -v /path/to/data:/mnt frankligy123/altanalyze:latest \
#          bam_to_bed bam/sample.bam
##############################################################################
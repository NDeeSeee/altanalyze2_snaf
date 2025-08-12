##############################################################################
# STAR 2-Pass RNA-seq Alignment Docker Image
##############################################################################
# Multi-stage build for optimized container size and security
# Base: Ubuntu 22.04 LTS for stability and long-term support
# STAR version: 2.4.0h (matches original script requirements)
##############################################################################

# Build stage: Compile STAR from source for optimal performance
FROM ubuntu:22.04 AS builder

# Set non-interactive frontend to avoid tzdata prompts
ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    zlib1g-dev \
    libncurses5-dev \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download and compile STAR 2.4.0h
WORKDIR /tmp
RUN wget https://github.com/alexdobin/STAR/archive/2.4.0h.tar.gz \
    && tar -xzf 2.4.0h.tar.gz \
    && cd STAR-2.4.0h/source \
    && make STAR

##############################################################################
# Runtime stage: Minimal image with only runtime dependencies
##############################################################################
FROM ubuntu:22.04 AS runtime

# Metadata labels following OCI specification
LABEL org.opencontainers.image.title="STAR 2-Pass RNA-seq Aligner" \
      org.opencontainers.image.description="Containerized STAR 2.4.0h for 2-pass RNA-seq alignment" \
      org.opencontainers.image.version="2.4.0h" \
      org.opencontainers.image.authors="Bioinformatics Team" \
      org.opencontainers.image.source="https://github.com/alexdobin/STAR"

# Set non-interactive frontend
ARG DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    zlib1g \
    libncurses5 \
    bash \
    gzip \
    coreutils \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy STAR binary from builder stage
COPY --from=builder /tmp/STAR-2.4.0h/bin/Linux_x86_64_static/STAR /usr/local/bin/

# Create non-root user for security
RUN groupadd -r staruser && useradd -r -g staruser staruser

# Create working directories with proper permissions
RUN mkdir -p /data/input /data/output /data/reference /data/work \
    && chown -R staruser:staruser /data

# Copy and setup alignment script
COPY star_2.4_container.sh /usr/local/bin/star_align.sh
RUN chmod +x /usr/local/bin/star_align.sh

# Set working directory
WORKDIR /data/work

# Switch to non-root user
USER staruser

# Health check to verify STAR installation
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD STAR --version || exit 1

# Default entrypoint
ENTRYPOINT ["/usr/local/bin/star_align.sh"]

# Default command shows usage
CMD ["--help"]

##############################################################################
# Usage:
# Build: docker build -t star-aligner:2.4.0h .
# Run:   docker run -v /path/to/data:/data star-aligner:2.4.0h \
#          /data/input/sample.1.fastq.gz \
#          /data/reference/genome_dir \
#          /data/reference/genome.fa \
#          /data/output
##############################################################################
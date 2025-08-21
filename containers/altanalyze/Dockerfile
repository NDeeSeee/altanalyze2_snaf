##############################################################################
# AltAnalyze Splicing Analysis Derivative Image
##############################################################################
# Fast rebuilds: derive from prebuilt upstream image and only override scripts
# Cross-platform: buildx can target linux/amd64 and linux/arm64
##############################################################################

FROM frankligy123/altanalyze:0.7.0.1

LABEL org.opencontainers.image.title="AltAnalyze Splicing Analysis (derived)" \
      org.opencontainers.image.source="https://github.com/NDeeSeee/altanalyze2_snaf" \
      org.opencontainers.image.description="Derived image that overrides AltAnalyze.sh for faster iteration" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /usr/src/app

# Install runtime tooling needed by workflow steps
USER root
# Debian buster is EOL — switch to archive repos and disable Valid-Until checks
RUN sed -i -e 's|deb.debian.org/debian|archive.debian.org/debian|g' \
           -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       samtools \
       parallel \
       procps \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*
## Override scripts (fast layer)
# Ensure we have privileges to place/mark executable then drop back to user 1000
USER root
COPY --chown=1000:1000 ./AltAnalyze.sh /usr/src/app/AltAnalyze.sh
RUN chmod +x /usr/src/app/AltAnalyze.sh
# Bundle resource monitor for portability across platforms (optional at runtime)
COPY ./monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /usr/local/bin/monitor.sh || true
# Default to root to allow Cromwell/Terra wrappers to create /cromwell_root symlink
USER root

# Keep default entrypoint and CMD from base image
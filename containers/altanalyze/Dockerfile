##############################################################################
# AltAnalyze Splicing Analysis Derivative Image
##############################################################################
# Fast rebuilds: derive from prebuilt upstream image and only override scripts
# Cross-platform: buildx can target linux/amd64 and linux/arm64
##############################################################################

FROM frankligy123/altanalyze:0.7.0.1

LABEL org.opencontainers.image.title="AltAnalyze Splicing Analysis (derived)" \
      org.opencontainers.image.source="https://github.com/NDeeSeee/altanalyze2_snaf" \
      org.opencontainers.image.description="Derived image that overrides AltAnalyze.sh and prune.py for faster iteration" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /usr/src/app

# Override scripts (fast layer)
COPY AltAnalyze.sh /usr/src/app/AltAnalyze.sh
COPY prune.py /usr/src/app/prune.py
RUN chmod +x /usr/src/app/AltAnalyze.sh

# Keep default entrypoint and CMD from base image
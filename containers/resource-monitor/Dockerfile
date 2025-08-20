# Minimal image for Terra resource monitoring
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    python3 \
    python3-distutils \
    python3-psutil \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY monitor.sh /usr/local/bin/monitor.sh
COPY monitor.py /usr/local/bin/monitor.py
RUN chmod +x /usr/local/bin/monitor.sh && chmod +x /usr/local/bin/monitor.py || true

# Terra will run your provided Image script and Script; entrypoint/cmd are placeholders
ENTRYPOINT ["/bin/bash","-lc"]
CMD ["true"]

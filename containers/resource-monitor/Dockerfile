# Minimal image for Terra resource monitoring
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
 && rm -rf /var/lib/apt/lists/*

COPY monitor.sh /usr/local/bin/monitor.sh
RUN chmod +x /usr/local/bin/monitor.sh

# Terra will run your provided Image script and Script; entrypoint/cmd are placeholders
ENTRYPOINT ["/bin/bash","-lc"]
CMD ["true"]

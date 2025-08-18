#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == "" || ${2:-} == "" ]]; then
  echo "Usage: $0 <repo/name> <tag>" >&2
  echo "Example: $0 ndeeseee/resource-monitor 0.1.0" >&2
  exit 1
fi
IMAGE="$1:$2"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building $IMAGE" >&2
docker build -t "$IMAGE" "$DIR"

echo "Pushing $IMAGE" >&2
docker push "$IMAGE"

echo "Done: $IMAGE" >&2

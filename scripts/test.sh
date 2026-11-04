#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
engine=${CONTAINER_ENGINE:-podman}
mkdir -p results
"$engine" run --rm -v "$PWD:/work:z" registry.fedoraproject.org/fedora:44 \
  bash /work/tests/container-smoke.sh

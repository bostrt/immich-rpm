#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
engine=${CONTAINER_ENGINE:-podman}
fedora=${FEDORA_VERSION:-44}
if [[ $# != 1 || ! -f $1 || $1 != *.rpm ]]; then
  echo "Usage: $0 path/to/immich-machine-learning.rpm" >&2
  exit 2
fi
mkdir -p "$repo/.work" "$repo/results"
rpm_dir=$(mktemp -d "$repo/.work/test-ml-rpms.XXXXXX")
cp --reflink=auto "$1" "$rpm_dir/package.rpm"
"$engine" run --rm -v "$repo:/work:z" -v "$rpm_dir:/rpms:ro,z" \
  -e "IMMICH_TEST_MODELS=${IMMICH_TEST_MODELS:-0}" \
  "registry.fedoraproject.org/fedora:$fedora" \
  bash /work/tests/container-ml-smoke.sh

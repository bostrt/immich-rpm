#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
engine=${CONTAINER_ENGINE:-podman}
image=${BUILDER_IMAGE:-localhost/immich-rpm-builder:fc44}
ml_image=${ML_BUILDER_IMAGE:-localhost/immich-rpm-ml-builder:fc44}
with_ml=true
if [[ ${1:-} == --server-only ]]; then with_ml=false; shift; fi
if [[ $# -gt 0 ]]; then echo "Usage: $0 [--server-only]" >&2; exit 2; fi
mkdir -p sources results .work
"$engine" build -t "$image" -f Containerfile .
userns=()
if [[ $engine == *podman ]]; then userns=(--userns=keep-id); fi
"$engine" run --rm "${userns[@]}" --user "$(id -u):$(id -g)" \
  -v "$PWD:/work:z" -e HOME=/work/.work/home "$image" \
  bash scripts/container-build.sh
if $with_ml; then
  "$engine" build --build-arg "BASE_IMAGE=$image" -t "$ml_image" -f Containerfile.ml .
  "$engine" run --rm "${userns[@]}" --user "$(id -u):$(id -g)" \
    -v "$PWD:/work:z" -e HOME=/work/.work/home "$ml_image" \
    bash scripts/container-build-ml.sh
fi

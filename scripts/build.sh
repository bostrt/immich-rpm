#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
engine=${CONTAINER_ENGINE:-podman}
fedora=${FEDORA_VERSION:-44}
image=${BUILDER_IMAGE:-localhost/immich-rpm-builder:fc$fedora}
ml_image=${ML_BUILDER_IMAGE:-localhost/immich-rpm-ml-builder:fc$fedora}
mode=--binary
with_ml=auto
with_server=true
for arg in "$@"; do
  case "$arg" in
    --srpm-only) mode=--srpm-only ;;
    --server-only) with_ml=false; with_server=true ;;
    --with-ml) with_ml=true; with_server=true ;;
    --ml-only) with_ml=true; with_server=false ;;
    *) echo "Usage: $0 [--srpm-only] [--server-only|--with-ml|--ml-only]" >&2; exit 2 ;;
  esac
done
# Source preparation for COPR defaults to the server; ML needs a media review.
if [[ $with_ml == auto ]]; then
  with_ml=true
  [[ $mode == --srpm-only ]] && with_ml=false
fi
mkdir -p sources results .work
userns=()
if [[ $engine == *podman ]]; then userns=(--userns=keep-id); fi
if $with_server; then
  "$engine" build --build-arg "FEDORA_VERSION=$fedora" -t "$image" -f Containerfile .
  "$engine" run --rm "${userns[@]}" --user "$(id -u):$(id -g)" \
    -v "$PWD:/work:z" -e HOME=/work/.work/home "$image" \
    bash scripts/container-build.sh "$mode"
fi
if $with_ml; then
  "$engine" build --build-arg "FEDORA_VERSION=$fedora" -t "$ml_image" -f Containerfile.ml .
  "$engine" run --rm "${userns[@]}" --user "$(id -u):$(id -g)" \
    -v "$PWD:/work:z" -e HOME=/work/.work/home "$ml_image" \
    bash scripts/container-build-ml.sh "$mode"
fi

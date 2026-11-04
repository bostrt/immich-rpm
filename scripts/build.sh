#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
engine=${CONTAINER_ENGINE:-podman}
image=${BUILDER_IMAGE:-localhost/immich-rpm-builder:fc44}
ml_image=${ML_BUILDER_IMAGE:-localhost/immich-rpm-ml-builder:fc44}
mode=--binary
with_ml=auto
for arg in "$@"; do
  case "$arg" in
    --srpm-only) mode=--srpm-only ;;
    --server-only) with_ml=false ;;
    --with-ml) with_ml=true ;;
    *) echo "Usage: $0 [--srpm-only] [--server-only|--with-ml]" >&2; exit 2 ;;
  esac
done
# Source preparation for COPR defaults to the server; ML needs a media review.
if [[ $with_ml == auto ]]; then
  with_ml=true
  [[ $mode == --srpm-only ]] && with_ml=false
fi
mkdir -p sources results .work
"$engine" build -t "$image" -f Containerfile .
userns=()
if [[ $engine == *podman ]]; then userns=(--userns=keep-id); fi
"$engine" run --rm "${userns[@]}" --user "$(id -u):$(id -g)" \
  -v "$PWD:/work:z" -e HOME=/work/.work/home "$image" \
  bash scripts/container-build.sh "$mode"
if $with_ml; then
  "$engine" build --build-arg "BASE_IMAGE=$image" -t "$ml_image" -f Containerfile.ml .
  "$engine" run --rm "${userns[@]}" --user "$(id -u):$(id -g)" \
    -v "$PWD:/work:z" -e HOME=/work/.work/home "$ml_image" \
    bash scripts/container-build-ml.sh "$mode"
fi

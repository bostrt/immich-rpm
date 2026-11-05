#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/build-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/build-common.sh"
init_package immich-machine-learning.spec
export UV_CACHE_DIR="$repo/.work/uv-cache-system-opencv"
export UV_PYTHON_DOWNLOADS=never
cache="sources/immich-$version-system-opencv-uv-cache.tar.gz"
inputs=$(sha256sum "sources/immich-$version.tar.gz" scripts/container-build-ml.sh; uv --version; python3 --version; rpm -q python3-opencv python3-numpy)
if [[ ! -f $cache || ! -f $cache.inputs ]] || [[ $(cat "$cache.inputs") != "$inputs" ]]; then
  mkdir -p .work/ml-system-opencv-fetch
  tar -xzf "sources/immich-$version.tar.gz" -C .work/ml-system-opencv-fetch
  export UV_PROJECT_ENVIRONMENT="$repo/.work/ml-system-opencv-fetch/venv"
  uv venv --allow-existing --python /usr/bin/python3 --system-site-packages "$UV_PROJECT_ENVIRONMENT"
  uv sync --project ".work/ml-system-opencv-fetch/immich-$version/machine-learning" \
    --python /usr/bin/python3 --frozen --extra cpu --no-dev --no-install-project --link-mode copy \
    --no-install-package opencv-python-headless --no-install-package opencv-python \
    --no-install-package numpy
  tar -czf "$cache.part" -C .work uv-cache-system-opencv
  mv "$cache.part" "$cache"
  printf '%s\n' "$inputs" > "$cache.inputs"
  unset UV_PROJECT_ENVIRONMENT
fi
cp "sources/immich-$version.tar.gz" "$cache" "$top/SOURCES/"
build_package
sha256sum "sources/immich-$version.tar.gz" "$cache" > results/immich-machine-learning-SOURCES.sha256

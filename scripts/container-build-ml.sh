#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/build-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/build-common.sh"
init_package immich-machine-learning.spec
export UV_CACHE_DIR="$repo/.work/uv-cache"
export UV_PYTHON_DOWNLOADS=never
cache="sources/immich-$version-uv-cache.tar.gz"
inputs=$(sha256sum "sources/immich-$version.tar.gz"; uv --version; python3.13 --version)
if [[ ! -f $cache || ! -f $cache.inputs ]] || [[ $(cat "$cache.inputs") != "$inputs" ]]; then
  mkdir -p .work/ml-fetch
  tar -xzf "sources/immich-$version.tar.gz" -C .work/ml-fetch
  uv sync --project ".work/ml-fetch/immich-$version/machine-learning" \
    --python /usr/bin/python3.13 --frozen --extra cpu --no-dev --no-install-project --link-mode copy
  tar -czf "$cache.part" -C .work uv-cache
  mv "$cache.part" "$cache"
  printf '%s\n' "$inputs" > "$cache.inputs"
fi
cp "sources/immich-$version.tar.gz" "$cache" "$top/SOURCES/"
build_package
sha256sum "sources/immich-$version.tar.gz" "$cache" > results/immich-machine-learning-SOURCES.sha256

#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/build-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/build-common.sh"
init_package immich-machine-learning.spec
target=$(rpm -E '%{?dist}.%{_arch}')
top="$repo/.work/${spec%.spec}-top$target"
mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SRPMS,SOURCES,SPECS}
work="$repo/.work/ml$target"
export UV_CACHE_DIR="$work/uv-cache-system-opencv"
export UV_PYTHON_DOWNLOADS=never
cache="sources/immich-$version-system-opencv-uv-cache$target.tar.gz"
system_packages=()
system_rpms=(python3-opencv python3-numpy)
if (( $(rpm -E '%{fedora}') >= 45 )); then
  system_packages+=(--no-install-package onnxruntime)
  system_rpms+=(python3-onnxruntime)
fi
inputs=$(sha256sum "sources/immich-$version.tar.gz" scripts/container-build-ml.sh "$spec"; uv --version; python3 --version; rpm -q "${system_rpms[@]}")
if [[ ! -f $cache || ! -f $cache.inputs ]] || [[ $(cat "$cache.inputs") != "$inputs" ]]; then
  mkdir -p "$work/fetch"
  tar -xzf "sources/immich-$version.tar.gz" -C "$work/fetch"
  export UV_PROJECT_ENVIRONMENT="$work/fetch/venv"
  uv venv --allow-existing --python /usr/bin/python3 --system-site-packages "$UV_PROJECT_ENVIRONMENT"
  uv sync --project "$work/fetch/immich-$version/machine-learning" \
    --python /usr/bin/python3 --frozen --extra cpu --no-dev --no-install-project --link-mode copy \
    --no-install-package opencv-python-headless --no-install-package opencv-python \
    --no-install-package numpy "${system_packages[@]}"
  tar -czf "$cache.part" -C "$work" uv-cache-system-opencv
  mv "$cache.part" "$cache"
  printf '%s\n' "$inputs" > "$cache.inputs"
  unset UV_PROJECT_ENVIRONMENT
fi
cp "sources/immich-$version.tar.gz" "$cache" "$top/SOURCES/"
build_package
sha256sum "sources/immich-$version.tar.gz" "$cache" > results/immich-machine-learning-SOURCES.sha256

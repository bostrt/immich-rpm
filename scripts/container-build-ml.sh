#!/usr/bin/env bash
set -euo pipefail
cd /work
version=3.3.5
export UV_CACHE_DIR=/work/.work/uv-cache
export UV_PYTHON_DOWNLOADS=never
mkdir -p "$HOME" .work/ml-top/{BUILD,BUILDROOT,RPMS,SRPMS,SOURCES,SPECS} results
(cd sources && sha256sum -c SHA256SUMS)
if [[ ! -f sources/immich-$version-uv-cache.tar.gz ]]; then
  mkdir -p .work/ml-fetch
  tar -xzf "sources/immich-$version.tar.gz" -C .work/ml-fetch
  uv sync --project ".work/ml-fetch/immich-$version/machine-learning" \
    --python /usr/bin/python3.13 --frozen --extra cpu --no-dev --no-install-project --link-mode copy
  tar -czf "sources/immich-$version-uv-cache.tar.gz" -C .work uv-cache
fi
cp "sources/immich-$version.tar.gz" "sources/immich-$version-uv-cache.tar.gz" .work/ml-top/SOURCES/
find packaging -maxdepth 1 -type f -exec cp -t .work/ml-top/SOURCES/ {} +
cp immich-machine-learning.spec .work/ml-top/SPECS/
rpmbuild -ba --define '_topdir /work/.work/ml-top' .work/ml-top/SPECS/immich-machine-learning.spec
cp .work/ml-top/RPMS/*/*.rpm .work/ml-top/SRPMS/*.rpm results/
sha256sum results/*.rpm > results/SHA256SUMS

#!/usr/bin/env bash
set -euo pipefail
cd /work
version=3.3.5
mkdir -p "$HOME" .work/top/{BUILD,BUILDROOT,RPMS,SRPMS,SOURCES,SPECS} .work/tools results
if [[ ! -f sources/immich-$version.tar.gz ]]; then
  curl -fL --retry 3 "https://github.com/immich-app/immich/archive/refs/tags/v$version.tar.gz" -o "sources/immich-$version.tar.gz"
fi
(cd sources && sha256sum -c SHA256SUMS)
if [[ ! -f sources/extism-js-x86_64-linux-v1.7.0.gz ]]; then
  curl -fL --retry 3 https://github.com/extism/js-pdk/releases/download/v1.7.0/extism-js-x86_64-linux-v1.7.0.gz -o sources/extism-js-x86_64-linux-v1.7.0.gz
fi
echo '63b72da2f5e88655522dc21477de549f238a2f40546a69ce4e0fce7e78654035  sources/extism-js-x86_64-linux-v1.7.0.gz' | sha256sum -c -
gzip -dc sources/extism-js-x86_64-linux-v1.7.0.gz > .work/tools/extism-js
chmod 755 .work/tools/extism-js
export PATH="/work/.work/tools:$PATH"
if [[ ! -f sources/immich-geodata.tar.gz ]]; then
  mkdir -p .work/geodata
  for name in cities500.zip admin1CodesASCII.txt admin2Codes.txt countryInfo.txt; do
    curl -fL --retry 3 "https://download.geonames.org/export/dump/$name" -o ".work/geodata/$name"
  done
  curl -fL --retry 3 https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson -o .work/geodata/ne_10m_admin_0_countries.geojson
  unzip -o .work/geodata/cities500.zip -d .work/geodata
  date -u +%FT%TZ > .work/geodata/geodata-date.txt
  tar --exclude='*.zip' -czf sources/immich-geodata.tar.gz -C .work geodata
fi
if [[ ! -f sources/immich-$version-fedora-pnpm-store.tar.gz ]]; then
  mkdir -p .work/fetch-fedora
  tar -xzf "sources/immich-$version.tar.gz" -C .work/fetch-fedora
  (
    cd ".work/fetch-fedora/immich-$version"
    patch -p1 < /work/patches/0001-sharp-use-fedora-libvips.patch
    pnpm --store-dir /work/.work/pnpm-store --filter 'immich...' --filter 'immich-web...' --filter '@immich/plugin-core...' fetch --frozen-lockfile
  )
  tar -czf "sources/immich-$version-fedora-pnpm-store.tar.gz" -C .work pnpm-store
fi
find packaging -maxdepth 1 -type f -exec cp -t .work/top/SOURCES/ {} +
cp patches/*.patch .work/top/SOURCES/
cp README.md .work/top/SOURCES/
cp sources/*.tar.gz .work/top/SOURCES/
cp sources/extism-js-x86_64-linux-v1.7.0.gz .work/top/SOURCES/
cp immich.spec .work/top/SPECS/
rpmbuild -ba --define '_topdir /work/.work/top' --define '_smp_mflags -j2' .work/top/SPECS/immich.spec
cp .work/top/RPMS/*/*.rpm .work/top/SRPMS/*.rpm results/
sha256sum results/*.rpm > results/SHA256SUMS
sha256sum sources/*.tar.gz sources/extism-js-x86_64-linux-v1.7.0.gz > results/SOURCES.sha256
rpm -qp --requires results/immich-$version-*.x86_64.rpm > results/requires.txt

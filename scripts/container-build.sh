#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/build-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/build-common.sh"
init_package immich.spec

pnpm_archive=$(rpmspec -P "$spec" | awk '/^Source12:/ { sub(/.*\//, "", $2); print $2 }')
download_verified "$pnpm_archive" "https://registry.npmjs.org/pnpm/-/$pnpm_archive"
mkdir -p .work/tools/pnpm-package
tar -xzf "sources/$pnpm_archive" -C .work/tools/pnpm-package --strip-components=1
chmod 755 .work/tools/pnpm-package/bin/pnpm.mjs
ln -sfn pnpm-package/bin/pnpm.mjs .work/tools/pnpm
export PATH="$repo/.work/tools:$PATH"
download_verified extism-js-x86_64-linux-v1.7.0.gz \
  https://github.com/extism/js-pdk/releases/download/v1.7.0/extism-js-x86_64-linux-v1.7.0.gz

if [[ ! -f sources/immich-geodata.tar.gz ]]; then
  mkdir -p .work/geodata
  for name in cities500.zip admin1CodesASCII.txt admin2Codes.txt countryInfo.txt; do
    curl -fL --retry 3 "https://download.geonames.org/export/dump/$name" -o ".work/geodata/$name"
  done
  curl -fL --retry 3 https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson -o .work/geodata/ne_10m_admin_0_countries.geojson
  unzip -o .work/geodata/cities500.zip -d .work/geodata
  date -u +%FT%TZ > .work/geodata/geodata-date.txt
  tar --exclude='*.zip' -czf sources/immich-geodata.tar.gz.part -C .work geodata
  mv sources/immich-geodata.tar.gz{.part,}
fi

# Changing the lockfile patch or package manager invalidates the fetch archive.
cache="sources/immich-$version-fedora-pnpm-store.tar.gz"
inputs=$(sha256sum "sources/immich-$version.tar.gz" "sources/$pnpm_archive" patches/0001-sharp-use-fedora-libvips.patch)
if [[ ! -f $cache || ! -f $cache.inputs ]] || [[ $(cat "$cache.inputs") != "$inputs" ]]; then
  mkdir -p .work/fetch-fedora
  tar -xzf "sources/immich-$version.tar.gz" -C .work/fetch-fedora
  (
    cd ".work/fetch-fedora/immich-$version"
    patch -p1 < "$repo/patches/0001-sharp-use-fedora-libvips.patch"
    pnpm --store-dir "$repo/.work/pnpm-store" --filter 'immich...' --filter 'immich-web...' --filter '@immich/plugin-core...' fetch --frozen-lockfile
  )
  tar -czf "$cache.part" -C .work pnpm-store
  mv "$cache.part" "$cache"
  printf '%s\n' "$inputs" > "$cache.inputs"
fi
cp patches/*.patch README.md "sources/immich-$version.tar.gz" "$cache" \
  sources/immich-geodata.tar.gz sources/extism-js-x86_64-linux-v1.7.0.gz \
  "sources/$pnpm_archive" "$top/SOURCES/"
build_package
sha256sum "sources/immich-$version.tar.gz" "$cache" sources/immich-geodata.tar.gz \
  sources/extism-js-x86_64-linux-v1.7.0.gz "sources/$pnpm_archive" > results/immich-SOURCES.sha256

#!/usr/bin/env bash
# Shared by the scripts that run INSIDE the build containers.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo=$PWD
mode=${1:---binary}
case "$mode" in
  --binary|--srpm-only) ;;
  *) echo "Expected --binary or --srpm-only" >&2; exit 2 ;;
esac
mkdir -p "$HOME" sources results/SRPMS .work

download_verified() {
  local name=$1 url=$2 checksum
  checksum=$(awk -v name="$name" '$2 == name { print; found=1 } END { if (!found) exit 1 }' sources/SHA256SUMS)
  if [[ ! -f sources/$name ]]; then
    curl -fL --retry 3 "$url" -o "sources/$name.part"
    (cd sources && printf '%s\n' "${checksum/  $name/  $name.part}" | sha256sum -c -)
    mv "sources/$name.part" "sources/$name"
  fi
  (cd sources && printf '%s\n' "$checksum" | sha256sum -c -)
}

init_package() {
  spec=$1
  version=$(rpmspec -q --srpm --qf '%{VERSION}' "$spec")
  nvr=$(rpmspec -q --srpm --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$spec")
  top="$repo/.work/${spec%.spec}-top"
  mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SRPMS,SOURCES,SPECS}
  download_verified "immich-$version.tar.gz" "https://github.com/immich-app/immich/archive/refs/tags/v$version.tar.gz"
}

build_package() {
  cp "$spec" "$top/SPECS/"
  find packaging -maxdepth 1 -type f -exec cp -t "$top/SOURCES/" {} +
  local action=-ba
  [[ $mode == --srpm-only ]] && action=-bs
  rpmbuild "$action" --define "_topdir $top" --define '_smp_mflags -j2' "$top/SPECS/$spec"
  # Copy only this invocation's version/release, never every historical RPM.
  cp "$top/SRPMS/$nvr.src.rpm" results/SRPMS/
  if [[ $mode == --binary ]]; then
    cp "$top/RPMS/x86_64/$nvr.x86_64.rpm" results/
    rpm -qp --requires "results/$nvr.x86_64.rpm" > "results/${spec%.spec}-requires.txt"
  fi
  (cd results/SRPMS && sha256sum ./*.src.rpm > SHA256SUMS)
  if compgen -G 'results/*.x86_64.rpm' > /dev/null; then
    (cd results && sha256sum ./*.x86_64.rpm > SHA256SUMS)
  fi
  echo "Source RPM: results/SRPMS/$nvr.src.rpm"
}

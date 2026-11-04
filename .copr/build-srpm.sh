#!/usr/bin/env bash
# Invoked by COPR inside Mock, or by the containerized preparation test.
set -euo pipefail
outdir=$(realpath -m "${1:?COPR must provide an output directory}")
requested_spec=${2:-immich.spec}
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ $(realpath "$requested_spec") != "$PWD/immich.spec" ]]; then
  echo 'This COPR source target builds immich.spec only.' >&2
  exit 2
fi
if [[ $EUID != 0 ]]; then
  echo 'Run this target inside the COPR source-build chroot or a container.' >&2
  exit 2
fi

# Only source-preparation tools are needed here; the binary build installs its
# own BuildRequires in a separate chroot with networking disabled.
dnf -y --setopt=install_weak_deps=False install \
  rpm-build redhat-rpm-config systemd-rpm-macros \
  nodejs24 nodejs24-npm nodejs24-full-i18n \
  curl git patch tar gzip unzip findutils

release_tag=$(rpmspec --define 'dist %{nil}' -q --srpm \
  --qf '%{NAME}-%{VERSION}-%{RELEASE}' immich.spec)
if tag=$(git describe --tags --exact-match HEAD 2>/dev/null); then
  if [[ $tag != "$release_tag" ]]; then
    echo "Tag $tag does not match spec version/release $release_tag." >&2
    exit 1
  fi
fi

export CI=1 NODE_OPTIONS=--max-old-space-size=3072
bash scripts/container-build.sh --srpm-only
nvr=$(rpmspec -q --srpm --qf '%{NAME}-%{VERSION}-%{RELEASE}' immich.spec)
mkdir -p "$outdir"
cp "results/SRPMS/$nvr.src.rpm" "$outdir/"

#!/usr/bin/env bash
# Runs in the Fedora ML builder container after preparing its source RPM.
set -euo pipefail
[[ -f /run/.containerenv || -f /.dockerenv ]] || { echo 'Container required' >&2; exit 1; }
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash .copr/check-ml-tag.sh "${RELEASE_TAG:?Release tag is required}"
fedora=$(rpm -E '%{fedora}')
[[ $fedora == "${FEDORA_VERSION:?Fedora release is required}" ]]
case "$fedora" in 44|45) ;; *) echo "Unsupported Fedora release: $fedora" >&2; exit 1 ;; esac
nvr=$(rpmspec -q --srpm --qf '%{NAME}-%{VERSION}-%{RELEASE}' immich-machine-learning.spec)
srpm="results/SRPMS/$nvr.src.rpm"
[[ -s $srpm ]]
[[ -n ${COPR_CONFIG:-} ]] || { echo 'COPR_CONFIG secret is missing' >&2; exit 1; }
dnf -y --setopt=install_weak_deps=False install copr-cli
umask 077
copr_config=$(mktemp)
trap 'rm -f "$copr_config"' EXIT
printf '%s\n' "$COPR_CONFIG" > "$copr_config"
unset COPR_CONFIG
copr-cli --config "$copr_config" build bostrt/immich "$srpm" \
  --chroot "fedora-$fedora-x86_64" --enable-net off

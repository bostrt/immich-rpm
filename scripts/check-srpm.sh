#!/usr/bin/env bash
# Rebuild the actual SRPM using only Fedora build tooling and its BuildRequires.
set -euo pipefail
if [[ $# != 1 || $1 != *.src.rpm || ! -f $1 ]]; then
  echo "Usage: $0 path/to/package.src.rpm" >&2
  exit 2
fi
srpm=$(realpath "$1")
cd "$(dirname "${BASH_SOURCE[0]}")/.."
engine=${CONTAINER_ENGINE:-podman}
fedora=${FEDORA_VERSION:-44}
mkdir -p .work results
context=$(mktemp -d "$PWD/.work/check-srpm.XXXXXX")
cp --reflink=auto "$srpm" "$context/package.src.rpm"
image="localhost/immich-rpm-check:$(basename "$srpm" .src.rpm)-fc$fedora"
"$engine" build --build-arg "FEDORA_VERSION=$fedora" -t "$image" -f Containerfile.check "$context"
userns=()
if [[ $engine == *podman ]]; then userns=(--userns=keep-id); fi
# Expand the following shell variables inside the container.
# shellcheck disable=SC2016
"$engine" run --rm --network=none "${userns[@]}" --user "$(id -u):$(id -g)" \
  -v "$context:/build:z" -v "$PWD/results:/output:z" -e HOME=/build/home "$image" \
  bash -euo pipefail -c '
    mkdir -p "$HOME" /build/top
    nvr=$(rpm -qp --qf "%{NAME}-%{VERSION}-%{RELEASE}" /tmp/package.src.rpm)
    rpmbuild --rebuild /tmp/package.src.rpm --define "_topdir /build/top" \
      --define "_smp_mflags -j2" --define "_smp_build_ncpus 2" 2>&1 | tee "/output/$nvr-rebuild.log"
    cp "/build/top/RPMS/x86_64/$nvr.x86_64.rpm" /output/
    cd /output
    sha256sum ./*.x86_64.rpm > SHA256SUMS
  '
echo "Rebuild succeeded with networking disabled; RPM and log are in results/."

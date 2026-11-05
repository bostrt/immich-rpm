#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
engine=${CONTAINER_ENGINE:-podman}
fedora=${FEDORA_VERSION:-44}
with_ml=1
if [[ ${1:-} == --server-only ]]; then with_ml=0; shift; fi
if [[ $# == 0 ]]; then
  shopt -s nullglob
  server=("$repo"/results/immich-[0-9]*.x86_64.rpm)
  ml=("$repo"/results/immich-machine-learning-[0-9]*.x86_64.rpm)
  if [[ ${#server[@]} != 1 ]] || { [[ $with_ml == 1 ]] && [[ ${#ml[@]} != 1 ]]; }; then
    echo "Specify exact RPM paths when results/ contains multiple releases or is incomplete." >&2
    echo "Usage: $0 [--server-only] [server.rpm [machine-learning.rpm]]" >&2
    exit 2
  fi
  set -- "${server[@]}"
  [[ $with_ml == 0 ]] || set -- "$@" "${ml[@]}"
fi
mkdir -p "$repo/.work" "$repo/results"
rpm_dir=$(mktemp -d "$repo/.work/test-rpms.XXXXXX")
for rpm_path in "$@"; do
  [[ -f $rpm_path && $rpm_path == *.rpm ]] || { echo "Not an RPM file: $rpm_path" >&2; exit 2; }
  cp --reflink=auto "$rpm_path" "$rpm_dir/"
done
"$engine" run --rm -v "$repo:/work:z" -v "$rpm_dir:/rpms:ro,z" \
  -e "IMMICH_TEST_ML=$with_ml" -e "IMMICH_TEST_FFMPEG=${IMMICH_TEST_FFMPEG:-fedora}" \
  "registry.fedoraproject.org/fedora:$fedora" \
  bash /work/tests/container-smoke.sh

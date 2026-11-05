#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# These spec fields are literals, apart from the Fedora dist suffix.
expected=$(awk '
  $1 == "Name:" { name=$2 }
  $1 == "Version:" { version=$2 }
  $1 == "Release:" { release=$2; sub(/%.*/, "", release) }
  END { print name "-" version "-" release }
' immich-machine-learning.spec)
if [[ ${1:-} != "$expected" ]]; then
  echo "ML release tag must match the spec: $expected" >&2
  exit 1
fi
echo "Validated ML release tag: $expected"

#!/usr/bin/env bash
# Maintainer helper: regenerate the minimal Fedora Sharp compatibility patch.
# Run in the builder container, from /work.
set -euo pipefail
mkdir -p .work/pin-sharp patches
tar -xzf sources/immich-3.3.5.tar.gz -C .work/pin-sharp
cd .work/pin-sharp/immich-3.3.5
cp pnpm-workspace.yaml pnpm-workspace.yaml.orig
cp pnpm-lock.yaml pnpm-lock.yaml.orig
sed -i 's/sharp: \^0.35.3/sharp: 0.35.3/' pnpm-workspace.yaml
pnpm install --lockfile-only --ignore-scripts --no-frozen-lockfile
{
  diff -u --label a/pnpm-workspace.yaml --label b/pnpm-workspace.yaml pnpm-workspace.yaml.orig pnpm-workspace.yaml || test "$?" -eq 1
  diff -u --label a/pnpm-lock.yaml --label b/pnpm-lock.yaml pnpm-lock.yaml.orig pnpm-lock.yaml || test "$?" -eq 1
} > /work/patches/0001-sharp-use-fedora-libvips.patch

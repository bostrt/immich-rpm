#!/usr/bin/env bash
set -euo pipefail
# Runs only in a disposable Fedora container; never invoke on the host.
[[ -f /run/.containerenv || -f /.dockerenv ]] || { echo 'Container required' >&2; exit 1; }
dnf_options=(--setopt=install_weak_deps=False)
if [[ ${IMMICH_TEST_OFFLINE:-0} == 1 ]]; then dnf_options+=(--disablerepo='*'); fi
ffmpeg_provider=${IMMICH_TEST_FFMPEG:-fedora}
case "$ffmpeg_provider" in
  fedora) ffmpeg_package=ffmpeg-free ;;
  rpmfusion)
    [[ ${IMMICH_TEST_OFFLINE:-0} != 1 ]] || { echo 'RPM Fusion setup requires network access' >&2; exit 2; }
    ffmpeg_package=ffmpeg
    fedora_release=$(rpm -E '%{fedora}')
    dnf -y "${dnf_options[@]}" install \
      "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$fedora_release.noarch.rpm"
    # Reproduce installation on a host which already has RPM Fusion FFmpeg.
    dnf -y "${dnf_options[@]}" install ffmpeg
    ffmpeg_before=$(rpm -q ffmpeg)
    ;;
  *) echo 'IMMICH_TEST_FFMPEG must be fedora or rpmfusion' >&2; exit 2 ;;
esac
dnf -y "${dnf_options[@]}" install /rpms/*.rpm python3 curl procps-ng
[[ $(rpm -qf --qf '%{NAME}' /usr/bin/ffmpeg) == "$ffmpeg_package" ]]
[[ $(rpm -qf --qf '%{NAME}' /usr/bin/ffprobe) == "$ffmpeg_package" ]]
if [[ $ffmpeg_provider == rpmfusion ]]; then
  [[ $(rpm -q ffmpeg) == "$ffmpeg_before" ]]
fi
ffmpeg -version
ffprobe -version
echo "PASS: FFmpeg commands provided by $ffmpeg_package"
with_ml=${IMMICH_TEST_ML:-1}
rpm -q immich
if [[ $with_ml == 1 ]]; then rpm -q immich-machine-learning; fi
mkdir -p /run/postgresql /var/lib/pgsql/data /var/cache/immich-machine-learning
chown postgres:postgres /run/postgresql /var/lib/pgsql/data
runuser -u postgres -- initdb -D /var/lib/pgsql/data --auth-local=peer --auth-host=scram-sha-256
runuser -u postgres -- pg_ctl -D /var/lib/pgsql/data -l /var/lib/pgsql/server.log \
  -o '-c listen_addresses=127.0.0.1 -c unix_socket_directories=/run/postgresql' -w start
immich-setup
# Check that explicitly rerunning database setup is safe.
immich-setup
valkey-server --bind 127.0.0.1 --port 6379 --daemonize yes
systemd-analyze verify /usr/lib/systemd/system/immich.service
if [[ $with_ml == 1 ]]; then
  systemd-analyze verify /usr/lib/systemd/system/immich-machine-learning.service
  chown immich-ml:immich-ml /var/cache/immich-machine-learning
  runuser -u immich-ml -- bash -c '
    set -a
    source /etc/immich/machine-learning.conf
    set +a
    export PATH=/usr/libexec/immich-machine-learning/venv/bin:/usr/bin
    export PYTHONDONTWRITEBYTECODE=1
    cd /usr/libexec/immich-machine-learning
    exec python -m immich_ml
  ' > /tmp/immich-ml.log 2>&1 &
fi
runuser -u immich -- bash -c '
  set -a
  source /etc/immich/immich.conf
  set +a
  export NODE_ENV=production
  cd /usr/libexec/immich/server
  exec node dist/main.js
' > /tmp/immich-server.log 2>&1 &
cleanup() {
  cp /tmp/immich-server.log /work/results/smoke-server.log
  if [[ $with_ml == 1 ]]; then cp /tmp/immich-ml.log /work/results/smoke-ml.log; fi
}
trap cleanup EXIT
python3 /work/tests/smoke.py
# Verify actual linkage to Fedora libvips, not an npm binary distribution.
find /usr/libexec/immich/server -name '*.node' -exec ldd {} \; > /work/results/native-linkage.txt
if grep -q 'not found' /work/results/native-linkage.txt; then
  cat /work/results/native-linkage.txt
  exit 1
fi
grep 'libvips-cpp.so' /work/results/native-linkage.txt
rpm -V immich
if [[ $with_ml == 1 ]]; then rpm -V immich-machine-learning; fi
summary='PASS: Fedora RPM installation, database setup, web/API, upload, thumbnail and metadata'
if [[ $with_ml == 1 ]]; then summary+=', ML health and ONNX CPU inference'; fi
echo "$summary" | tee /work/results/smoke-result.txt

#!/usr/bin/env bash
set -euo pipefail
[[ -f /run/.containerenv || -f /.dockerenv ]] || { echo 'Container required' >&2; exit 1; }
fedora=$(rpm -E '%{fedora}')
output="/work/results/ml-fc$fedora"
mkdir -p "$output"
exec > >(tee "$output/smoke.log") 2>&1
dnf -y --setopt=install_weak_deps=False install /rpms/package.rpm curl util-linux findutils
rpm -q immich-machine-learning python3 python3-opencv python3-numpy
rpm -V immich-machine-learning
systemd-analyze verify /usr/lib/systemd/system/immich-machine-learning.service
find /usr/libexec/immich-machine-learning/venv -type f -name '*.so*' -exec ldd {} \; > "$output/native-linkage.txt"
if grep -q 'not found' "$output/native-linkage.txt"; then
  cat "$output/native-linkage.txt"
  exit 1
fi
echo 'PASS: RPM integrity, systemd unit syntax and private native library linkage'
cd /usr/libexec/immich-machine-learning
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH=$PWD
install -d -o immich-ml -g immich-ml /tmp/ml-results
runuser -u immich-ml -- venv/bin/python /work/tests/ml_image_processing.py /tmp/ml-results
cp /tmp/ml-results/* "$output/"
runuser -u immich-ml -- bash -c '
  set -a
  source /etc/immich/machine-learning.conf
  set +a
  export PATH=/usr/libexec/immich-machine-learning/venv/bin:/usr/bin
  exec python -m immich_ml
' > /tmp/immich-ml.log 2>&1 &
ml_pid=$!
cleanup() {
  kill "$ml_pid" 2>/dev/null || true
  cp /tmp/immich-ml.log "$output/service.log"
}
trap cleanup EXIT
ready=0
for attempt in {1..60}; do
  if [[ $(curl -fsS http://127.0.0.1:3003/ping 2>/dev/null || true) == pong ]]; then
    ready=1
    break
  fi
  if ! kill -0 "$ml_pid" 2>/dev/null; then cat /tmp/immich-ml.log; exit 1; fi
  sleep 1
done
[[ $ready == 1 ]] || { cat /tmp/immich-ml.log; exit 1; }
echo 'PASS: service runs as immich-ml and responds pong'
runuser -u immich-ml -- bash -c '
  set -a
  source /etc/immich/machine-learning.conf
  set +a
  exec venv/bin/python /work/tests/ml_smoke.py
'
rpm -V immich-machine-learning
echo "PASS: Fedora $fedora ML RPM installation, image processing, service and inference" > "$output/result.txt"
cat "$output/result.txt"

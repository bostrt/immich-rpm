"""End-to-end test against the RPMs in a disposable container."""
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

BASE = "http://127.0.0.1:2283"


def request(path, data=None, token=None, content_type="application/json", method=None):
    headers = {}
    if data is not None:
        if isinstance(data, dict):
            data = json.dumps(data).encode()
        headers["Content-Type"] = content_type
    if token:
        headers["Authorization"] = f"Bearer {token}"
    url = path if path.startswith("http") else BASE + path
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers, method=method), timeout=30) as r:
        body = r.read()
        return json.loads(body) if "json" in r.headers.get("Content-Type", "") else body


def wait_for(label, callback, seconds=180):
    deadline = time.monotonic() + seconds
    last = None
    while time.monotonic() < deadline:
        try:
            value = callback()
            if value:
                print(f"PASS: {label}", flush=True)
                return value
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            last = error
        time.sleep(2)
    raise RuntimeError(f"Timed out waiting for {label}: {last}")


wait_for("server startup and PostgreSQL migrations", lambda: request("/api/server/ping"))
assert b"<html" in request("/").lower()
print("PASS: web UI", flush=True)
expected_version = subprocess.check_output(["rpm", "-q", "--qf", "%{VERSION}", "immich"], text=True).split(".")
actual_version = request("/api/server/version")
assert [actual_version[key] for key in ("major", "minor", "patch")] == list(map(int, expected_version))
if os.environ.get("IMMICH_TEST_ML", "1") == "1":
    wait_for("CPU ML service", lambda: request("http://127.0.0.1:3003/ping") == b"pong")
    subprocess.run([
        "runuser", "-u", "immich-ml", "--",
        "/usr/libexec/immich-machine-learning/venv/bin/python", "-c",
        "import onnx, onnxruntime as ort, numpy as np; "
        "h = onnx.helper; t = onnx.TensorProto.FLOAT; "
        "g = h.make_graph([h.make_node('Add', ['x', 'x'], ['y'])], 'rpm-smoke', "
        "[h.make_tensor_value_info('x', t, [2])], [h.make_tensor_value_info('y', t, [2])]); "
        "m = h.make_model(g, opset_imports=[h.make_opsetid('', 17)], ir_version=9); "
        "s = ort.InferenceSession(m.SerializeToString(), providers=['CPUExecutionProvider']); "
        "assert np.array_equal(s.run(None, {'x': np.array([1, 2], dtype=np.float32)})[0], [2, 4])",
    ], check=True)
    print("PASS: ONNX CPU inference", flush=True)
wait_for("background workers and core plugin", lambda: "Loaded plugin:" in Path("/tmp/immich-server.log").read_text())

password = str(uuid.uuid4()) + "aA1!"
request("/api/auth/admin-sign-up", {"email": "smoke@example.test", "password": password, "name": "RPM smoke test"})
token = request("/api/auth/login", {"email": "smoke@example.test", "password": password})["accessToken"]
print("PASS: administrator registration and login", flush=True)
# Test photo processing without downloading large external model weights.
# The separate ML checks above exercise its HTTP service and CPU runtime.
config = request("/api/system-config", token=token)
config["machineLearning"]["enabled"] = False
request("/api/system-config", config, token, method="PUT")

subprocess.run(["magick", "-size", "128x128", "xc:red", "/tmp/fixture.jpg"], check=True)
boundary = "rpm-smoke-" + uuid.uuid4().hex
parts = []
for key, value in {"deviceAssetId": "rpm-smoke", "deviceId": "rpm-test", "fileCreatedAt": "2026-11-03T00:00:00Z", "fileModifiedAt": "2026-11-03T00:00:00Z"}.items():
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="assetData"; filename="fixture.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'.encode())
with open("/tmp/fixture.jpg", "rb") as fixture:
    parts.append(fixture.read())
parts.append(f"\r\n--{boundary}--\r\n".encode())
asset = request("/api/assets", b"".join(parts), token, f"multipart/form-data; boundary={boundary}")
asset_id = asset["id"]
print(f"PASS: photo upload ({asset_id})", flush=True)
wait_for("thumbnail generation using Fedora libvips", lambda: request(f"/api/assets/{asset_id}/thumbnail", token=token))
detail = wait_for("ExifTool metadata extraction", lambda: request(f"/api/assets/{asset_id}", token=token).get("exifInfo"))
assert detail["exifImageWidth"] == 128
assert detail["exifImageHeight"] == 128
print("PASS: metadata dimensions", flush=True)

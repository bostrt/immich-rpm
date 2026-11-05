"""Check the installed ML runtime; optionally download and exercise real models."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys

import cv2
import httpx
import immich_ml
import numpy as np
import onnx
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

fedora = int(subprocess.check_output(["rpm", "-E", "%{fedora}"], text=True))
assert os.environ["ORT_DISABLE_TELEMETRY"] == "1"
for module in (cv2, np):
    assert not Path(module.__file__).resolve().is_relative_to(Path(sys.prefix)), module.__file__
assert Path(onnx.__file__).resolve().is_relative_to(Path(sys.prefix)), onnx.__file__
assert tuple(map(int, onnx.__version__.split(".")[:2])) >= (1, 22)
assert Path(ort.__file__).resolve().is_relative_to(Path(sys.prefix)) == (fedora < 45), ort.__file__
print("ONNX Runtime:", ort.__version__, ort.__file__, flush=True)
print("ONNX:", onnx.__version__, onnx.__file__, flush=True)
h = onnx.helper
t = onnx.TensorProto.FLOAT
graph = h.make_graph([h.make_node("Add", ["x", "x"], ["y"])], "rpm-smoke",
    [h.make_tensor_value_info("x", t, [2])], [h.make_tensor_value_info("y", t, [2])])
model = h.make_model(graph, opset_imports=[h.make_opsetid("", 17)], ir_version=9)
session = ort.InferenceSession(model.SerializeToString(), providers=["CPUExecutionProvider"])
np.testing.assert_array_equal(session.run(None, {"x": np.array([1, 2], dtype=np.float32)})[0], [2, 4])
print("PASS: package origins, telemetry disabled and ONNX CPU inference", flush=True)

if os.environ.get("IMMICH_TEST_MODELS", "0") == "1":
    def embedding(value):
        vector = np.asarray(json.loads(value), dtype=np.float32)
        assert vector.size == 512 and np.isfinite(vector).all()
        assert np.linalg.norm(vector) > 0
        return vector

    def predict(entries, *, image=None, text=None):
        data = {"entries": json.dumps(entries)}
        files = None
        if image is not None:
            buffer = io.BytesIO()
            image.save(buffer, format="PNG")
            files = {"image": ("fixture.png", buffer.getvalue(), "image/png")}
        if text is not None:
            data["text"] = text
        response = httpx.post("http://127.0.0.1:3003/predict", data=data, files=files, timeout=600)
        response.raise_for_status()
        return response.json()

    clip = {"modelName": "ViT-B-32__openai"}
    embedding(predict({"clip": {"textual": clip}}, text="a red photograph")["clip"])
    picture = Image.new("RGB", (256, 256), (200, 20, 20))
    embedding(predict({"clip": {"visual": clip}}, image=picture)["clip"])
    print("PASS: real CLIP text and image model inference through HTTP", flush=True)

    face = {"modelName": "buffalo_l"}
    result = predict({"facial-recognition": {"detection": face, "recognition": face}}, image=picture)
    assert result["facial-recognition"] == []
    # A blank image exercises detection, but has no faces. Supply synthetic
    # landmarks separately to exercise the real recognition network as well.
    from immich_ml.models.facial_recognition._ops import ARCFACE_DST
    from immich_ml.models.facial_recognition.recognition import FaceRecognizer
    from immich_ml.schemas import FaceRecognitionOptions
    faces = {"boxes": np.array([[0, 0, 112, 112]], dtype=np.float32),
             "landmarks": ARCFACE_DST[np.newaxis].copy(), "scores": np.array([1.0], dtype=np.float32)}
    recognized = FaceRecognizer("buffalo_l").predict(picture, faces, options=FaceRecognitionOptions())
    assert len(recognized) == 1
    embedding(recognized[0]["embedding"])
    print("PASS: real face detection and recognition models with synthetic inputs", flush=True)

    picture = Image.new("RGB", (640, 160), "white")
    ImageDraw.Draw(picture).text((20, 40), "HELLO IMMICH", fill="black", font=ImageFont.load_default(size=48))
    ocr = {"modelName": "PP-OCRv5_mobile"}
    result = predict({"ocr": {"detection": ocr, "recognition": ocr}}, image=picture)
    assert "HELLO" in json.dumps(result["ocr"]).upper(), result
    print("PASS: real OCR detection and recognition through HTTP", flush=True)

"""Exercise Immich 3.3.6 helpers with Fedora's OpenCV/NumPy Python packages."""
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys

import cv2
import numpy as np
from PIL import Image

from immich_ml.models.transforms import letterbox, widen
from immich_ml.models.facial_recognition._ops import ALIGNED_SIZE, ARCFACE_DST, align_face, nms
from immich_ml.models.ocr.postprocess import DBPostProcess

out = Path(sys.argv[1])
results = []


def passed(name):
    results.append(name)
    print(f'PASS: {name}', flush=True)


print('Python:', sys.version, flush=True)
print('OpenCV:', cv2.__version__, cv2.__file__, flush=True)
print('NumPy:', np.__version__, np.__file__, flush=True)
assert cv2.__file__.startswith('/usr/')
assert np.__file__.startswith('/usr/')
passed('OpenCV and NumPy loaded from Fedora system packages')
files = subprocess.check_output(['rpm', '-ql', 'python3-opencv'], text=True).splitlines()
extensions = [path for path in files if '/cv2/' in path and path.endswith('.so')]
assert len(extensions) == 1, extensions
extension = extensions[0]
owner = subprocess.check_output(['rpm', '-qf', extension], text=True).strip()
print('Extension:', extension, flush=True)
print('RPM owner:', owner, flush=True)
linkage = subprocess.check_output(['ldd', extension], text=True)
(out / 'native-linkage.txt').write_text(linkage)
(out / 'opencv-build.txt').write_text(cv2.getBuildInformation())
assert 'not found' not in linkage
assert 'opencv_python_headless.libs' not in linkage
assert '/usr/libexec/immich' not in linkage
assert 'libopencv_core.so' in linkage
assert 'libavcodec.so' in linkage
passed('Native extension links to system OpenCV and FFmpeg without missing libraries')

# An image with known contents checks both the resized region and its padding.
image = np.full((16, 24, 3), (30, 120, 210), dtype=np.uint8)
boxed, scale = letterbox(image, 32)
assert boxed.shape == (32, 32, 3)
assert boxed.dtype == np.uint8
np.testing.assert_array_equal(boxed[:21], np.broadcast_to(image[0, 0], (21, 32, 3)))
assert not boxed[21:].any()
assert scale == 21 / 16
boxed_pil, scale_pil = letterbox(Image.fromarray(image), 32)
np.testing.assert_array_equal(boxed, boxed_pil)
assert scale == scale_pil
passed('Immich letterbox resizing into a destination array, with correct padding')

# Exercise the narrow non-contiguous destination view used for tall images.
portrait = np.full((24, 16, 3), (30, 120, 210), dtype=np.uint8)
boxed_portrait, _ = letterbox(portrait, 32)
np.testing.assert_array_equal(boxed_portrait[:, :21], np.broadcast_to(portrait[0, 0], (32, 21, 3)))
assert not boxed_portrait[:, 21:].any()
passed('Immich resize into a non-contiguous NumPy destination slice')

half = np.array([[0, 1, -2], [0.5, 65504, -0.125]], dtype=np.float16)
wide = widen(half)
assert wide.dtype == np.float32
np.testing.assert_array_equal(wide, half.astype(np.float32))
passed('Immich half-precision conversion through cv2.convertFp16')

boxes = np.array([[0, 0, 10, 10], [1, 1, 11, 11], [30, 30, 40, 40]], dtype=np.float32)
scores = np.array([0.9, 0.8, 0.7], dtype=np.float32)
np.testing.assert_array_equal(nms(boxes, scores), [0, 2])
passed('Immich face overlap suppression through cv2.dnn.NMSBoxes')

# Canonical landmarks yield an identity face alignment: output must equal input.
face = np.random.default_rng(7).integers(0, 256, (ALIGNED_SIZE, ALIGNED_SIZE, 3), dtype=np.uint8)
crop = np.empty_like(face)
align_face(face, ARCFACE_DST.copy(), crop)
np.testing.assert_array_equal(crop, face)
passed('Immich face alignment through cv2.warpAffine')

probs = np.zeros((64, 96), dtype=np.float32)
probs[16:40, 20:70] = 0.95
for dilation in (False, True):
    processor = DBPostProcess(use_dilation=dilation)
    for score_mode in ('fast', 'slow'):
        detected, confidence = processor(probs, (64, 96), 0.7, score_mode)
        assert detected.shape == (1, 4, 2), (dilation, score_mode, detected)
        assert confidence.shape == (1,) and 0.7 < confidence[0] <= 1.0
        assert np.isfinite(detected).all()
        assert (detected >= 0).all()
        assert (detected[..., 0] < 96).all() and (detected[..., 1] < 64).all()
    empty_boxes, empty_scores = processor(np.zeros_like(probs), (64, 96), 0.7)
    assert empty_boxes.shape == (0, 4, 2) and empty_scores.shape == (0,)
passed('Immich OCR postprocessing: dilation, contours, rectangles, polygon masks and confidence scores')

metadata = {}
for name in ('opencv', 'opencv-python', 'opencv-python-headless'):
    try:
        metadata[name] = importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        metadata[name] = None
print('Python package metadata:', json.dumps(metadata), flush=True)
summary = {
    'python': sys.version.split()[0],
    'opencv': cv2.__version__,
    'numpy': np.__version__,
    'extension': extension,
    'rpm_owner': owner,
    'metadata': metadata,
    'passed': results,
    'scope': 'Immich image-processing helpers; no model inference or full-service startup',
}
(out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(f'PASS: {len(results)} checks', flush=True)

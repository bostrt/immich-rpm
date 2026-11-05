%global debug_package %{nil}
# Dependencies are private to this application, not system Python providers.
%global __provides_exclude_from ^%{_libexecdir}/immich-machine-learning/.*$
%global __requires_exclude_from ^%{_libexecdir}/immich-machine-learning/.*$
# Wheel executables are launched with python -m; preserve the wheel contents.
%undefine __brp_mangle_shebangs
%undefine __brp_python_bytecompile
%undefine __brp_check_rpaths
%global _build_id_links none

Name:           immich-machine-learning
Version:        3.3.6
Release:        3%{?dist}
Summary:        Optional native CPU machine learning service for Immich
License:        AGPL-3.0-only AND MIT AND Apache-2.0 AND BSD-3-Clause
URL:            https://immich.app
Source0:        https://github.com/immich-app/immich/archive/refs/tags/v%{version}.tar.gz#/immich-%{version}.tar.gz
Source1:        immich-%{version}-system-opencv-uv-cache%{?dist}.%{_arch}.tar.gz
Source2:        immich-machine-learning.service
Source3:        machine-learning.conf
Source4:        immich-machine-learning.sysusers
ExclusiveArch:  x86_64
BuildRequires:  python3-devel uv systemd-rpm-macros
BuildRequires:  python3-opencv >= 4.13
BuildRequires:  python3-opencv < 5
BuildRequires:  python3-numpy >= 1:2.4
BuildRequires:  python3-numpy < 1:3
%if 0%{?fedora} >= 45
BuildRequires:  python3-onnxruntime >= 1.23.2
BuildRequires:  python3-onnxruntime < 2
Requires:       python3-onnxruntime >= 1.23.2
Requires:       python3-onnxruntime < 2
%endif
# The import check loads native wheels even in a minimal buildroot.
BuildRequires:  libstdc++ libgcc libgomp zlib geos tar gzip findutils
Requires:       python(abi) = %{python3_version}
Requires:       python3-opencv >= 4.13
Requires:       python3-opencv < 5
Requires:       python3-numpy >= 1:2.4
Requires:       python3-numpy < 1:3
Requires:       glibc libstdc++ libgcc libgomp zlib geos
Requires:       systemd
Requires(pre):  systemd
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

%description
Optional CPU service for Immich smart search, face recognition and OCR.
Uses Fedora's default Python, OpenCV and NumPy packages. Other Python
dependencies are installed in a private environment from Immich's pinned
uv.lock. Fedora 45 uses the system ONNX Runtime; Fedora 44 bundles it.
The ONNX Python library remains bundled. Model weights are downloaded on
demand to the service cache.

%prep
%setup -q -n immich-%{version}
tar -xzf %{SOURCE1}

%build
# Materialize from the source RPM's cache without network access.
export UV_CACHE_DIR="$PWD/uv-cache-system-opencv"
export UV_PYTHON_DOWNLOADS=never
export UV_PROJECT_ENVIRONMENT="$PWD/ml-venv"
# OpenCV's Fedora bindings match the default Python ABI. Use Fedora's NumPy
# with them; installing upstream's wheel would shadow these system packages.
uv venv --python /usr/bin/python3 --system-site-packages "$UV_PROJECT_ENVIRONMENT"
system_packages=""
%if 0%{?fedora} >= 45
system_packages="--no-install-package onnxruntime"
%endif
uv sync --project machine-learning --python /usr/bin/python3 --offline \
  --frozen --extra cpu --no-dev --no-install-project --link-mode copy \
  --no-install-package opencv-python-headless --no-install-package opencv-python \
  --no-install-package numpy $system_packages

%install
install -d %{buildroot}%{_libexecdir}/immich-machine-learning
cp -a ml-venv %{buildroot}%{_libexecdir}/immich-machine-learning/venv
cp -a machine-learning/immich_ml %{buildroot}%{_libexecdir}/immich-machine-learning/
# Console entrypoints contain temporary build paths. All services use python -m.
find %{buildroot}%{_libexecdir}/immich-machine-learning/venv/bin -type f -delete
find %{buildroot}%{_libexecdir}/immich-machine-learning -name __pycache__ -type d -prune -exec rm -rf {} +
install -Dpm 644 %{SOURCE2} %{buildroot}%{_unitdir}/immich-machine-learning.service
install -Dpm 640 %{SOURCE3} %{buildroot}%{_sysconfdir}/immich/machine-learning.conf
install -Dpm 644 %{SOURCE4} %{buildroot}%{_sysusersdir}/immich-machine-learning.conf
install -d %{buildroot}%{_localstatedir}/cache/immich-machine-learning

%check
PYTHONPATH=machine-learning ml-venv/bin/python - <<'PY'
from pathlib import Path
import sys
import cv2
import numpy
import onnxruntime as ort
import immich_ml.main

assert "CPUExecutionProvider" in ort.get_available_providers()
system_modules = [cv2, numpy]
%if 0%{?fedora} >= 45
system_modules.append(ort)
%endif
for module in system_modules:
    path = Path(module.__file__).resolve()
    assert not path.is_relative_to(Path(sys.prefix)), path
    assert str(path).startswith("/usr/lib"), path
    print(module.__name__, module.__version__, path)
print("ONNX Runtime", ort.__version__)
PY

%pre
%sysusers_create_compat %{SOURCE4}

%post
%systemd_post immich-machine-learning.service

%preun
%systemd_preun immich-machine-learning.service

%postun
%systemd_postun_with_restart immich-machine-learning.service

%files
%license LICENSE
%{_libexecdir}/immich-machine-learning/
%{_unitdir}/immich-machine-learning.service
%{_sysusersdir}/immich-machine-learning.conf
%dir %{_sysconfdir}/immich
%config(noreplace) %attr(0640,root,immich-ml) %{_sysconfdir}/immich/machine-learning.conf
%attr(0750,immich-ml,immich-ml) %dir %{_localstatedir}/cache/immich-machine-learning

%changelog
* Thu Nov 05 2026 Immich RPM contributors - 3.3.6-3
- Use Fedora's ONNX Runtime on Fedora 45 with Python 3.15
- Keep ML dependency caches separate by Fedora release and architecture

* Thu Nov 05 2026 Immich RPM contributors - 3.3.6-2
- Use Fedora's default Python, OpenCV and NumPy in the ML service
- Exclude OpenCV and NumPy wheels from the private runtime environment
- Exclude the OpenCV wheel and its media libraries from the source cache

* Wed Nov 04 2026 Immich RPM contributors - 3.3.6-1
- Update to Immich 3.3.6, disabling ONNX Runtime telemetry by default

* Wed Nov 04 2026 Immich RPM contributors - 3.3.5-2
- Declare native libraries needed by the build-time import check

* Tue Nov 03 2026 Immich RPM contributors - 3.3.5-1
- Optional CPU machine learning service with Fedora Python

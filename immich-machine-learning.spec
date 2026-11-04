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
Version:        3.3.5
Release:        2%{?dist}
Summary:        Optional native CPU machine learning service for Immich
License:        AGPL-3.0-only AND MIT AND Apache-2.0 AND BSD-3-Clause
URL:            https://immich.app
Source0:        https://github.com/immich-app/immich/archive/refs/tags/v%{version}.tar.gz#/immich-%{version}.tar.gz
Source1:        immich-%{version}-uv-cache.tar.gz
Source2:        immich-machine-learning.service
Source3:        machine-learning.conf
Source4:        immich-machine-learning.sysusers
ExclusiveArch:  x86_64
BuildRequires:  python3.13 uv systemd-rpm-macros
# The import check loads native wheels even in a minimal buildroot.
BuildRequires:  libstdc++ libgcc libgomp zlib tar gzip findutils
Requires:       python3.13 glibc libstdc++ libgcc libgomp zlib
Requires:       systemd
Requires(pre):  systemd
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

%description
Optional CPU service for Immich smart search, face recognition and OCR.
Uses Fedora's Python 3.13 interpreter with a private environment populated
from Immich's pinned uv.lock. The ONNX stack is newer than Fedora's packaged
versions. Model weights are downloaded on demand to the service cache.

%prep
%setup -q -n immich-%{version}
tar -xzf %{SOURCE1}

%build
# Materialize from the source RPM's cache without network access.
export UV_CACHE_DIR="$PWD/uv-cache"
export UV_PYTHON_DOWNLOADS=never
export UV_PROJECT_ENVIRONMENT="$PWD/ml-venv"
uv sync --project machine-learning --python /usr/bin/python3.13 --offline \
  --frozen --extra cpu --no-dev --no-install-project --link-mode copy

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
PYTHONPATH=machine-learning ml-venv/bin/python -c 'import immich_ml.main; import onnxruntime as ort; assert "CPUExecutionProvider" in ort.get_available_providers(); print(ort.__version__)'

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
* Wed Nov 04 2026 Immich RPM contributors - 3.3.5-2
- Declare native libraries needed by the build-time import check

* Tue Nov 03 2026 Immich RPM contributors - 3.3.5-1
- Optional CPU machine learning service with Fedora Python

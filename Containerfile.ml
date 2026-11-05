ARG FEDORA_VERSION=44
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION}
RUN dnf -y upgrade --refresh && \
    dnf -y --setopt=install_weak_deps=False install \
      rpm-build rpmdevtools redhat-rpm-config systemd-rpm-macros \
      gcc-c++ make python3-devel python3-opencv python3-numpy geos-devel cargo uv \
      libstdc++ libgcc libgomp zlib tar gzip findutils curl git \
      systemd util-linux shadow-utils diffutils file && \
    if [ "$(rpm -E '%{fedora}')" -ge 45 ]; then \
      dnf -y --setopt=install_weak_deps=False install python3-onnxruntime; \
    fi && dnf clean all
WORKDIR /work

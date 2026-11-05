ARG BASE_IMAGE=localhost/immich-rpm-builder:fc44
FROM ${BASE_IMAGE}
RUN dnf -y --setopt=install_weak_deps=False install \
      python3-devel python3-opencv python3-numpy geos-devel cargo uv && dnf clean all

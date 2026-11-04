ARG BASE_IMAGE=localhost/immich-rpm-builder:fc44
FROM ${BASE_IMAGE}
RUN dnf -y --setopt=install_weak_deps=False install python3.13 uv && dnf clean all

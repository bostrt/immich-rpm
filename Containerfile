FROM registry.fedoraproject.org/fedora:44
RUN dnf -y upgrade --refresh && \
    dnf -y install rpm-build rpmdevtools redhat-rpm-config systemd-rpm-macros \
      gcc-c++ make python3 python3-pip nodejs24 nodejs24-npm nodejs24-devel \
      vips-devel perl-Image-ExifTool ImageMagick ffmpeg-free \
      postgresql-server postgresql-contrib pgvector valkey \
      curl tar gzip xz unzip findutils diffutils patch git file which \
      systemd util-linux procps-ng shadow-utils && \
    dnf clean all
RUN npm install --global pnpm@11.27.1
ENV CI=1 NODE_OPTIONS=--max-old-space-size=3072
WORKDIR /work
RUN dnf -y --setopt=install_weak_deps=False install binaryen && dnf clean all

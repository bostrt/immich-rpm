# Immich RPMs for Fedora

Native **Immich 3.3.5** packages for **Fedora 44 x86_64**. Containers are used
only to build and test the RPMs. Installed services run directly under systemd;
Podman and Docker are not runtime dependencies.

- `immich`: server, web UI, core workflow plugin, and reverse-geocoding data.
- `immich-machine-learning`: optional CPU service for smart search, faces, and OCR.

## Build without installing build tools on the host

With rootless Podman already available:

```bash
./scripts/build.sh
```

Use `./scripts/build.sh --server-only` to omit ML. RPMs and source RPMs are written
to `results/`, downloads to `sources/`, and temporary build files to `.work/`.
The first build needs network access for Fedora packages, upstream sources, and
locked npm/Python dependencies. Subsequent RPM builds reuse those caches.
Budget approximately 15 GB of free disk space and 6 GB of available memory.

All `dnf`, Node.js, Python dependency installation, compilers, and `rpmbuild`
commands run inside Fedora containers. The host only needs the container engine,
Bash, and standard file utilities. `CONTAINER_ENGINE=docker` selects Docker for
the build instead. The shared `:z` mount label permits concurrent build containers
on SELinux systems.

`immich.spec` builds TypeScript, the Svelte web UI, and the core WASM plugin from
source. It compiles Sharp and bcrypt against Fedora headers. The source RPMs
include the dependency caches and geodata snapshot needed to reproduce their
payloads with the builder images. The builder uses pinned pnpm 11.27.1 and the
upstream-pinned Extism compiler 1.7.0; the latter is a build-only binary, checked
against its upstream SHA-256.

## Install and initialize

These commands install runtime packages on the machine that will host Immich.
Building the RPMs does not run them on your host.

```bash
sudo dnf install ./results/immich-3.3.5-1.fc44.x86_64.rpm
# Optional:
sudo dnf install ./results/immich-machine-learning-3.3.5-1.fc44.x86_64.rpm
```

For a **new** PostgreSQL installation, initialize its cluster once:

```bash
sudo postgresql-setup --initdb
```

Skip initialization if PostgreSQL already has a cluster. Then:

```bash
sudo systemctl enable --now postgresql.service valkey.service
sudo immich-setup
sudo systemctl enable --now immich-machine-learning.service  # if installed
sudo systemctl enable --now immich.service
```

Open `http://localhost:2283`. The first registered user is the administrator.
If remote access is wanted, open port 2283 in the host firewall or configure a
reverse proxy. The ML service listens only on `127.0.0.1:3003`.

`immich-setup` creates a non-superuser `immich` database role, an `immich` database,
and the required extensions. It uses the local PostgreSQL admin account and is
safe to rerun. It does not initialize a cluster, rewrite `pg_hba.conf`, set a
database password, or start services. The default application connection uses
the Unix socket at `/run/postgresql` with peer authentication as the `immich`
system user. Existing PostgreSQL configurations must allow that local connection.

If omitting ML, disable machine learning in Administration → Settings, or set an
external ML URL there. The default for new installations is `http://127.0.0.1:3003`.

## Files and maintenance

| Purpose | Location |
| --- | --- |
| Server configuration | `/etc/immich/immich.conf` |
| ML configuration | `/etc/immich/machine-learning.conf` |
| Photos, videos, generated media | `/var/lib/immich/media` |
| Writable plugin storage | `/var/lib/immich/plugins` |
| Downloaded ML models | `/var/cache/immich-machine-learning` |
| Server code and private Node modules | `/usr/libexec/immich/server` |
| Static UI, core plugin, geodata | `/usr/share/immich` |
| Private Python ML environment | `/usr/libexec/immich-machine-learning` |

Configuration files use systemd `EnvironmentFile` syntax and are preserved on
RPM upgrades. Services run as separate unprivileged `immich` and `immich-ml`
accounts. Inspect logs with `journalctl -u immich -u immich-machine-learning`.

Run an administrator command with the service's configuration and identity:

```bash
sudo systemd-run --wait --pty --collect --uid=immich --gid=immich \
  --property=EnvironmentFile=/etc/immich/immich.conf \
  --working-directory=/usr/libexec/immich/server \
  /usr/bin/node /usr/libexec/immich/server/dist/main.js immich-admin --help
```

For a custom media path, change `IMMICH_MEDIA_LOCATION`, create the destination
owned by `immich`, and add a matching `ReadWritePaths=` entry using
`sudo systemctl edit immich`. `ProtectHome=yes` prevents using home directories;
use a dedicated location such as `/srv/immich`. External library paths also need
appropriate filesystem permissions and service sandbox access.

Back up the PostgreSQL database and media before upgrades. Immich runs database
migrations at startup; downgrading an RPM does not reverse those migrations.
Removing the package does not delete an existing database or uploaded photos.
The ML service downloads model weights when first needed and requires outbound
HTTPS access for that first use.

## Dependency choices and limits

| Component | Packaging |
| --- | --- |
| Node.js | Fedora `nodejs24` |
| Database | Fedora `postgresql-server`, `postgresql-contrib`, `pgvector` |
| Queue/cache | Fedora `valkey` |
| Image processing | Fedora `vips`, `ImageMagick` |
| Metadata | Fedora `perl-Image-ExifTool` |
| Video | Fedora `ffmpeg-free` |
| Python interpreter | Fedora `python3.13` |
| Application JavaScript | Private modules from the upstream lockfile, with the Sharp pin below |
| Python ML stack | Private CPU environment from upstream `uv.lock` |

Immich 3.3.5 supports `DB_VECTOR_EXTENSION=pgvector`, avoiding a separate
VectorChord build. This selects pgvector indexes; it does not use VectorChord's
indexing implementation. Never point these defaults at an existing VectorChord
database without following upstream migration guidance.

The checked-in compatibility patch pins Sharp to **0.35.3**, within Immich's
declared `^0.35.3` range. That version supports Fedora's libvips **8.18.3**;
upstream's locked Sharp 0.35.5 requires libvips 8.18.7. The vendored ExifTool
executable and prebuilt bcrypt binaries are removed from the runtime package.

Fedora's ML packages are too old for this Immich release (notably ONNX and ONNX
Runtime), and the pinned `immich-model` library requires Python below 3.14.
The optional RPM therefore uses Fedora Python 3.13 with upstream's pinned wheels,
including CPU ONNX Runtime 1.30.0. It does not replace the system Python packages
and does not install CUDA, ROCm, or OpenVINO runtimes.

Fedora's media packages differ from Immich's custom upstream media builds.
Codec support, especially H.264/H.265/HEIC, depends on Fedora's available codecs.
`ffmpeg-free` does not supply libx264; select an available encoder such as VP9 in
Immich's transcoding settings. This package does not enable third-party RPM
repositories. Hardware acceleration and all phone/camera formats need separate
validation on the target hardware.

These are personal deployment RPMs, not official Fedora or upstream Immich
packages. Bundled JavaScript, Python wheels, and the build-only Extism binary
mean additional unbundling, license review, and build-system work would be needed
for a Fedora distribution submission. Keep the source RPMs with the binaries.

## Test in a disposable container

After building both packages:

```bash
./scripts/test.sh
```

The test installs the RPMs into a clean Fedora 44 container, initializes a fresh
PostgreSQL cluster, runs database setup twice, starts the services' executables
as their service users, and checks the UI/API, administrator login, photo upload,
thumbnail generation, metadata extraction, ML health, and a small ONNX CPU
inference. It also verifies unit
syntax, RPM file integrity, and native library linkage. Logs go to `results/`.
This does not test a booted systemd host, SELinux policy for runtime services,
every media format, downloaded model inference, or GPU acceleration.

The initial Fedora 44 build passed these checks. The dependency-cache rebuild
was also verified in a container with networking disabled. Detailed service logs
and the test result are included in `results/` after running the test.

Upstream references: [quick start](https://docs.immich.app/overview/quick-start/),
[environment variables](https://docs.immich.app/install/environment-variables/),
and [the packaged source release](https://github.com/immich-app/immich/tree/v3.3.5).

# Building and developing the Immich RPMs

This guide covers local builds, validation, packaging decisions, and COPR
publication. For installation and day-to-day administration, see the
[user guide](README.md).

Commands below run from the repository root. Examples use the current specs:
Immich server `3.3.6-1` and machine learning `3.3.6-2`.

- [Build locally](#build-without-installing-build-tools-on-the-host)
- [Install local RPMs](#install-locally-built-rpms)
- [Prepare and check source RPMs](#prepare-source-rpms-for-copr)
- [Run smoke tests](#test-in-a-disposable-container)
- [Publish server releases](#publish-releases-through-git-tags)
- [Publish machine learning releases](#optional-ml-publication)
- [Understand dependency choices](#dependency-choices-and-limits)
- [Repository and installed code layout](#repository-and-installed-code-layout)

## Build without installing build tools on the host

With rootless Podman already available:

```bash
./scripts/build.sh
```

Use `./scripts/build.sh --server-only` to omit ML. RPMs are written to `results/`,
source RPMs to `results/SRPMS/`, downloads to `sources/`, and temporary build
files to `.work/`. Local builder images default to Fedora 44.
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
include the dependency caches, geodata snapshot, and pinned pnpm 11.27.1 needed
to rebuild without the original builder image. The upstream-pinned Extism
compiler 1.7.0 is a build-only binary. Both build tools and the Immich release
archive are checked against `sources/SHA256SUMS`.
Source preparation runs pnpm's registry policy checks while online. The RPM
build uses `--offline --frozen-lockfile --trust-lockfile` so it does not need the
preparer's private registry-metadata cache; store integrity checks remain enabled.

## Install locally built RPMs

Use explicit filenames so you install the intended release:

```bash
sudo dnf install ./results/immich-3.3.6-1.fc44.x86_64.rpm
# Optional:
sudo dnf install ./results/immich-machine-learning-3.3.6-2.fc44.x86_64.rpm
```

Then follow the [database and service setup](README.md#initialize-the-database)
in the user guide. Building or testing RPMs does not install them on your host.

## Prepare source RPMs for COPR

```bash
./scripts/build.sh --srpm-only
```

This downloads/prepares dependencies and runs `rpmbuild -bs` inside Podman;
it does not compile the server or install build tools on the host. It produces
`results/SRPMS/immich-3.3.6-1.fc44.src.rpm`. The SRPM contains everything needed
for an offline RPM build. COPR uses its own Mock buildroot and the spec's
`BuildRequires`, not this repository's Containerfile.

Verify the SRPM locally before uploading:

```bash
./scripts/check-srpm.sh results/SRPMS/immich-3.3.6-1.fc44.src.rpm
```

The checker starts from Fedora 44, installs RPM build tooling and only the
SRPM's declared build dependencies, then rebuilds as an unprivileged user with
`--network=none`. It writes the binary RPM and rebuild log to `results/`. This
catches dependencies accidentally supplied by the convenience builder, but it
is not a full reproduction of COPR's Mock configuration. Check work directories
and images remain available for debugging under `.work/check-srpm.*` and
`localhost/immich-rpm-check:*`.

With your COPR credentials configured, the manual submission commands are:

```bash
# Once, for a new project:
copr-cli create immich --chroot fedora-44-x86_64 --chroot fedora-45-x86_64 --enable-net off
# Upload this source RPM, not the bare spec or a prebuilt binary RPM:
copr-cli build immich results/SRPMS/immich-3.3.6-1.fc44.src.rpm \
  --chroot fedora-44-x86_64 --chroot fedora-45-x86_64 --enable-net off
```

Replace `immich` with your project name. The local build scripts do not create
projects, upload sources, or publish packages. Only x86_64 is supported.

## Test in a disposable container

After building both packages, select the exact RPMs to test:

```bash
./scripts/test.sh results/immich-3.3.6-1.fc44.x86_64.rpm \
  results/immich-machine-learning-3.3.6-2.fc44.x86_64.rpm
```

The test installs the RPMs into a clean Fedora 44 container, initializes a fresh
PostgreSQL cluster, runs database setup twice, starts the services' executables
as their service users, and checks the UI/API, administrator login, photo upload,
thumbnail generation, metadata extraction, ML health, ONNX telemetry disabled
by default, and a small ONNX CPU inference. It also verifies unit syntax, RPM
file integrity, and native library linkage. Logs go to `results/`.
This does not test a booted systemd host, SELinux policy for runtime services,
every media format, downloaded model inference, or GPU acceleration.

For a server-only COPR build, use
`./scripts/test.sh --server-only results/immich-3.3.6-1.fc44.x86_64.rpm`.
To additionally test installation with RPM Fusion FFmpeg already installed:

```bash
IMMICH_TEST_FFMPEG=rpmfusion ./scripts/test.sh --server-only \
  results/immich-3.3.6-1.fc44.x86_64.rpm
```

This explicitly enables RPM Fusion only inside the disposable test container,
installs its FFmpeg first, and checks that Immich preserves it. The default test
uses Fedora repositories and checks that `ffmpeg-free` supplies both commands.

The server-only test skips ML installation and checks while exercising the
database, UI, upload, thumbnail, and metadata paths. You can use explicit paths
to RPMs downloaded from COPR, too. With no paths, the test accepts only one RPM
per requested package in `results/`; it refuses to guess between releases left
by earlier builds.

The initial Fedora 44 build passed these checks. The dependency-cache rebuild
was also verified in a container with networking disabled. Detailed service logs
and the test result are included in `results/` after running the test.

## Publish releases through Git tags

The [bostrt/immich COPR project](https://copr.fedorainfracloud.org/coprs/bostrt/immich/)
builds the server package from
[this GitHub repository](https://github.com/bostrt/immich-rpm).
Its SCM package uses the `make_srpm` method and `.copr/Makefile`.
COPR runs source preparation inside its network-enabled Mock chroot, downloading
the same checked sources and locked dependencies as the local container build.
Source preparation explicitly fetches Linux x86_64/glibc dependencies, even
when COPR assigns it an ARM builder. Native install scripts run during the
subsequent binary builds, which have networking disabled.

| COPR target | Status |
| --- | --- |
| Fedora 44 x86_64 | Enabled; published package passed container installation and smoke tests |
| Fedora 45 x86_64 | Enabled; published package passed container installation and smoke tests |
| Fedora 43 x86_64 | Pending a newer Fedora Node.js RPM; excluded from package builds |

As of 2026-11-04, Fedora 43 provides Node.js 24.14.1, including in updates-testing.
Immich's locked build dependencies require at least 24.15, and this spec uses
the tested minimum of 24.18. We are waiting for a Fedora update rather than
maintaining a Node.js backport. Fedora 43 is not an active build target, and
the `immich` package also excludes `fedora-43-*` so release tags do not trigger
builds with unsatisfied dependencies. Once a suitable Node.js RPM is available,
enable the Fedora 43 chroot, remove that package exclusion, and build/test the
release on Fedora 43 before advertising support. New Fedora releases are not
added automatically.

Pushing a new tag named `immich-VERSION-RELEASE` starts a build of that tagged
commit. For example, `immich-3.3.6-1` matches `Version: 3.3.6` and
`Release: 1%{?dist}` in `immich.spec`. The source target rejects tags that do not
match the spec. A tag does not update the spec or source checksums for you.

For the next packaging revision of the same upstream release:

1. Increment `Release` in `immich.spec`, update its changelog, and commit the
   tested changes. An upstream version update also needs the source checksums,
   patches, and dependency compatibility checked.
2. Push `main`, then create and push the matching tag, for example:

   ```bash
   git push origin main
   git tag -a immich-3.3.6-2 -m 'Immich 3.3.6 packaging release 2'
   git push origin immich-3.3.6-2
   ```

3. Follow the build on COPR. A successful build publishes the RPM to its
   repository automatically. Bump `Release` for fixes rather than moving a
   published tag or replacing an existing RPM version.

The GitHub webhook subscribes only to the `create` event; ordinary branch
pushes and pull requests do not trigger builds. COPR selects the `immich`
package from the tag name. Only tags pushed to GitHub trigger the webhook.
The optional ML package uses direct source RPM uploads, as described below.
Its `immich-machine-learning-VERSION-RELEASE` tags record releases and do not
trigger automatic builds.

To reproduce the package configuration in a new COPR project:

```bash
copr-cli add-package-scm OWNER/PROJECT --name immich \
  --clone-url https://github.com/bostrt/immich-rpm.git \
  --commit main --spec immich.spec --type git --method make_srpm \
  --webhook-rebuild on --chroot-denylist 'fedora-43-*'
```

Then add the project's GitHub integration URL as a GitHub repository webhook,
using JSON and only **Branch or tag creation**. Keep the URL secret; it contains
the COPR webhook credential. See the
[COPR webhook documentation](https://docs.copr.fedorainfracloud.org/user_documentation.html#webhooks).

## Optional ML publication

The optional ML SRPM can be prepared with `--srpm-only --with-ml` and checked
with `check-srpm.sh` in the same way. Release `3.3.6-2` uses Fedora's OpenCV and
NumPy. It excludes the `opencv-python-headless` wheel and its private
FFmpeg/OpenSSL libraries from both the runtime and the dependency cache.
The other Python dependencies remain bundled.

The Fedora 44 RPM passed a container upgrade from `3.3.6-1`,
preserving a modified configuration and cache file. Service startup, the health
endpoint, CPU ONNX inference, native library linkage, and eight OpenCV/image
processing checks passed. A clean, unprivileged rebuild with networking disabled
also passed. Laptop testing against a remote Immich server exercised smart
search, face detection/recognition and OCR, with no errors or automatic restarts
observed in the service logs.

Publish the tested source RPM to the Fedora 44 target explicitly:

```bash
./scripts/check-srpm.sh results/SRPMS/immich-machine-learning-3.3.6-2.fc44.src.rpm
copr-cli build bostrt/immich results/SRPMS/immich-machine-learning-3.3.6-2.fc44.src.rpm \
  --chroot fedora-44-x86_64 --enable-net off
```

Prepare the ML dependency cache on the target Fedora release: its default
Python ABI determines which native wheels are downloaded. A Fedora 44 cache is
not a validated Fedora 45 build input. Keep ML submissions limited to Fedora 44
until the full Python 3.15 service has been built and tested for Fedora 45.

[COPR accepts direct SRPM uploads](https://docs.copr.fedorainfracloud.org/user_documentation.html#direct-upload)
and does not require full Fedora Packaging Guidelines compliance, but its
[content and license requirements](https://docs.copr.fedorainfracloud.org/user_documentation.html#what-i-can-build-in-copr)
still apply to all uploaded sources and binaries, including bundled dependencies.

## Dependency choices and limits

| Component | Packaging |
| --- | --- |
| Node.js | Fedora `nodejs24` |
| Database | Fedora `postgresql-server`, `postgresql-contrib`, `pgvector` |
| Queue/cache | Fedora `valkey` |
| Image processing | Fedora `vips`, `ImageMagick` |
| Metadata | Fedora `perl-Image-ExifTool` |
| Video | `/usr/bin/ffmpeg` and `/usr/bin/ffprobe`, supplied by Fedora `ffmpeg-free` or an installed RPM Fusion `ffmpeg` |
| Python interpreter | Fedora default `python3` (3.14 on Fedora 44) |
| ML image processing | Fedora `python3-opencv` and `python3-numpy` |
| Application JavaScript | Private modules from the upstream lockfile, with the Sharp pin below |
| Python ML stack | Private CPU environment from upstream `uv.lock`, except system OpenCV and NumPy |

Immich 3.3.6 supports `DB_VECTOR_EXTENSION=pgvector`, avoiding a separate
VectorChord build. This selects pgvector indexes; it does not use VectorChord's
indexing implementation. Never point these defaults at an existing VectorChord
database without following upstream migration guidance.

The checked-in compatibility patch pins Sharp to **0.35.3**, within Immich's
declared `^0.35.3` range. That version supports Fedora's libvips **8.18.3**;
upstream's locked Sharp 0.35.5 requires libvips 8.18.7. The vendored ExifTool
executable and prebuilt bcrypt binaries are removed from the runtime package.

Fedora's ONNX and ONNX Runtime packages are too old for this Immich release, so
the optional RPM retains upstream's pinned wheels, including CPU ONNX Runtime
1.30.0. Its private environment can import system packages and explicitly skips
the OpenCV and NumPy wheels so Fedora's packages supply those imports. Fedora's
OpenCV package brings a substantial set of additional library dependencies.

The pinned `immich-model` library declares Python `<3.14`. The builder uses uv,
which ignores dependency Python upper bounds; installing successfully is not an
upstream compatibility guarantee. This release was tested with the default
Fedora 44 Python 3.14 runtime. Immich 3.3.6 disables ONNX Runtime telemetry by
default. The RPM does not install CUDA, ROCm, or OpenVINO runtimes.

Fedora's media packages differ from Immich's custom upstream media builds.
Codec support, especially H.264/H.265/HEIC, depends on the installed media libraries.
`ffmpeg-free` does not supply libx264; select an available encoder such as VP9 in
Immich's transcoding settings. This package does not enable third-party RPM
repositories. An existing RPM Fusion `ffmpeg` installation satisfies the command
dependencies and does not need to be replaced with `ffmpeg-free`. Hardware
acceleration and all phone/camera formats need separate validation on the
target hardware.

These are personal deployment RPMs, not official Fedora or upstream Immich
packages. Bundled JavaScript, Python wheels, and the build-only Extism binary
mean additional unbundling, license review, and build-system work would be needed
for a Fedora distribution submission. Keep the source RPMs with the binaries.

## Repository and installed code layout

| Path | Purpose |
| --- | --- |
| `immich.spec` | Server RPM, web UI, core plugin, and geodata |
| `immich-machine-learning.spec` | Optional CPU machine learning RPM |
| `packaging/` | Service units, default configuration, system users, and database setup |
| `patches/` | Compatibility patches applied to upstream sources |
| `scripts/` | Source preparation, container builds, and validation entry points |
| `tests/` | Container smoke tests |
| `.copr/` | COPR source preparation and release-tag validation |
| `Containerfile`, `Containerfile.ml`, `Containerfile.check` | Build and isolated SRPM-check environments |
| `sources/SHA256SUMS` | Checksums for downloaded sources and build tools |

| Installed code | Location |
| --- | --- |
| Server code and private Node modules | `/usr/libexec/immich/server` |
| Static UI, core plugin, geodata | `/usr/share/immich` |
| Private Python ML environment | `/usr/libexec/immich-machine-learning` |

The server RPM installs `README.md` as `README.fedora.md` in its documentation.
Keep that file focused on users; packaging details belong in this guide.

Upstream references: [quick start](https://docs.immich.app/overview/quick-start/),
[environment variables](https://docs.immich.app/install/environment-variables/),
and [the packaged source release](https://github.com/immich-app/immich/tree/v3.3.6).

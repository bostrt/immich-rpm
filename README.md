# Immich RPMs for Fedora

Run [Immich](https://immich.app), a self-hosted photo and video management
application, directly on Fedora. This repository packages the server, web UI,
and optional machine learning service as native RPMs managed by systemd.
Podman and Docker are not needed to run them.

These are personal deployment packages, maintained independently of Fedora and
upstream Immich. The packaged upstream version is **Immich 3.3.6**.

| Package | Includes | Supported COPR targets |
| --- | --- | --- |
| `immich` | Server, web UI, core workflow plugin, and reverse-geocoding data | Fedora 44 and 45 x86_64 |
| `immich-machine-learning` | Optional CPU service for smart search, faces, and OCR | Fedora 44 x86_64 |

Fedora 43 is not supported. Fedora 45 machine learning is available as a
[local build](DEVELOPMENT.md#build-without-installing-build-tools-on-the-host)
using Fedora's ONNX Runtime package; COPR publication is pending. Until it is
published, build the ML RPM locally, use an external ML service, or disable ML.

- [Install from COPR](#install-from-copr)
- [Configure Immich](#configuration)
- [Manage services and troubleshoot](#services-and-troubleshooting)
- [Update and back up](#updates-and-backups)
- [Media support and limitations](#media-support-and-limitations)
- [Build, test, and publish packages](https://github.com/bostrt/immich-rpm/blob/main/DEVELOPMENT.md)

## Install from COPR

The [bostrt/immich COPR repository](https://copr.fedorainfracloud.org/coprs/bostrt/immich/)
provides the packages. Run these commands on the Fedora machine that will host
Immich:

```bash
sudo dnf copr enable bostrt/immich
sudo dnf install immich
```

DNF installs the required runtime dependencies, including PostgreSQL with
pgvector, Valkey, Node.js, and the media tools.

For local machine learning on **Fedora 44**, also install:

```bash
sudo dnf install immich-machine-learning
```

### Initialize the database

For a **new PostgreSQL installation**, initialize its cluster once:

```bash
sudo postgresql-setup --initdb
```

Skip that command if PostgreSQL already has a cluster. Start the database and
cache services, then prepare Immich's database:

```bash
sudo systemctl enable --now postgresql.service valkey.service
sudo immich-setup
```

`immich-setup` creates the non-superuser `immich` database role, the `immich`
database, and the required extensions. It is safe to rerun. It uses the local
PostgreSQL admin account; it does not initialize a cluster, change authentication
rules, set a database password, or start services.

The default connection uses the Unix socket at `/run/postgresql` with peer
authentication as the `immich` system user. If you already run PostgreSQL, its
`pg_hba.conf` must allow that local connection.

### Start Immich

If you installed the optional ML package, start it first:

```bash
sudo systemctl enable --now immich-machine-learning.service
```

Then start the server:

```bash
sudo systemctl enable --now immich.service
```

Open **<http://localhost:2283>** on the server, or `http://SERVER_ADDRESS:2283`
from another machine. The first registered user becomes the administrator.
For remote access, allow TCP port 2283 in the host firewall or configure a reverse
proxy. The server listens on all interfaces by default; the ML service listens
only on `127.0.0.1:3003`.

If you are not running local ML, go to **Administration → Settings** and disable
machine learning or configure an external ML URL. New installations default to
`http://127.0.0.1:3003`.

## Configuration

The packages use two configuration files:

| File | Service |
| --- | --- |
| `/etc/immich/immich.conf` | Immich server |
| `/etc/immich/machine-learning.conf` | Optional machine learning service |

Edit the relevant file as root, for example:

```bash
sudoedit /etc/immich/immich.conf
sudo systemctl restart immich.service
```

Files use systemd `EnvironmentFile` syntax: one `NAME=value` per line, without
`export` or shell commands. Changes take effect after restarting the affected
service. For ML changes, restart `immich-machine-learning.service` instead.
RPM upgrades preserve modified configuration files.

### Server defaults

| Setting | Default | Purpose |
| --- | --- | --- |
| `IMMICH_HOST` | `0.0.0.0` | Address to listen on |
| `IMMICH_PORT` | `2283` | Web UI and API port |
| `IMMICH_MEDIA_LOCATION` | `/var/lib/immich/media` | Photos, videos, and generated media |
| `IMMICH_PLUGINS_INSTALL_FOLDER` | `/var/lib/immich/plugins` | Writable plugin storage |
| `DB_HOSTNAME` | `/run/postgresql` | Local PostgreSQL socket directory |
| `DB_USERNAME` / `DB_DATABASE_NAME` | `immich` / `immich` | Database role and database |
| `DB_VECTOR_EXTENSION` | `pgvector` | Vector search extension |
| `REDIS_HOSTNAME` / `REDIS_PORT` | `127.0.0.1` / `6379` | Valkey connection |

For a remote database, configure `DB_HOSTNAME`, `DB_PORT`, `DB_USERNAME`,
`DB_DATABASE_NAME`, and `DB_PASSWORD` as needed. The remote database and required
extensions must be prepared separately; `immich-setup` only prepares the local
database.

The default Valkey connection has no configured password. The package leaves
Valkey's authentication settings unchanged. If your Valkey service requires
credentials, configure matching Immich settings in `immich.conf`. See the
[upstream environment variable reference](https://docs.immich.app/install/environment-variables/)
for additional connection options.

These defaults use **pgvector**. Do not point them at an existing VectorChord
database without following upstream migration guidance.

### Use a different media directory

Create a directory owned by the service account:

```bash
sudo install -d -o immich -g immich -m 0750 /srv/immich
```

For an existing library, stop `immich.service` and copy the entire media directory
to the new location, preserving its contents and ownership, before continuing.
Changing the setting does not move existing media.

Set the following in `/etc/immich/immich.conf`:

```ini
IMMICH_MEDIA_LOCATION=/srv/immich
```

Allow the service to write there with `sudo systemctl edit immich.service`:

```ini
[Service]
ReadWritePaths=/srv/immich
```

Then apply the override and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart immich.service
```

The service uses `ProtectHome=yes`, so choose a dedicated location such as
`/srv/immich` instead of a home directory. External libraries also need filesystem
permissions and service sandbox access that allow the `immich` user to read them.

### Machine learning

The ML service runs as the separate `immich-ml` user. Its defaults in
`/etc/immich/machine-learning.conf` include:

| Setting | Default |
| --- | --- |
| `IMMICH_HOST` / `IMMICH_PORT` | `127.0.0.1` / `3003` |
| `MACHINE_LEARNING_CACHE_FOLDER` | `/var/cache/immich-machine-learning` |
| `MACHINE_LEARNING_WORKERS` | `1` |
| `MACHINE_LEARNING_WORKER_TIMEOUT` | `120` seconds |

Model weights download when first needed, so the ML host needs outbound HTTPS
access for that first use. Configure the ML URL in **Administration → Settings**
if you use an external service. This RPM provides CPU inference; it does not
install CUDA, ROCm, or OpenVINO runtimes.

## Services and troubleshooting

Check the server and its local dependencies:

```bash
sudo systemctl status immich.service postgresql.service valkey.service
sudo journalctl -u immich.service -b -n 100 --no-pager
```

For the optional ML service:

```bash
sudo systemctl status immich-machine-learning.service
sudo journalctl -u immich-machine-learning.service -b -n 100 --no-pager
```

| Symptom | Check |
| --- | --- |
| Database connection or authentication errors | PostgreSQL is running, `immich-setup` completed, and local peer authentication is allowed |
| Valkey connection errors | `valkey.service` is running and its address and credentials match `immich.conf` |
| Media path permission errors | The directory is owned by `immich`, parent directories are accessible, and the systemd override allows writes |
| ML unavailable | The ML service is running and its URL matches the setting in Immich; check outbound HTTPS access if model downloads fail |
| UI works locally but is unreachable remotely | Server bind address, firewall, and reverse proxy settings |
| Video transcoding fails | Installed codecs and the selected encoder; see [media support](#media-support-and-limitations) |

Run an administrator command with the server's configuration and identity:

```bash
sudo systemd-run --wait --pty --collect --uid=immich --gid=immich \
  --property=EnvironmentFile=/etc/immich/immich.conf \
  --working-directory=/usr/libexec/immich/server \
  /usr/bin/node /usr/libexec/immich/server/dist/main.js immich-admin --help
```

## Updates and backups

Back up the **PostgreSQL database, media, and configuration** before upgrading.
Immich runs database migrations at startup; downgrading an RPM does not undo
those migrations.

| Data | Default location |
| --- | --- |
| Photos, videos, and generated media | `/var/lib/immich/media` |
| Writable plugin storage | `/var/lib/immich/plugins` |
| Server and ML configuration | `/etc/immich/` |
| Downloaded ML models | `/var/cache/immich-machine-learning` |
| Library records, users, and other database state | PostgreSQL database `immich` |

Use your configured media location if you changed it. Copying the media directory
alone does not back up the database.

Update installed packages from the enabled COPR repository:

```bash
sudo dnf upgrade immich
# If the optional ML package is installed, update it as well:
sudo dnf upgrade immich-machine-learning
```

The package upgrade restarts running Immich services. Check service status and
logs afterward. Review any `.rpmnew` files alongside your configuration for new
defaults. Removing the package does not delete an existing database or uploaded
photos.

## Media support and limitations

These packages use Fedora's media libraries. Codec support, especially
H.264/H.265/HEIC, depends on the libraries installed on your system.

- Fedora's `ffmpeg-free` does not supply libx264. Select an available encoder,
  such as VP9, in Immich's transcoding settings.
- An existing RPM Fusion `ffmpeg` installation satisfies the package's FFmpeg
  dependencies and does not need to be replaced with `ffmpeg-free`. These packages
  do not enable third-party RPM repositories.
- Hardware acceleration and support for every phone or camera format need
  validation on your hardware.

For application usage, see the [Immich documentation](https://docs.immich.app/).
For local builds, dependency details, tests, and COPR releases, see the
[development guide](https://github.com/bostrt/immich-rpm/blob/main/DEVELOPMENT.md).

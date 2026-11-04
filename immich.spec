%global debug_package %{nil}
# Private application modules must not provide unrelated system Node libraries.
%global __provides_exclude_from ^%{_libexecdir}/immich/.*$
%global __requires_exclude ^(npm|nodejs)[(]

Name:           immich
Version:        3.3.5
Release:        3%{?dist}
Summary:        Native photo and video management server
License:        AGPL-3.0-only AND MIT AND BSD-3-Clause AND Apache-2.0 AND CC-BY-4.0
URL:            https://immich.app
Source0:        https://github.com/immich-app/immich/archive/refs/tags/v%{version}.tar.gz#/immich-%{version}.tar.gz
Source1:        immich-%{version}-fedora-pnpm-store.tar.gz
Source2:        immich-geodata.tar.gz
Source3:        immich.service
Source4:        immich.conf
Source5:        immich.sysusers
Source6:        immich.tmpfiles
Source7:        immich-setup
Source8:        use-system-exiftool.py
Source9:        extism-js-x86_64-linux-v1.7.0.gz
Source10:       README.md
Source11:       NOTICE
Source12:       https://registry.npmjs.org/pnpm/-/pnpm-11.27.1.tgz
Patch0:         0001-sharp-use-fedora-libvips.patch
ExclusiveArch:  x86_64
BuildRequires:  nodejs24-devel nodejs24-npm gcc-c++ make python3 vips-devel
BuildRequires:  systemd-rpm-macros perl-Image-ExifTool binaryen
BuildRequires:  nodejs24 >= 1:24.18
# pnpm's progress renderer uses Intl.Segmenter; small-ICU Node can crash here.
BuildRequires:  nodejs24-full-i18n
BuildRequires:  tar gzip findutils
Requires:       nodejs24 >= 1:24.18
Requires:       nodejs24-full-i18n
Requires:       vips >= 8.18.3
Requires:       perl-Image-ExifTool ImageMagick ffmpeg-free
Requires:       postgresql postgresql-server postgresql-contrib pgvector >= 0.7
Requires:       valkey
Requires:       util-linux systemd
Requires(pre):  systemd
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

%description
Immich server and web interface running directly on Fedora under systemd.
Uses Fedora Node.js, PostgreSQL with pgvector, Valkey, libvips, ExifTool,
ImageMagick and FFmpeg. JavaScript dependencies are bundled privately from
the upstream lockfile. Machine learning is a separate service.

%prep
%setup -q
%patch -P 0 -p1
tar -xzf %{SOURCE1}
tar -xzf %{SOURCE2}
mkdir -p rpm-tools/pnpm-package
gzip -dc %{SOURCE9} > rpm-tools/extism-js
chmod 755 rpm-tools/extism-js
# Ship the exact package manager with the SRPM. COPR does not use Containerfile.
tar -xzf %{SOURCE12} -C rpm-tools/pnpm-package --strip-components=1
chmod 755 rpm-tools/pnpm-package/bin/pnpm.mjs
ln -s pnpm-package/bin/pnpm.mjs rpm-tools/pnpm
cp %{SOURCE10} README.fedora.md
cp %{SOURCE11} NOTICE.fedora

%build
export CI=1
export NODE_OPTIONS=--max-old-space-size=3072
export SHARP_FORCE_GLOBAL_LIBVIPS=true
export npm_config_nodedir=/usr
export npm_config_store_dir="$PWD/pnpm-store"
export npm_config_offline=true
export PATH="$PWD/rpm-tools:$PATH"
# Source preparation verifies registry policies online. Offline builds use that
# frozen lockfile; package integrity checks stay enabled without registry metadata.
pnpm --store-dir "$PWD/pnpm-store" --filter 'immich...' --filter 'immich-web...' --filter '@immich/plugin-core...' install --offline --frozen-lockfile --trust-lockfile
pnpm --config.verify-deps-before-run=false --filter @immich/sdk build
pnpm --config.verify-deps-before-run=false --filter @immich/plugin-sdk build
pnpm --config.verify-deps-before-run=false --filter immich build
pnpm --config.verify-deps-before-run=false --filter immich-web build
pnpm --config.verify-deps-before-run=false --filter @immich/plugin-core build
pnpm --store-dir "$PWD/pnpm-store" --offline --trust-lockfile --filter immich --prod --no-optional deploy "$PWD/server-pruned"
pnpm --config.verify-deps-before-run=false --dir server-pruned/node_modules/sharp exec npm run build
python3 %{SOURCE8}
# Keep only native binaries built for this platform, not bundled libvips.
find server-pruned -type d -name prebuilds -prune -exec rm -rf {} +
# Rebuild bcrypt against Fedora's headers after removing upstream prebuilds.
pnpm --config.verify-deps-before-run=false --dir server-pruned/node_modules/bcrypt exec node-gyp rebuild --nodedir=/usr
printf '{"sources":[],"packages":[]}\n' > build-lock.json

%install
install -d %{buildroot}%{_libexecdir}/immich/server %{buildroot}%{_datadir}/immich
cp -a server-pruned/. %{buildroot}%{_libexecdir}/immich/server/
cp -a web/build %{buildroot}%{_datadir}/immich/www
cp -a geodata %{buildroot}%{_datadir}/immich/
install -m 644 build-lock.json %{buildroot}%{_datadir}/immich/
install -d %{buildroot}%{_datadir}/immich/plugins/immich-plugin-core/dist
install -m 644 packages/plugin-core/dist/plugin.wasm %{buildroot}%{_datadir}/immich/plugins/immich-plugin-core/dist/
install -m 644 packages/plugin-core/manifest.json %{buildroot}%{_datadir}/immich/plugins/immich-plugin-core/
install -Dpm 644 %{SOURCE3} %{buildroot}%{_unitdir}/immich.service
install -Dpm 640 %{SOURCE4} %{buildroot}%{_sysconfdir}/immich/immich.conf
install -Dpm 644 %{SOURCE5} %{buildroot}%{_sysusersdir}/immich.conf
install -Dpm 644 %{SOURCE6} %{buildroot}%{_tmpfilesdir}/immich.conf
install -Dpm 755 %{SOURCE7} %{buildroot}%{_sbindir}/immich-setup
install -d %{buildroot}%{_localstatedir}/lib/immich/{media,plugins} %{buildroot}%{_localstatedir}/cache/immich
# Development sources, maps and upstream container launchers are unnecessary.
find %{buildroot}%{_libexecdir}/immich -name '*.map' -delete
rm -rf %{buildroot}%{_libexecdir}/immich/server/bin

%check
cd server-pruned
node --input-type=module -e 'import sharp from "sharp"; if (sharp.versions.vips !== "8.18.3") console.log(sharp.versions); await sharp({create:{width:2,height:2,channels:3,background:"red"}}).jpeg().toBuffer();'
node --input-type=module -e 'import bcrypt from "bcrypt"; if (!await bcrypt.compare("test", await bcrypt.hash("test", 4))) process.exit(1);'
node --input-type=module -e 'import {exiftool} from "exiftool-vendored"; console.log(await exiftool.version()); await exiftool.end();'
test -s ../web/build/index.html
test -s ../packages/plugin-core/dist/plugin.wasm

%pre
%sysusers_create_compat %{SOURCE5}

%post
%systemd_post immich.service
%tmpfiles_create %{_tmpfilesdir}/immich.conf

%preun
%systemd_preun immich.service

%postun
%systemd_postun_with_restart immich.service

%files
%license LICENSE
%doc README.fedora.md NOTICE.fedora
%{_libexecdir}/immich/
%{_datadir}/immich/
%{_unitdir}/immich.service
%{_sysusersdir}/immich.conf
%{_tmpfilesdir}/immich.conf
%{_sbindir}/immich-setup
%dir %{_sysconfdir}/immich
%config(noreplace) %attr(0640,root,immich) %{_sysconfdir}/immich/immich.conf
%attr(0750,immich,immich) %dir %{_localstatedir}/lib/immich
%attr(0750,immich,immich) %dir %{_localstatedir}/lib/immich/media
%attr(0750,immich,immich) %dir %{_localstatedir}/lib/immich/plugins
%attr(0750,immich,immich) %dir %{_localstatedir}/cache/immich

%changelog
* Wed Nov 04 2026 Immich RPM contributors - 3.3.5-3
- Fetch x86_64 dependencies even when COPR prepares sources on an ARM builder
- Defer native dependency install scripts to the offline RPM build

* Wed Nov 04 2026 Immich RPM contributors - 3.3.5-2
- Include the pinned pnpm build tool for offline COPR builds
- Require Node ICU data explicitly in minimal build and runtime environments

* Tue Nov 03 2026 Immich RPM contributors - 3.3.5-1
- Initial native Fedora 44 package, built in a container

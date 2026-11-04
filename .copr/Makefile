# COPR runs this target inside its network-enabled source-build chroot.
# For local builds, use scripts/build.sh so all build tools stay in Podman.
.PHONY: srpm
srpm:
	bash "$(dir $(abspath $(lastword $(MAKEFILE_LIST))))build-srpm.sh" "$(outdir)" "$(spec)"

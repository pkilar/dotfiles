#!/usr/bin/env bash
# Build the beacond Arch packages (beacond, beacond-client).
#
# Must be run on an Arch (or Arch-derived) host with makepkg available.
# Always operates on packaging/arch/ regardless of the caller's cwd, and
# never touches anything outside it or $srcdir/$pkgdir below it.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# makepkg writes beside the PKGBUILD by default. Send output to the repo
# root instead: repo-layout.md gitignores /archbuild/, and the multi-distro
# driver globs archbuild/*.pkg.tar.* from there.
REPO_ROOT="$(cd ../.. && pwd)"
export PKGDEST="$REPO_ROOT/archbuild"
mkdir -p "$PKGDEST"

# Keep .SRCINFO in sync with PKGBUILD. Not needed by makepkg itself, but
# self-hosted repo tooling and reviewers that don't want to evaluate bash
# rely on it, so regenerate it on every build rather than let it go stale.
makepkg --printsrcinfo > .SRCINFO

exec makepkg -sf --noconfirm "$@"

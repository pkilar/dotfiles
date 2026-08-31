#!/usr/bin/env bash
# Build the beacond Arch packages (beacond, beacond-client).
#
# Must be run on an Arch (or Arch-derived) host with makepkg available.
# Always operates on packaging/arch/ regardless of the caller's cwd, and
# never touches anything outside it or $srcdir/$pkgdir below it.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# Keep .SRCINFO in sync with PKGBUILD. Not needed by makepkg itself, but
# self-hosted repo tooling and reviewers that don't want to evaluate bash
# rely on it, so regenerate it on every build rather than let it go stale.
makepkg --printsrcinfo > .SRCINFO

exec makepkg -sf --noconfirm "$@"

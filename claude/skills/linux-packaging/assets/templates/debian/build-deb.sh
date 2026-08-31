#!/usr/bin/env bash
# Build beacond Debian packages.
#
# Usage:
#   ./packaging/debian/build-deb.sh
#
# Stages a source snapshot from the working tree (git archive when the tree
# is a git checkout, otherwise a plain rsync copy), overlays this debian/
# directory onto it, pins debian/changelog's version from the top-level
# VERSION file, and runs dpkg-buildpackage. Uses the "3.0 (native)" source
# format: there is no separate upstream tarball to manage, which fits a
# package that is built and served in-house rather than uploaded to a
# Debian archive (self-hosted distribution is the default assumption for
# this packaging; see packaging/debian/README.md).
#
# Prerequisites:
#   apt-get install build-essential debhelper dpkg-dev fakeroot
#   Go >= 1.22 on PATH (see go.mod; newer than Debian stable's golang-go, so
#   use the golang:<ver>-bookworm image or a manually installed toolchain).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION")"
PKG_NAME="beacond"
STAGE_NAME="${PKG_NAME}-${VERSION}"

echo "==> Building ${PKG_NAME} ${VERSION} Debian packages"

# Throwaway build tree (should stay out of version control). The .debs land
# directly in debbuild/.
DEBBUILD_DIR="${PROJECT_ROOT}/debbuild"
rm -rf "${DEBBUILD_DIR}"
mkdir -p "${DEBBUILD_DIR}/${STAGE_NAME}"
STAGING="${DEBBUILD_DIR}/${STAGE_NAME}"

echo "==> Staging source snapshot..."
if git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "${PROJECT_ROOT}" archive --format=tar HEAD | tar -x -C "${STAGING}"
    # Overlay the working-tree packaging/ so uncommitted or untracked
    # packaging files (e.g. packaging/debian/* before its first commit) are
    # included. Merge-copy the CONTENTS ("/.") into the existing directory
    # to avoid a packaging/packaging/ nesting that would hide them.
    mkdir -p "${STAGING}/packaging"
    cp -a "${PROJECT_ROOT}/packaging/." "${STAGING}/packaging/"
    cp -a "${PROJECT_ROOT}/VERSION" "${STAGING}/VERSION"
else
    rsync -a --exclude='.git' --exclude='debbuild' --exclude='rpmbuild' --exclude='archbuild' \
        "${PROJECT_ROOT}/" "${STAGING}/"
fi

# Install the debian/ packaging dir at the source root and pin the
# changelog version from VERSION so it never drifts from the RPM/Arch
# packaging.
cp -a "${SCRIPT_DIR}/." "${STAGING}/debian/"
chmod +x "${STAGING}/debian/rules"
sed -i "1s/^${PKG_NAME} (.*)/${PKG_NAME} (${VERSION})/" "${STAGING}/debian/changelog"

echo "==> Running dpkg-buildpackage..."
(
    cd "${STAGING}"
    dpkg-buildpackage -b -us -uc
)

echo ""
echo "==> Build complete. Packages:"
find "${DEBBUILD_DIR}" -maxdepth 1 -name '*.deb' 2>/dev/null | sort

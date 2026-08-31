#!/usr/bin/env bash
# build-rpm.sh -- stage a source tarball and build the beacond RPMs.
#
# Usage: packaging/rpm/build-rpm.sh [--topdir DIR]
#
# Requires: rpmbuild, GNU tar (for --transform/--exclude-vcs), and a
# readable repo checkout. No network access and no git needed -- the source
# tarball is a plain tar of the working tree, not a git archive, so it picks
# up whatever is on disk (including uncommitted packaging changes) rather
# than only what has been committed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAME="beacond"
# Repo root, not packaging/rpm/. repo-layout.md gitignores build trees as
# /rpmbuild/, /debbuild/, /archbuild/, and the multi-distro driver globs
# rpmbuild/RPMS/*/*.rpm from the root -- a tree under packaging/rpm/ builds
# fine and then reports "NO ARTIFACTS" when driven from there.
TOPDIR="$REPO_ROOT/rpmbuild"

while [ $# -gt 0 ]; do
    case "$1" in
        --topdir)
            TOPDIR="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,11p' "$0"
            exit 0
            ;;
        *)
            echo "build-rpm.sh: unrecognized argument: $1" >&2
            exit 2
            ;;
    esac
done

if [ ! -f "$REPO_ROOT/VERSION" ]; then
    echo "build-rpm.sh: $REPO_ROOT/VERSION not found" >&2
    exit 1
fi
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
if [ -z "$VERSION" ]; then
    echo "build-rpm.sh: $REPO_ROOT/VERSION is empty" >&2
    exit 1
fi

echo "==> Building ${NAME} ${VERSION} RPMs (topdir: $TOPDIR)"

mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}

TARBALL="$TOPDIR/SOURCES/${NAME}-${VERSION}.tar.gz"
echo "==> Staging source tarball: $TARBALL"
tar \
    --exclude-vcs \
    --exclude="./packaging/rpm/rpmbuild" \
    --exclude="./bin" \
    --transform "s,^\.,${NAME}-${VERSION}," \
    -czf "$TARBALL" \
    -C "$REPO_ROOT" .

cp "$SCRIPT_DIR/beacond.service"   "$TOPDIR/SOURCES/"
cp "$SCRIPT_DIR/beacond.sysusers"  "$TOPDIR/SOURCES/"
cp "$SCRIPT_DIR/beacond.sysconfig" "$TOPDIR/SOURCES/"
cp "$SCRIPT_DIR/beacond.spec"      "$TOPDIR/SPECS/"

echo "==> Running rpmbuild"
rpmbuild \
    --define "_topdir $TOPDIR" \
    --define "beacond_version $VERSION" \
    -ba "$TOPDIR/SPECS/beacond.spec"

echo "==> Built packages:"
find "$TOPDIR/RPMS" "$TOPDIR/SRPMS" -name '*.rpm' -print

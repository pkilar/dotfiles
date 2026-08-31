#!/usr/bin/env bash
#
# verify-package.sh — build, lint, install, and upgrade-test a Linux package in
# a clean container.
#
# Packaging bugs hide in the transitions: a fresh install exercises almost none
# of the code that runs during an upgrade, which is where config files get
# clobbered and daemons fail to restart. This script climbs the verification
# ladder so those transitions actually get executed instead of assumed.
#
#   Tier 1  build the package
#   Tier 2  lint the BUILT package (not just the recipe)
#   Tier 3  install into a clean container, then assert it really landed
#   Tier 4  install the previous version, edit its config, then upgrade
#
# Tier 4 is the point of the exercise. It is the only tier that can tell you
# whether a site admin's edits survive, and it is the tier everyone skips.
#
# A note on why this script is fussy about exit codes: an earlier version piped
# the install command into `tail`, which threw away its status and reported PASS
# for an install that had actually failed. A verification tool that lies is
# worse than no verification tool, so every tier here runs its command
# unpiped, checks the status, and then asserts a post-condition (the package
# is registered with the package manager, the files exist, the user exists)
# rather than trusting the command's own word for it.
#
# Usage:
#   verify-package.sh --format rpm|deb|arch --repo DIR --build-cmd CMD [options]
#
# Options:
#   --format FMT          rpm | deb | arch                          (required)
#   --repo DIR            repository root to build from             (default: .)
#   --build-cmd CMD       command producing packages, run in the container from
#                         the repo root                             (required)
#   --image IMG           override the container image
#   --artifact-glob GLOB  how to find built packages (default per format)
#   --expect-files LIST   space-separated paths that must exist after install
#   --expect-user USER    account that must exist after install
#   --upgrade-from DIR    directory of previously-built packages to install
#                         before upgrading. Without it tier 4 is SKIPPED and
#                         reported as untested — never silently passed.
#   --site DIR            site configuration for a restricted network: internal
#                         repositories, extra CA anchors, an env file and an
#                         optional setup.sh. See references/multi-distro-builds.md
#                         and assets/templates/multi-distro/site.example/.
#                         Proxy variables in the environment (http_proxy,
#                         https_proxy, no_proxy, GOPROXY, ...) are forwarded
#                         automatically, BY NAME so credentials in a URL never
#                         reach a command line or a log.
#   --site-target NAME    which file to take from the site directory. One
#                         repository file is installed, chosen by name:
#                         <NAME>.repo / .list / .sources / .mirrorlist, falling
#                         back to default.<ext>. Lets one site directory hold
#                         configuration for every distribution at once.
#                         (default: "default")
#   --lint-args ARGS      extra arguments for the tier-2 linter, e.g. a project's
#                         justified filter file. The repo is mounted read-only at
#                         /src, so use paths under it:
#                           --lint-args '--ignore-unused-rpmlintrc -r /src/packaging/rpm/x.rpmlintrc'
#                         Without this, tier 2 reports every finding and will FAIL
#                         on packaging whose deviations are deliberate but
#                         unjustified TO THIS TOOL — which is the honest default:
#                         a suppression the tool cannot see is one a reviewer
#                         cannot see either.
#   --keep                keep the work directory for inspection
#   --tier N              stop after tier N (1-4, default 4)
#   -h, --help            this help
#
# Exit status is non-zero if any attempted tier fails.

set -uo pipefail

FORMAT="" REPO="." BUILD_CMD="" IMAGE="" ARTIFACT_GLOB="" UPGRADE_FROM=""
EXPECT_FILES="" EXPECT_USER="" KEEP=0 MAX_TIER=4 LINT_ARGS="" SITE="${PKG_SITE_DIR:-}" SITE_TARGET="default"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 2; }
say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)        FORMAT="$2"; shift 2 ;;
        --repo)          REPO="$2"; shift 2 ;;
        --build-cmd)     BUILD_CMD="$2"; shift 2 ;;
        --image)         IMAGE="$2"; shift 2 ;;
        --artifact-glob) ARTIFACT_GLOB="$2"; shift 2 ;;
        --expect-files)  EXPECT_FILES="$2"; shift 2 ;;
        --expect-user)   EXPECT_USER="$2"; shift 2 ;;
        --upgrade-from)  UPGRADE_FROM="$2"; shift 2 ;;
        --lint-args)     LINT_ARGS="$2"; shift 2 ;;
        --tier)          MAX_TIER="$2"; shift 2 ;;
        --keep)          KEEP=1; shift ;;
        --site)          SITE="$2"; shift 2 ;;
        --site-target)   SITE_TARGET="$2"; shift 2 ;;
        -h|--help)       sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
        *)               die "unknown argument: $1 (try --help)" ;;
    esac
done

[[ -n "$FORMAT" ]]    || die "--format is required (rpm|deb|arch)"
[[ -n "$BUILD_CMD" ]] || die "--build-cmd is required"
[[ -d "$REPO" ]]      || die "--repo '$REPO' is not a directory"
REPO="$(cd "$REPO" && pwd)"

RUNTIME=""
for r in podman docker; do command -v "$r" >/dev/null 2>&1 && { RUNTIME="$r"; break; }; done
[[ -n "$RUNTIME" ]] || die "no container runtime found (need podman or docker)"

WORK="$(mktemp -d)"
cleanup() { if [[ $KEEP -eq 1 ]]; then echo "work dir kept: $WORK"; else rm -rf "$WORK"; fi; }
trap cleanup EXIT

# A malformed ~/.docker/config.json makes podman fail every pull with an opaque
# JSON parse error. Point it at a throwaway auth file unless the caller set one.
if [[ "$RUNTIME" == "podman" && -z "${REGISTRY_AUTH_FILE:-}" ]]; then
    printf '{}' > "$WORK/auth.json"; export REGISTRY_AUTH_FILE="$WORK/auth.json"
fi

case "$FORMAT" in
    rpm)
        IMAGE="${IMAGE:-fedora:latest}"
        ARTIFACT_GLOB="${ARTIFACT_GLOB:-*.rpm}"
        TOOLCHAIN='dnf install -y -q --setopt=install_weak_deps=False rpm-build rpmdevtools rpmlint make git rsync tar findutils "dnf-command(builddep)"'
        # Installs what the spec's own BuildRequires ask for, so this works on a
        # project whose toolchain is not in the fixed list above.
        BUILDDEP='spec=$(find /build -name "*.spec" -type f | head -1); [ -n "$spec" ] && dnf builddep -y -q "$spec"'
        LINT='rpmlint'
        SITE_REPO_DIR='/etc/yum.repos.d'; SITE_CA_DIR='/etc/pki/ca-trust/source/anchors'; SITE_CA_UPDATE='update-ca-trust'
        SITE_REPO_EXT='repo'; SITE_REPO_DEST=''
        PREP=':'
        INSTALL='dnf install -y --setopt=install_weak_deps=False'
        # Deliberately NOT `rpm -Uvh --nodeps`: --nodeps discards the dependency
        # check this tier exists to perform, and plain rpm cannot resolve deps
        # from a repo the way dnf can. dnf handles the upgrade path correctly.
        UPGRADE='dnf install -y --setopt=install_weak_deps=False'
        QUERY='rpm -qa'
        LISTCFG='rpm -qcp'
        ;;
    deb)
        IMAGE="${IMAGE:-debian:stable}"
        ARTIFACT_GLOB="${ARTIFACT_GLOB:-*.deb}"
        TOOLCHAIN='export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential debhelper devscripts equivs lintian git make ca-certificates'
        # Installs what debian/control's Build-Depends ask for. The control file
        # is located rather than assumed at ./debian, since it commonly lives
        # under packaging/debian in a multi-format repo.
        BUILDDEP='ctl=$(find /build -path "*/debian/control" -type f | head -1); [ -n "$ctl" ] && mk-build-deps -ri -t "apt-get -y --no-install-recommends" "$ctl"'
        LINT='lintian --tag-display-limit 0'
        SITE_REPO_DIR='/etc/apt/sources.list.d'; SITE_CA_DIR='/usr/local/share/ca-certificates'; SITE_CA_UPDATE='update-ca-certificates'
        SITE_REPO_EXT='list sources'; SITE_REPO_DEST=''
        # apt refuses a bare filename for a local .deb — it must look like a path.
        # The install container is fresh, so it has no package index. Without
        # this, every declared dependency reports "not installable" and the
        # tier fails for a reason that has nothing to do with the package.
        PREP='export DEBIAN_FRONTEND=noninteractive; apt-get update -qq'
        INSTALL='apt-get install -y --no-install-recommends'
        UPGRADE='apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confold'
        QUERY="dpkg-query -W -f='\${Package}\n'"
        LISTCFG='dpkg-deb -I'
        ;;
    arch)
        IMAGE="${IMAGE:-archlinux:base-devel}"
        ARTIFACT_GLOB="${ARTIFACT_GLOB:-*.pkg.tar.zst}"
        TOOLCHAIN='pacman -Syu --noconfirm --needed base-devel namcap git'
        # makepkg -s resolves makedepends itself, so there is nothing to do here.
        BUILDDEP=':'
        LINT='namcap'
        SITE_REPO_DIR='/etc/pacman.d'; SITE_CA_DIR='/etc/ca-certificates/trust-source/anchors'; SITE_CA_UPDATE='trust extract-compat'
        # pacman.conf includes this path by exact name.
        SITE_REPO_EXT='mirrorlist'; SITE_REPO_DEST='mirrorlist'
        PREP='pacman -Sy --noconfirm'
        INSTALL='pacman -U --noconfirm'
        UPGRADE='pacman -U --noconfirm'
        QUERY='pacman -Qq'
        LISTCFG='pacman -Qip'
        ;;
    *) die "unsupported --format '$FORMAT' (rpm|deb|arch)" ;;
esac

mkdir -p "$WORK/artifacts"
# Prepended to every container script. Empty unless --site was given, so the
# no-firewall path is byte-for-byte what it was. Order matters: the CA must be
# trusted before an HTTPS mirror is contacted, and mirrors must exist before the
# first install. setup.sh runs last so it can override the rest -- typically to
# remove the distribution's own unreachable mirrors, BY NAME, since a glob would
# take the site files placed a moment earlier.
SITE_APPLY=""
if [[ -n "$SITE" ]]; then
    [[ -d "$SITE" ]] || die "--site '$SITE' is not a directory"
    SITE=$(cd -- "$SITE" && pwd)
    SITE_APPLY="
if [ -d /site ]; then
    [ -f /site/env ] && { . /site/env; export \$(sed -n 's/^[[:space:]]*\\([A-Za-z_][A-Za-z0-9_]*\\)=.*/\\1/p' /site/env) 2>/dev/null || true; }
    if ls /site/ca/*.crt >/dev/null 2>&1; then
        mkdir -p $SITE_CA_DIR && cp /site/ca/*.crt $SITE_CA_DIR/ && $SITE_CA_UPDATE >/dev/null 2>&1 || true
    fi
    _done=
    for _n in $SITE_TARGET default; do
        [ -n \"\$_done\" ] && break
        for _e in $SITE_REPO_EXT; do
            [ -f /site/$FORMAT/\$_n.\$_e ] || continue
            mkdir -p $SITE_REPO_DIR
            # Prefixed: a target id is often the distribution's own repo
            # filename (fedora.repo, rocky.repo, ubi.repo), and overwriting one
            # deletes the base repository.
            cp /site/$FORMAT/\$_n.\$_e $SITE_REPO_DIR/${SITE_REPO_DEST:-00-site-\$_n.\$_e}
            echo \"site: \$_n.\$_e -> $SITE_REPO_DIR\"; _done=1; break
        done
    done
    if [ -z \"\$_done\" ] && [ -d /site/$FORMAT ] && [ -n \"\$(ls -A /site/$FORMAT 2>/dev/null)\" ]; then
        echo \"site: WARNING /site/$FORMAT has files but none named '$SITE_TARGET.<ext>' or 'default.<ext>' (ext: $SITE_REPO_EXT)\" >&2
    fi
    [ -x /site/setup.sh ] && /site/setup.sh
fi
"
fi

FAILED=0

ctr() {  # ctr <podman-args...> -- <script>;  returns the script's real status
    local script="${!#}" args=("${@:1:$#-1}")
    # Every tier needs the network -- build, lint, install and upgrade all
    # resolve dependencies -- so the proxy and site config apply to all of them.
    #
    # Proxy variables are forwarded BY NAME: `-e VAR` takes the value from this
    # process, so a proxy URL carrying credentials never appears in a command
    # line, in ps output, or in a log.
    local env_args=() v
    for v in http_proxy https_proxy ftp_proxy no_proxy \
             HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY \
             GOPROXY GOSUMDB GONOSUMDB GOPRIVATE GOFLAGS; do
        [[ -n "${!v:-}" ]] && env_args+=(-e "$v")
    done
    [[ -n "$SITE" ]] && env_args+=(-v "$SITE:/site:ro")
    "$RUNTIME" run --rm "${env_args[@]}" "${args[@]}" "$IMAGE" bash -c "$SITE_APPLY
$script"
}

# ---------------------------------------------------------------- tier 1 -----
say "Tier 1 — build ($FORMAT, image $IMAGE)"

# makepkg refuses to run as root by design, so Arch builds need an unprivileged
# user. git refuses to operate on a tree owned by another uid, which makes build
# scripts silently fall through to non-git codepaths — set safe.directory.
if [[ "$FORMAT" == "arch" ]]; then
    BUILD_WRAPPER='useradd -m builder; chown -R builder /build; runuser -u builder -- bash -lc "cd /build && '"$BUILD_CMD"'"'
else
    BUILD_WRAPPER="$BUILD_CMD"
fi

read -r -d '' BUILD_SCRIPT <<EOF || true
set -e
$TOOLCHAIN >/dev/null 2>&1 || { echo "TOOLCHAIN INSTALL FAILED"; $TOOLCHAIN; exit 1; }
git config --global --add safe.directory '*' 2>/dev/null || true
cp -a /src /build && cd /build
# Snapshot matching files that already exist. A repo may carry previously built
# packages -- a dist/ tree, a stale rpmbuild/ -- and collecting those would lint
# them as current and install them in tier 3. Only what THIS build produced counts.
find /build -name '$ARTIFACT_GLOB' -type f | sort > /tmp/artifacts.before
# An unsatisfiable BuildRequires is itself a finding -- it means the package
# cannot be built on its stated target -- so this warns rather than failing
# here, and lets the build report the specific missing dependency.
$BUILDDEP || echo "NOTE: build-dep resolution failed; the build may now fail on a missing BuildRequires"
$BUILD_WRAPPER
found=\$(comm -13 /tmp/artifacts.before <(find /build -name '$ARTIFACT_GLOB' -type f | sort))
[ -n "\$found" ] || { echo "NO NEW ARTIFACTS matching $ARTIFACT_GLOB"; exit 1; }
echo "\$found" | while read -r f; do cp "\$f" /out/; done
EOF

if ctr -v "$REPO":/src:ro -v "$WORK/artifacts":/out -- "$BUILD_SCRIPT" > "$WORK/build.log" 2>&1; then
    n=$(find "$WORK/artifacts" -type f | wc -l)
    ok "built $n package(s)"; find "$WORK/artifacts" -type f -printf '       %f\n'
else
    bad "build failed"; tail -30 "$WORK/build.log"; exit 1
fi
[[ "$MAX_TIER" -lt 2 ]] && exit 0

# ---------------------------------------------------------------- tier 2 -----
say "Tier 2 — lint the built package"

# The linter's exit status is the signal, so it must not be piped away. An
# earlier version of this tier ran `$LINT "$p" | tail -20`, which discarded the
# status AND hid every finding past the twentieth line -- and rpmlint prints a
# multi-line configuration preamble before its findings, so that window fills
# with boilerplate. A linter that failed to run therefore read exactly like a
# package with nothing wrong, which is the same defect this script's own
# install tier was fixed for once already.
#
# namcap is the exception: it always exits 0 whatever it finds, so its output
# has to be parsed. That is also why the "did anything get linted at all" check
# is not optional -- with a glob that matches nothing, a loop that never runs
# and a clean package look identical.
read -r -d '' LINT_SCRIPT <<EOF || true
$TOOLCHAIN >/dev/null 2>&1
cd /pkgs
rc=0; n=0
for p in $ARTIFACT_GLOB; do
    [ -e "\$p" ] || continue
    n=\$((n + 1))
    echo "--- \$p"
    if $LINT $LINT_ARGS "\$p" > /tmp/lint.out 2>&1; then :; else rc=1; fi
    cat /tmp/lint.out
    grep -qE '(: E: | E: )' /tmp/lint.out && rc=1
done
[ "\$n" -gt 0 ] || { echo "NO ARTIFACTS LINTED — glob '$ARTIFACT_GLOB' matched nothing"; exit 1; }
exit \$rc
EOF
if ctr -v "$WORK/artifacts":/pkgs -v "$REPO":/src:ro -- "$LINT_SCRIPT" > "$WORK/lint.log" 2>&1; then
    ok "no error-level findings"
    sed 's/^/       /' "$WORK/lint.log"
else
    bad "error-level findings, or the linter did not run — triage each one"
    sed 's/^/       /' "$WORK/lint.log"
    FAILED=1
fi
echo "  triage each finding: real bug / expected for this language / deliberate"
echo "  a justified suppression goes in the project's filter file with its reason"
echo "  and is applied here with --lint-args (see --help)"
echo "  (debian/*.lintian-overrides, or an .rpmlintrc using addFilter(), not TOML)"
[[ "$MAX_TIER" -lt 3 ]] && exit "$FAILED"

# ---------------------------------------------------------------- tier 3 -----
say "Tier 3 — install into a clean container"

# Assertions live here, not in the install command's exit status: a package
# manager can exit 0 having installed nothing useful.
read -r -d '' INSTALL_SCRIPT <<EOF || true
set -e
$PREP
cd /pkgs
$INSTALL ./$ARTIFACT_GLOB
echo "--- registered with the package manager:"
$QUERY | sort | tail -20
EOF
[[ -n "$EXPECT_USER" ]] && INSTALL_SCRIPT+="
echo '--- expected user:'
getent passwd '$EXPECT_USER' || { echo \"MISSING USER $EXPECT_USER\"; exit 1; }"
[[ -n "$EXPECT_FILES" ]] && INSTALL_SCRIPT+="
echo '--- expected files:'
for f in $EXPECT_FILES; do
  [ -e \"\$f\" ] && ls -ld \"\$f\" || { echo \"MISSING FILE \$f\"; exit 1; }
done"
INSTALL_SCRIPT+="
echo '--- units shipped (containers have no running systemd; presence only):'
ls /usr/lib/systemd/system /lib/systemd/system 2>/dev/null | grep -E '[.](service|socket|timer)\$' || echo '(none)'"

if ctr -v "$WORK/artifacts":/pkgs -- "$INSTALL_SCRIPT" > "$WORK/install.log" 2>&1; then
    ok "installs cleanly and post-conditions hold"
    sed 's/^/       /' "$WORK/install.log" | tail -30
else
    bad "install failed"; tail -30 "$WORK/install.log"; FAILED=1
fi
[[ "$MAX_TIER" -lt 4 ]] && exit "$FAILED"

# ---------------------------------------------------------------- tier 4 -----
say "Tier 4 — upgrade test (old → new, with a modified config file)"
if [[ -z "$UPGRADE_FROM" ]]; then
    skip "no --upgrade-from given, so the upgrade path was NOT tested."
    echo "       This is the tier that catches config-clobbering and restart bugs."
    echo "       Build the previous release into a directory and pass it here."
    exit "$FAILED"
fi
[[ -d "$UPGRADE_FROM" ]] || die "--upgrade-from '$UPGRADE_FROM' is not a directory"

case "$FORMAT" in
    rpm)  CFGLIST='for p in ./*.rpm; do rpm -qcp "$p"; done' ;;
    deb)  CFGLIST='for p in ./*.deb; do dpkg-deb -I "$p" conffiles 2>/dev/null || true; done' ;;
    arch) CFGLIST='for p in ./*.pkg.tar.zst; do bsdtar xOf "$p" .PKGINFO | sed -n "s|^backup = |/|p"; done' ;;
esac

read -r -d '' UPGRADE_SCRIPT <<EOF || true
set -e
$PREP
cd /old
echo "--- installing OLD"
$INSTALL ./$ARTIFACT_GLOB
CONFIGS=\$($CFGLIST | sort -u)
echo "--- config files these packages own:"; echo "\$CONFIGS"
[ -n "\$CONFIGS" ] || echo "(none — nothing to preserve, so this tier proves little)"
for c in \$CONFIGS; do
  [ -f "\$c" ] && echo '# SITE EDIT MARKER' >> "\$c" || true
done
cd /pkgs
echo "--- upgrading to NEW"
$UPGRADE ./$ARTIFACT_GLOB
echo "--- did site edits survive?"
rc=0
for c in \$CONFIGS; do
  if [ -f "\$c" ] && grep -q 'SITE EDIT MARKER' "\$c"; then echo "  PRESERVED \$c"
  else echo "  LOST      \$c"; rc=1; fi
done
echo "--- package-manager conflict files left behind:"
find /etc \( -name '*.rpmnew' -o -name '*.rpmsave' -o -name '*.dpkg-dist' \
          -o -name '*.dpkg-old' -o -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null || true
exit \$rc
EOF

if ctr -v "$WORK/artifacts":/pkgs -v "$(cd "$UPGRADE_FROM" && pwd)":/old:ro -- "$UPGRADE_SCRIPT" > "$WORK/upgrade.log" 2>&1; then
    ok "upgrade completed and every config file kept its site edits"
    sed 's/^/       /' "$WORK/upgrade.log" | tail -30
else
    bad "upgrade test failed — a config file lost its site edits, or the upgrade itself broke"
    sed 's/^/       /' "$WORK/upgrade.log" | tail -35; FAILED=1
fi

say "Summary"
echo "  format=$FORMAT image=$IMAGE tiers=1..$MAX_TIER result=$([[ $FAILED -eq 0 ]] && echo PASS || echo FAIL)"
echo "  Not covered by any tier: unit activation under a real init system,"
echo "  SELinux/AppArmor policy, device access, anything needing real hardware."
exit "$FAILED"

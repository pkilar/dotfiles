#!/usr/bin/env bash
#
# parity-check.sh — compare what the RPM, deb, and Arch packagings of the same
# project actually produce.
#
# Projects that ship several formats drift. Someone adds a file to the spec and
# forgets debian/install; a dependency gets bumped in one place; a config file
# is marked noreplace in RPM but is a plain (auto-)conffile on Debian with
# different semantics. None of this is visible in review — the diff touches one
# directory and looks complete — and each drift breaks exactly one group of
# users, who are usually not the ones doing the review.
#
# This compares the BUILT packages rather than the recipes, because the recipes
# are written in three different languages and only the output is comparable.
#
# Usage:
#   parity-check.sh [--rpm DIR|GLOB] [--deb DIR|GLOB] [--arch DIR|GLOB]
#
#   At least two formats must be given. Paths may be a directory containing
#   packages, or a glob.
#
# Some divergence is correct: env files live at /etc/sysconfig, /etc/default,
# and /etc/conf.d respectively, and helper scripts at /usr/libexec vs /usr/lib.
# Those are normalised. Anything still reported is either a real drift or a
# deliberate difference you should be able to name.

set -uo pipefail

RPM_SRC="" DEB_SRC="" ARCH_SRC=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rpm)  RPM_SRC="$2"; shift 2 ;;
        --deb)  DEB_SRC="$2"; shift 2 ;;
        --arch) ARCH_SRC="$2"; shift 2 ;;
        -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//;$d'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

n=0; for s in "$RPM_SRC" "$DEB_SRC" "$ARCH_SRC"; do [[ -n "$s" ]] && n=$((n+1)); done
[[ "$n" -ge 2 ]] || { echo "error: give at least two of --rpm/--deb/--arch" >&2; exit 2; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

expand() {  # expand <dir-or-glob> <extension>
    local src="$1" ext="$2"
    if [[ -d "$src" ]]; then find "$src" -name "*.$ext" -type f | sort
    else ls -1 $src 2>/dev/null | sort; fi
}

# Normalise away differences that are conventional rather than accidental, so
# the report shows real drift instead of known-good distro divergence.
normalise() {
    sed -e 's|^\./|/|' -e 's|^\([^/]\)|/\1|' \
        -e 's|^/lib/|/usr/lib/|' \
        -e 's|^/etc/sysconfig/|/etc/ENVDIR/|' \
        -e 's|^/etc/default/|/etc/ENVDIR/|' \
        -e 's|^/etc/conf\.d/|/etc/ENVDIR/|' \
        -e 's|^/usr/libexec/|/usr/LIBEXEC/|' \
        -e 's|^/usr/lib/\([a-z0-9_-]*\)/\(.*\.sh\)$|/usr/LIBEXEC/\1/\2|' \
        -e 's|/$||' \
    | grep -vE '^/?$' \
    | grep -vE '^/(\.|$)' \
    | grep -vE '^/usr/share/(doc|man|licenses)(/|$)' \
    | grep -vE '^/usr/share/lintian(/|$)' \
    | grep -vE '^/(usr|etc|var|usr/bin|usr/lib|usr/share|var/log|var/lib)$' \
    | sort -u
}

collect_rpm()  { for p in $(expand "$1" rpm); do rpm -qlp "$p" 2>/dev/null; done | normalise; }
collect_deb()  { for p in $(expand "$1" deb); do dpkg-deb -c "$p" 2>/dev/null | awk '{print $6}'; done | normalise; }
collect_arch() { for p in $(expand "$1" 'pkg.tar.zst'); do bsdtar tf "$p" 2>/dev/null; done | grep -v '^\.' | normalise; }

cfg_rpm()  { for p in $(expand "$1" rpm); do rpm -qcp "$p" 2>/dev/null; done | normalise; }
cfg_deb()  { for p in $(expand "$1" deb); do dpkg-deb -I "$p" conffiles 2>/dev/null; done | normalise; }
cfg_arch() { for p in $(expand "$1" 'pkg.tar.zst'); do bsdtar xOf "$p" .PKGINFO 2>/dev/null | sed -n 's|^backup = |/|p'; done | normalise; }

FORMATS=()
[[ -n "$RPM_SRC" ]]  && { collect_rpm  "$RPM_SRC"  > "$WORK/rpm.files";  cfg_rpm  "$RPM_SRC"  > "$WORK/rpm.cfg";  FORMATS+=(rpm); }
[[ -n "$DEB_SRC" ]]  && { collect_deb  "$DEB_SRC"  > "$WORK/deb.files";  cfg_deb  "$DEB_SRC"  > "$WORK/deb.cfg";  FORMATS+=(deb); }
[[ -n "$ARCH_SRC" ]] && { collect_arch "$ARCH_SRC" > "$WORK/arch.files"; cfg_arch "$ARCH_SRC" > "$WORK/arch.cfg"; FORMATS+=(arch); }

for f in "${FORMATS[@]}"; do
    c=$(wc -l < "$WORK/$f.files")
    [[ "$c" -eq 0 ]] && { echo "error: found no $f packages (check the path/glob)" >&2; exit 2; }
done

report() {   # report <label> <suffix>
    local label="$1" sfx="$2" drift=0
    printf '\n\033[1m== %s\033[0m\n' "$label"
    cat "${FORMATS[@]/#/$WORK/}" 2>/dev/null >/dev/null
    local all="$WORK/all.$sfx"
    cat $(for f in "${FORMATS[@]}"; do echo "$WORK/$f.$sfx"; done) | sort -u > "$all"

    printf '  %-58s' 'PATH'; for f in "${FORMATS[@]}"; do printf ' %-5s' "$f"; done; echo
    printf '  %s\n' "$(printf '%.0s-' {1..78})"
    while read -r path; do
        local row="" missing=0
        for f in "${FORMATS[@]}"; do
            if grep -qxF "$path" "$WORK/$f.$sfx"; then row+=" $(printf '%-5s' 'yes')"
            else row+=" $(printf '%-5s' '--')"; missing=1; fi
        done
        if [[ "$missing" -eq 1 ]]; then
            printf '  \033[33m%-58s\033[0m%s\n' "$path" "$row"; drift=$((drift+1))
        fi
    done < "$all"
    [[ "$drift" -eq 0 ]] && printf '  (no drift)\n' || printf '\n  %d path(s) differ between formats.\n' "$drift"
    return "$drift"
}

report "File payload — paths present in some formats but not others" files
FILE_DRIFT=$?
report "Config-file treatment — paths one format protects and another does not" cfg
CFG_DRIFT=$?

printf '\n\033[1m== Summary\033[0m\n'
printf '  formats compared: %s\n' "${FORMATS[*]}"
printf '  payload drift:    %d path(s)\n' "$FILE_DRIFT"
printf '  config drift:     %d path(s)\n' "$CFG_DRIFT"
cat <<'EOF'

  Config drift is the more dangerous of the two: a file protected in one format
  and unprotected in another means the same upgrade destroys site edits for one
  group of users and not the other. Note that Debian registers every file under
  /etc as a conffile automatically, so a "code" file shows as protected there
  and unprotected elsewhere — that asymmetry is forced, not a mistake, but it
  should be a decision you made rather than one you discover here.

  In the payload table, a row that is a bare directory (no file extension, and
  files below it appear in every format) usually means one format is not
  *owning* that directory — an explicit %dir entry is missing from the spec, or
  a .install/dirs entry from the others. That leaves the directory orphaned with
  arbitrary ownership when the package is removed.

  Expected, non-actionable differences you may still see: RPM %ghost entries
  exist only on RPM; state directories created via tmpfiles.d are packaged paths
  on one format and not on another; per-format helper filenames may differ.
EOF
[[ $((FILE_DRIFT + CFG_DRIFT)) -eq 0 ]] && exit 0 || exit 1

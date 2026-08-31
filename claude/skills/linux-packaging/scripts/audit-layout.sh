#!/usr/bin/env bash
#
# audit-layout.sh — check how a repository organises its packaging.
#
# This is the cheap pass that runs before any container work. It finds
# organisational defects rather than semantic ones, which matters because the
# two correlate: an asset duplicated across three format directories is an asset
# that was updated in one of them.
#
# The standard it checks against (see references/repo-layout.md):
#   - everything packaging-related lives under packaging/<format>/
#   - anything used by more than one format has ONE copy, in its own sibling dir
#   - a single top-level VERSION is the only place the version is written
#   - each format has a build-<format>.sh entry point
#   - build trees are generated, not committed
#
# Usage: audit-layout.sh [repo-root]      (default: current directory)
#
# Exit status is the number of findings, so it can gate CI.

set -uo pipefail
ROOT="${1:-.}"
cd "$ROOT" || { echo "error: cannot enter $ROOT" >&2; exit 255; }

FINDINGS=0
say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFIND\033[0m  %s\n' "$*"; FINDINGS=$((FINDINGS+1)); }
note() { printf '        %s\n' "$*"; }

in_git() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }
lsfiles() { if in_git; then git ls-files; else find . -type f -not -path './.git/*' | sed 's|^\./||'; fi; }

say "1. Is anything packaging-related outside packaging/ ?"
STRAY=$(lsfiles | grep -iE '\.spec$|(^|/)debian/(control|rules|changelog)$|(^|/)PKGBUILD$' \
        | grep -v '^packaging/' || true)
if [[ -n "$STRAY" ]]; then
    bad "packaging recipes live outside packaging/"
    echo "$STRAY" | sed 's/^/        /'
    note "Consolidating means 'what does this ship?' has one answer."
else
    ok "all recipes are under packaging/"
fi

say "2. Which formats are present, and do they have entry points?"
FOUND=0
for fmt in rpm debian arch; do
    [[ -d "packaging/$fmt" ]] || continue
    FOUND=$((FOUND+1))
    if compgen -G "packaging/$fmt/build-*.sh" >/dev/null; then
        ok "$fmt  ($(basename $(compgen -G "packaging/$fmt/build-*.sh" | head -1)))"
    else
        bad "$fmt has no build-*.sh entry point"
        note "One script per format, same shape, so running one teaches all three."
    fi
done
[[ "$FOUND" -eq 0 ]] && note "(no packaging/{rpm,debian,arch} directories found)"

say "3. Is any asset duplicated across format directories?"
# Scan wherever the packaging actually lives, not just packaging/. Looking only
# under packaging/ made this check vacuous on exactly the repos that most need
# it: one that has not adopted the layout keeps its duplicates in debian/, rpm/
# and archlinux/, so the check passed while three drifted copies of the same
# config sat one directory up.
SCAN_DIRS=()
[[ -d packaging ]] && SCAN_DIRS+=(packaging)
while read -r d; do
    [[ -n "$d" && -d "$d" ]] && SCAN_DIRS+=("$d")
done < <(lsfiles | grep -iE '\.spec$|(^|/)debian/(control|rules|changelog)$|(^|/)PKGBUILD$' \
         | cut -d/ -f1 | grep -v '^packaging$' | sort -u)

if [[ ${#SCAN_DIRS[@]} -gt 0 ]]; then
    DUPES=$(find "${SCAN_DIRS[@]}" -type f -exec md5sum {} + 2>/dev/null \
            | sort | uniq -w32 -d --all-repeated=separate || true)
    if [[ -n "$DUPES" ]]; then
        bad "identical files exist at more than one path"
        echo "$DUPES" | awk '{ if (NF) print "        " $2; else print "" }'
        note "Move the shared copy to packaging/<asset-kind>/ and have each"
        note "recipe install that one path. A duplicate gets fixed once."
    else
        ok "no duplicated payload across ${SCAN_DIRS[*]}"
    fi
else
    note "(no packaging directories found to compare)"
fi

say "4. Is the version derived from one place?"
if [[ -f VERSION ]]; then
    V=$(tr -d '[:space:]' < VERSION)
    ok "VERSION exists: $V"
    case "$V" in
        v*) bad "VERSION starts with 'v'"
            note "The 'v' belongs on the git tag, not the file." ;;
    esac
    # A literal version in a recipe is only a finding if it disagrees with VERSION,
    # or if it is not obviously a placeholder the build rewrites.
    for f in packaging/rpm/*.spec packaging/arch/PKGBUILD packaging/debian/changelog; do
        [[ -f "$f" ]] || continue
        LIT=$(grep -hoE '^(Version:[[:space:]]*|pkgver=)[0-9][0-9.]*' "$f" 2>/dev/null | grep -oE '[0-9][0-9.]*' | head -1)
        # Strip the Debian revision before comparing: a changelog entry is
        # "pkg (0.1.0-1)" for VERSION "0.1.0", and comparing the whole string
        # reported every correctly-versioned package as drifted -- including a
        # deliberate "0.0.0-1" placeholder, which then never matched the
        # placeholder allowance below either.
        [[ "$f" == *changelog ]] && LIT=$(head -1 "$f" | grep -oE '\(([^)]*)\)' | tr -d '()' | head -1 | sed 's/-[^-]*$//')
        [[ -z "$LIT" ]] && continue
        if [[ "$LIT" == "$V" ]]; then
            ok "$f pinned at $LIT (matches VERSION)"
        elif [[ "$LIT" == "0.0.0" || "$LIT" == "0.0" ]]; then
            ok "$f uses a placeholder ($LIT) the build rewrites"
        else
            bad "$f says $LIT but VERSION says $V"
            note "Have the build script rewrite it in the staging copy, so the"
            note "two cannot disagree. Rewrite beats cross-check: a warning gets"
            note "ignored, a rewrite cannot."
        fi
    done
else
    bad "no top-level VERSION file"
    note "One line, no 'v'. Every format derives its version field from it."
fi

say "5. Are build trees generated rather than committed?"
if in_git; then
    BEFORE=$FINDINGS; SEEN=0
    for d in rpmbuild debbuild archbuild packaging/arch/src packaging/arch/pkg; do
        TRACKED=$(git ls-files "$d" 2>/dev/null | head -1)
        if [[ -n "$TRACKED" ]]; then
            bad "$d is committed to git"; SEEN=$((SEEN+1))
        elif git check-ignore -q "$d" 2>/dev/null; then
            ok "$d ignored"; SEEN=$((SEEN+1))
        fi
    done
    if [[ "$FINDINGS" -eq "$BEFORE" ]]; then
        if [[ "$SEEN" -eq 0 ]]; then
            note "no build trees present to check — a .gitignore rule written as"
            note "'/rpmbuild/' only matches an existing directory, so this cannot"
            note "confirm the rule until a build has run at least once."
        else
            ok "no build trees committed"
        fi
    fi
else
    note "(not a git repo — skipped)"
fi

say "Summary"
if [[ "$FINDINGS" -eq 0 ]]; then
    printf '  \033[32mNo layout findings.\033[0m\n'
else
    printf '  \033[31m%d finding(s).\033[0m See references/repo-layout.md.\n' "$FINDINGS"
fi
echo "  This pass checks organisation only. It says nothing about whether the"
echo "  packaging is semantically correct — run the verification ladder for that."
exit "$FINDINGS"

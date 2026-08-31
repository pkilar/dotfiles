# Repository layout and the single VERSION file

How packaging is *organised* in a repo, as distinct from how any one recipe is
written. Settle this once per project; retrofitting it means touching every
format at once.

The layout below is a golden standard drawn from a working three-format project.
Its value is not aesthetic: each rule below exists to make a specific class of
drift impossible rather than merely discouraged.

## Contents

- [The layout](#the-layout)
- [Three tiers, one tree](#three-tiers-one-tree)
- [VERSION is the only place the version is written](#version-is-the-only-place-the-version-is-written)
- [The build entry points](#the-build-entry-points)
- [Staging a source snapshot](#staging-a-source-snapshot)
- [What legitimately differs per format](#what-legitimately-differs-per-format)
- [Auditing an existing repo against this](#auditing-an-existing-repo-against-this)

## The layout

```
VERSION                          # one line, no leading "v". The single source of truth.
packaging/
├── rpm/
│   ├── <name>.spec
│   ├── build-rpm.sh             # entry point
│   ├── <pkg>.service            # per-format: env-file path differs
│   └── <pkg>.sysconfig          # RPM env-file convention
├── debian/
│   ├── control  rules  changelog  copyright  source/format
│   ├── build-deb.sh             # entry point
│   ├── <pkg>.service
│   ├── <pkg>.sysusers  <pkg>.tmpfiles
│   ├── <pkg>.postinst  <pkg>.prerm  <pkg>.maintscript
│   └── <pkg>.lintian-overrides  <pkg>.README.Debian  <pkg>.docs
├── arch/
│   ├── PKGBUILD
│   ├── build-arch.sh            # entry point
│   ├── <pkg>.service
│   ├── <pkg>.install
│   └── <pkg>.sysusers  <pkg>.tmpfiles
├── audit-rules/                 # SHARED: consumed by all three formats
└── profile.d/                   # SHARED: consumed by all three formats
```

Build trees are generated, never committed:

```gitignore
/rpmbuild/
/debbuild/
/archbuild/
```

Two properties do the work. **Everything packaging-related is under
`packaging/`** — nothing scattered at the repo root, so "what does this project
ship?" has one answer. And **anything used by more than one format lives in its
own sibling directory**, not duplicated into each format's folder.

## Three tiers, one tree

| Tier | Lives in | Rule |
|---|---|---|
| Shared payload | `packaging/<asset-kind>/` | One copy. Every format's recipe installs *this* path. |
| Format recipes | `packaging/<format>/` | Only what genuinely differs between formats. |
| Entry points | `packaging/<format>/build-<format>.sh` | Same shape in each format. |

The shared tier is the one people skip, and skipping it is how three packagings
silently diverge. A `profile.d` snippet or an auditd rule copied into
`packaging/rpm/`, `packaging/debian/`, and `packaging/arch/` will be edited in
one and forgotten in the other two — the diff looks complete, review passes, and
exactly one group of users gets the fix.

Keep one copy and have each recipe reference it by the same repo-relative path:

```
# rpm/<name>.spec
install -D -m 0644 packaging/audit-rules/61-foo.rules %{buildroot}/etc/audit/rules.d/61-foo.rules
# debian/rules
	install -D -m 0644 packaging/audit-rules/61-foo.rules debian/foo/etc/audit/rules.d/61-foo.rules
# arch/PKGBUILD
    install -Dm644 packaging/audit-rules/61-foo.rules "$pkgdir/etc/audit/rules.d/61-foo.rules"
```

Now a change to that file reaches all three by construction, and
`scripts/parity-check.sh` has far less to find.

## VERSION is the only place the version is written

A single top-level `VERSION` containing one line and nothing else:

```
0.10.5
```

No `v` prefix — that belongs on the git tag, not here. (For a Go module the tag
*must* be `vX.Y.Z`, since Go's module resolver ignores unprefixed tags. The file
and the tag are allowed to differ in exactly this way.)

Every format's version field is then **derived**, never typed:

| Format | Field | How it is injected |
|---|---|---|
| RPM | `Version:` | `rpmbuild --define "rpm_version ${VERSION}"`, with an in-spec fallback so a bare `rpmbuild` still parses |
| Debian | top `changelog` entry | `sed -i "1s/^${PKG} (.*)/${PKG} (${VERSION})/"` on the **staged** changelog |
| Arch | `pkgver=` | `sed -i "s/^pkgver=.*/pkgver=${VERSION}/"` on the **staged** PKGBUILD |

Read it with whitespace stripped, so a trailing newline cannot leak into a
version string:

```sh
VERSION="$(tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION")"
```

**Rewrite, do not cross-check.** Debian's changelog and Arch's `pkgver` are
authoritative to their own tooling, so they *can* disagree with `VERSION`. A
build that merely warns on mismatch still lets a wrong version ship when someone
ignores the warning. Rewriting them in the staged copy makes disagreement
structurally impossible, and leaves the committed files as placeholders that are
obviously not hand-maintained.

Note the rewrite targets the **staging directory**, not the working tree. The
committed `PKGBUILD` keeps a placeholder `pkgver`; the build never dirties the
repo. The one cost is that a committed `.SRCINFO` would go stale — regenerate it
in the build script, or don't commit it.

Bumping a release is then a one-line edit to `VERSION`, plus the changelog prose
each format wants for humans.

## The build entry points

One script per format, same shape, so a contributor who has run one can run all
three:

```
packaging/rpm/build-rpm.sh
packaging/debian/build-deb.sh
packaging/arch/build-arch.sh
```

Each one:

1. Resolves `PROJECT_ROOT` independently of the caller's working directory.
2. Reads `VERSION`.
3. Stages a source snapshot into a gitignored build tree.
4. Injects the version into that format's field.
5. Runs the native builder (`rpmbuild` / `dpkg-buildpackage` / `makepkg`).
6. Prints the artefact paths it produced.

Document the prerequisites in a header comment, and **list every tool the script
actually calls** — including ones only reached on a fallback path. A `rsync` or
`tar` invoked solely in an else-branch is exactly the dependency nobody has
installed on the day that branch is taken.

## Staging a source snapshot

Build from a snapshot, not the live tree, so builds are reproducible and cannot
be polluted by local scratch files:

```sh
if git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "${PROJECT_ROOT}" archive --format=tar HEAD | tar -x -C "${STAGING}/${TARBALL}"
    # git archive only sees committed content. Overlay the packaging tree and
    # VERSION so an uncommitted packaging change is still what gets built --
    # otherwise you debug a recipe you are not actually building.
    cp -a "${PROJECT_ROOT}/packaging/." "${STAGING}/${TARBALL}/packaging/"
    cp -a "${PROJECT_ROOT}/VERSION"     "${STAGING}/${TARBALL}/VERSION"
else
    rsync -a --exclude='.git' --exclude='rpmbuild' "${PROJECT_ROOT}/" "${STAGING}/${TARBALL}/"
fi
```

Three traps in that snippet, all of which have bitten real projects:

- **`cp -a packaging/.` not `cp -a packaging`.** The second form nests the tree
  as `packaging/packaging/` when the destination already exists. Copy the
  *contents*.
- **The git branch is silently skipped when git refuses the tree.** Running as
  root over a bind-mounted checkout trips git's `safe.directory` guard, so
  `rev-parse` fails and the fallback runs — needing a tool the prerequisites
  never mentioned. In containers, set `git config --global --add safe.directory '*'`.
- **`git archive HEAD` misses uncommitted work.** That is why the overlay
  exists. Without it, "I fixed the spec but the build still fails" is a
  guaranteed half hour.

## What legitimately differs per format

Do not over-share. These differ because the distributions differ, and forcing
them into one file makes the packaging wrong somewhere:

| Concern | RPM | Debian | Arch |
|---|---|---|---|
| Env file path | `/etc/sysconfig/<pkg>` | `/etc/default/<pkg>` | `/etc/conf.d/<pkg>` |
| Helper scripts | `/usr/libexec/<pkg>/` | `/usr/lib/<pkg>/` | `/usr/lib/<pkg>/` |
| nologin shell | `/sbin/nologin` | `/usr/sbin/nologin` | `/usr/bin/nologin` |
| Unit enable policy | preset-driven | enabled by default | never enabled |

Because the unit files carry `EnvironmentFile=`, they inherit that path
difference and must be per-format. Keep them per-format but otherwise
**identical** — if the hardening stanzas drift between them, that is drift, not
a distro difference.

## Auditing an existing repo against this

A quick pass that finds most layout problems:

```sh
# 1. Is anything packaging-related outside packaging/?
git ls-files | grep -iE '\.spec$|^debian/|PKGBUILD|\.service$|\.sysusers$|\.tmpfiles$' | grep -v '^packaging/'

# 2. Is any asset duplicated across formats? (identical content, several paths)
find packaging -type f -exec md5sum {} + | sort | uniq -w32 -d

# 3. Does the version appear anywhere it should be derived?
grep -rnE '^(Version:|pkgver=)' packaging/ ; head -1 packaging/debian/changelog ; cat VERSION

# 4. Are the build trees ignored?
git check-ignore -v rpmbuild debbuild archbuild

# 5. Do all three entry points exist and run from any directory?
ls packaging/*/build-*.sh
```

Findings worth acting on, in order of what they cost a user: a hardcoded version
that has drifted from `VERSION`; a shared asset duplicated per format; a build
tree committed to git; packaging files living outside `packaging/`; missing or
inconsistent entry points.

If the project ships only one format today, the layout still applies — a single
`packaging/rpm/` costs nothing now and means adding Debian later is additive
rather than a restructuring.

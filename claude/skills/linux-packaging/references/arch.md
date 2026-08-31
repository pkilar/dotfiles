# Arch packaging (PKGBUILD)

Covers authoring and auditing a `PKGBUILD`. Cross-distro concerns — version
ordering, config semantics, service users, unit policy — are in
[`cross-distro.md`](cross-distro.md).

Arch is the least ceremonious of the three formats and the most likely to be
packaged by transliterating a `.spec`. Resist that: several things RPM makes you
do explicitly, pacman does for you, and doing them anyway is a defect.

## Contents

- [Shape of a PKGBUILD](#shape-of-a-pkgbuild)
- [Split packages](#split-packages)
- [Config files: backup=()](#config-files-backup)
- [Users, state, and units — pacman does more than you think](#users-state-and-units--pacman-does-more-than-you-think)
- [Build conventions](#build-conventions)
- [High-frequency bugs](#high-frequency-bugs)
- [Verification](#verification)
- [namcap triage](#namcap-triage)

## Shape of a PKGBUILD

Four functions, run in order, each with a distinct job:

| Function | Job | Network |
|---|---|---|
| `prepare()` | Patch, and fetch language-level dependencies | Yes |
| `build()` | Compile | Should not need it |
| `check()` | Run the test suite | No |
| `package()` | **Install only.** Nothing is compiled here | No |

Putting a compile step in `package()` is the classic mistake — it breaks
`makepkg --repackage` and means `check()` tested something other than what
shipped. Keeping module downloads in `prepare()` also makes an offline build
fail at an obvious place rather than deep inside compilation.

Everything is a bash script, so quoting matters: always `"$pkgdir"` and
`"$srcdir"`, never bare. Use `install -Dm<mode>` with an explicit mode rather
than `cp` — it creates parents and sets permissions in one step.

## Split packages

One `pkgbase`, a `pkgname` array, and a `package_<name>()` function per entry:

```bash
pkgbase=beacond
pkgname=('beacond' 'beacond-client')
arch=('x86_64' 'aarch64')
makedepends=('go')

package_beacond() {
    pkgdesc="Heartbeat daemon"
    depends=('glibc')
    backup=('etc/beacond/beacond.yaml')
    install -Dm755 "$srcdir/bin/beacond" "$pkgdir/usr/bin/beacond"
}

package_beacond-client() {
    pkgdesc="Client for beacond"
    arch=('any')          # override: pure shell, no compiled content
    depends=('bash' 'curl')
    install -Dm755 "$srcdir/client/beacon-status" "$pkgdir/usr/bin/beacon-status"
}
```

Two things bite here.

**Only some variables are overridable per package.** `pkgdesc`, `arch`,
`license`, `depends`, `optdepends`, `provides`, `conflicts`, `replaces`,
`backup`, `options`, `install`, `changelog`, `groups`, `url` can be set inside
a `package_*()`. `makedepends`, `source`, and the checksum arrays are global
only. Anything you set globally and don't override **leaks into every
subpackage** — a global `depends` is the usual accident.

**`--syncdeps` only reads the global arrays.** Per-package `depends` are
metadata for the built package; they are not consulted when deciding what to
install to *build*. So anything `build()` needs must be in global
`makedepends`. namcap reports the gap as an error; the correct response is
usually to confirm the build genuinely doesn't need those runtime libraries,
not to promote them into `makedepends` and misstate the build requirements.

## Config files: `backup=()`

Paths are **relative and have no leading slash**, and the array is per-package:

```bash
backup=('etc/beacond/beacond.yaml')     # not '/etc/beacond/beacond.yaml'
```

A file in `backup=()` that the admin has edited gets left alone on upgrade and
the new version lands as `.pacnew`. A file **not** in `backup=()` is overwritten
unconditionally — which is exactly right for code (a `profile.d` snippet) and
catastrophic for config.

Audit this mechanically: list every `install -D … "$pkgdir/etc/…"` line and
check each against `backup=()`. Drop-in fragments are the ones people forget —
`etc/audit/rules.d/*`, `etc/cron.d/*`, `etc/sudoers.d/*` have no vendor/override
split, so if you ship a default straight into `/etc` it must be backed up or the
admin's edits die silently on the next upgrade.

Files with a `/usr/lib` vendor path and an `/etc` override — systemd units,
`sysusers.d`, `tmpfiles.d` — never need `backup=()`. Ship them to `/usr/lib`.

And remember pacman **never prompts and never announces** a `.pacnew`. If your
package ships config likely to drift, say so in the install message.

## Users, state, and units — pacman does more than you think

This is where a transliterated `.spec` goes wrong.

**Users.** Ship a `sysusers.d` fragment to `/usr/lib/sysusers.d/<name>.conf`.
The `systemd` package installs a pacman hook that runs `systemd-sysusers`
automatically. Calling `systemd-sysusers` yourself from an `.install` scriptlet
is redundant, and namcap flags it: `.INSTALL file runs a command
(systemd-sysusers) provided by hooks`. The same goes for `systemd-tmpfiles` and
for `systemctl daemon-reload`.

Note Arch is merged-`/usr`: the nologin shell is `/usr/bin/nologin`, not
`/sbin/nologin`.

**State.** `tmpfiles.d` fragment to `/usr/lib/tmpfiles.d/<name>.conf`. Use type
`d`, not `D`, unless you actually want contents purged.

**Units.** Install to `/usr/lib/systemd/system/`, never `/etc/systemd/system/`.
**Never enable or start anything.** Arch does not use presets and packages do
not auto-enable services — this is settled policy, not a style preference. An
`.install` scriptlet that prints "run `systemctl enable beacond`" is the correct
shape; one that runs it is a bug.

`.install` scriptlets should therefore be nearly empty: operator guidance in
`post_install`, and often a literal no-op `post_upgrade`. That is normal, not a
smell.

**Helper binaries** go in `/usr/lib/<pkgname>/`. Arch does not use
`/usr/libexec/` — that is an RPM convention.

## Build conventions

```bash
build() {
    cd "$srcdir/$pkgbase"
    export CGO_ENABLED=0
    export GOFLAGS="-buildmode=pie -trimpath -mod=readonly -modcacherw"
    export GOPATH="$srcdir/gopath" GOCACHE="$srcdir/gocache"
    go build -ldflags "-X main.version=$pkgver" -o bin/beacond ./cmd/beacond
}
```

`CGO_ENABLED=0` with `-buildmode=pie` gets you PIE hardening through Go's own
linker with no C toolchain. The `CGO_CFLAGS`/`-linkmode=external` plumbing in
Arch's Go guidelines only matters when cgo is actually on — see
[`languages.md`](languages.md) for what hardening flags do and don't apply to a
Go binary.

Confine `GOPATH` and `GOCACHE` to `$srcdir` so a build cannot scribble on the
user's home directory.

`license=('MIT')` uses the SPDX identifier — but MIT and BSD are *not* covered
by the shared `licenses` package, so you must still install the text yourself
to `/usr/share/licenses/$pkgname/LICENSE`, in every subpackage that needs it.

For a locally generated tarball rather than a real upstream URL, `SKIP` in
`sha256sums=()` is the honest answer — the artifact is regenerated per build and
cannot be pinned. Real upstream sources get a real URL and a real checksum.

## High-frequency bugs

| Bug | Symptom | Fix |
|---|---|---|
| `~` used for a pre-release | `1.0~rc1` sorts **newer** than `1.0`; upgrade never arrives | Use `1.0rc1` — see [`cross-distro.md`](cross-distro.md) |
| Config file missing from `backup=()` | Admin's edits silently destroyed on upgrade, no `.pacnew` | Audit every `/etc` install against `backup=()` |
| Manual `systemd-sysusers`/`tmpfiles`/`daemon-reload` in `.install` | Redundant; namcap error | Delete it; the hooks handle it |
| Enabling or starting a unit | Violates Arch policy | Print instructions instead |
| Global `depends` leaking into every subpackage | Client package drags in the daemon's libraries | Set `depends` per `package_*()` |
| Compiling in `package()` | `--repackage` breaks; `check()` tested something else | Compile in `build()` |
| Missing `arch=('any')` override | Pure-shell package built per-architecture | Override inside its `package_*()` |
| Hardcoded `x86_64` | Wrong on aarch64 | `$CARCH` — except in `case` patterns, which must be literal |
| `/usr/libexec` | Wrong convention for Arch | `/usr/lib/<pkgname>/` |
| License text not installed | MIT/BSD aren't covered by `licenses` | `install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"` |

## Verification

`makepkg` refuses to run as root by design, so a container build needs an
unprivileged user:

```sh
# Native, on an Arch host
cd packaging/arch && makepkg -sf --noconfirm

# Containerised
podman run --rm -v "$PWD":/src:ro archlinux:base-devel bash -c '
  pacman -Syu --noconfirm --needed base-devel go namcap
  useradd -m builder; cp -a /src /build; chown -R builder /build
  runuser -u builder -- bash -lc "cd /build/packaging/arch && makepkg -sf --noconfirm"'

# Inspection
namcap PKGBUILD                       # the recipe
namcap ./*.pkg.tar.zst                # the built package — do both
pacman -Qip ./pkg.tar.zst             # metadata, including backup entries
pacman -Qlp ./pkg.tar.zst             # file list
bsdtar xOf ./pkg.tar.zst .PKGINFO | grep '^backup'   # what actually got backed up
bsdtar xOf ./pkg.tar.zst .INSTALL     # the scriptlet, as shipped
```

`scripts/verify-package.sh --format arch` handles the unprivileged-user dance
and runs through the upgrade test, which is the only thing that actually proves
`backup=()` is complete.

## namcap triage

Three findings recur and mean different things:

- **`E: Split PKGBUILD needs additional makedepends [...]`** — real, and usually
  correct in mechanism: those packages are in a subpackage's `depends` but not
  in global `makedepends`. Check whether `build()` genuinely needs them. With
  `CGO_ENABLED=0` it typically does not, and the honest resolution is to record
  why rather than to inflate `makedepends`.
- **`W: Reference to x86_64 should be changed to $CARCH`** — often a false
  positive. namcap matches textually, so a `case "$CARCH" in x86_64) …` block
  trips it even though a `case` pattern *must* be a literal. Check whether the
  match is a pattern before "fixing" it.
- **`W: ELF file lacks FULL RELRO`** — expected for a Go binary built with the
  internal linker. Not a defect; see [`languages.md`](languages.md).

- **`W: .INSTALL file runs a command (systemd-sysusers) provided by hooks`** —
  the underlying rule is real (pacman's hooks already run those tools, so
  calling them yourself is redundant), but the check is textual and fires on a
  mere *mention*. A scriptlet whose comment says "the user is created by
  systemd-sysusers via pacman's own hook" trips it while doing nothing wrong.
  Open the `.install` and confirm there is an actual invocation before changing
  anything.

Everything else deserves a look.

**namcap has no per-finding suppression.** Unlike rpmlint's config filters and
lintian's override files, namcap offers only `-e/--exclude RULELIST` and
`-r/--rules RULELIST`, which disable or select whole rule *modules* globally.
There is no way to justify-and-silence one finding on one package. So the honest
options are to fix it, or to record the reasoning outside the tooling — do not
plan on an inline override that does not exist.

## .install scriptlet arguments

Each function receives version strings positionally — a third convention,
different from both RPM's numeric counts and Debian's verb-plus-version:

| Function | Arguments |
|---|---|
| `post_install` | new version |
| `post_upgrade` | new version, old version |
| `pre_remove` / `post_remove` | current version |

Because the upgrade case has its own function, there is no argument-sniffing to
get wrong — but it does mean `post_upgrade` must explicitly call `post_install`
if you want shared behaviour.

### A failing `pre_remove` does not stop the removal

This is the one that catches people who have written Debian or RPM packaging
first. dpkg aborts on a failing `prerm` and rpm aborts on a failing `%preun`;
**pacman does neither**. It prints `error: command failed to execute correctly`,
removes the package anyway, and exits `0`. A guard that refuses a dangerous
removal is therefore advisory on Arch and enforcing on the other two, which is
exactly the sort of asymmetry that ships unnoticed.

To actually veto a transaction, install a `PreTransaction` hook with
`AbortOnFail` into `/usr/share/libalpm/hooks/` — see
[`cross-distro.md`](cross-distro.md#a-failing-scriptlet-does-not-stop-every-package-manager)
for the hook, the reason it must be side-effect free, and the trap in overriding
it.

# Debian packaging (Debian, Ubuntu, derivatives)

Covers authoring and auditing a `debian/` tree. Cross-distro concerns — version
ordering, config semantics, service users, unit policy — are in
[`cross-distro.md`](cross-distro.md).

Debian's distinguishing feature is how much debhelper does implicitly. That is
mostly a gift, but it means the important questions are "what did `dh` decide on
my behalf, and did I want that?" — and the answers are frequently not visible
anywhere in the `debian/` directory you wrote.

## Contents

- [The tree](#the-tree)
- [control](#control)
- [Every /etc file is a conffile](#every-etc-file-is-a-conffile)
- [rules and the dh sequence](#rules-and-the-dh-sequence)
- [Maintainer scripts](#maintainer-scripts)
- [High-frequency bugs](#high-frequency-bugs)
- [Verification](#verification)
- [lintian triage](#lintian-triage)

## The tree

| File | Purpose |
|---|---|
| `control` | Source stanza + one stanza per binary package |
| `rules` | Executable makefile; `%: dh $@` plus targeted overrides |
| `changelog` | Version comes from here — the top entry is authoritative |
| `copyright` | Machine-readable format 1.0. For an official upload this is a real per-file licence audit |
| `source/format` | `3.0 (quilt)` for upstream + packaging, `3.0 (native)` when they are the same tree |
| `<pkg>.install` / `.dirs` / `.docs` | What lands where |
| `<pkg>.service` / `.sysusers` / `.tmpfiles` | Picked up by name — no wiring needed beyond invoking the right helper |
| `<pkg>.postinst` / `.prerm` / … | Maintainer scripts; debhelper injects its own code at `#DEBHELPER#` |
| `<pkg>.maintscript` | Declarative conffile removal/rename |
| `<pkg>.lintian-overrides` | Suppressions, each of which you must be able to defend |

Declare the compat level as `Build-Depends: debhelper-compat (= 13)`. A
`debian/compat` file is no longer accepted. If you need a feature added in a
point release *within* a compat level, add a second `Build-Depends: debhelper
(>= 13.6~)` — that combination is intentional, not redundant.

## control

```
Source: beacond
Section: net
Priority: optional
Maintainer: Real Name <email>
Build-Depends: debhelper-compat (= 13), golang-go (>= 1.22)
Standards-Version: 4.7.4
Rules-Requires-Root: no

Package: beacond
Architecture: any
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: Heartbeat daemon
 Longer description, indented one space.

Package: beacond-client
Architecture: all
Depends: ${misc:Depends}, bash, curl
Description: Client for beacond
```

**Verify every dependency name against the actual target archive.** This is the
single highest-value check in this file and it takes one command:

```sh
apt-cache policy auditd    # a real package
apt-cache policy audit     # nothing — this is the Arch name
```

Package names differ across distributions, and a name copied from a `.spec` or
`PKGBUILD` produces a package that builds cleanly, lints cleanly, and cannot be
installed. Nothing short of an install attempt catches it.

**`${shlibs:Depends}` belongs on every package shipping an ELF binary**, even a
fully static one. Below compat 14 an unreferenced substvar simply never lands,
so `dh_shlibdeps` runs, computes nothing useful, and the omission is invisible —
until the binary stops being static and the real library dependency is silently
dropped instead of declared.

`Architecture: any` for compiled binaries, `all` for architecture-independent
content. They cannot share a package.

## Every /etc file is a conffile

`dh_installdeb` registers **every** file staged under `debian/<pkg>/etc/` as a
conffile automatically. There is no per-file opt-out — a `<pkg>.conffiles` file
can only add entries.

For real configuration this is exactly right. For *code* under `/etc` — a
`profile.d` snippet, a helper script you need to keep fixing — it is a problem:
the file will auto-update only while nobody has edited it, and the moment an
admin touches it your fixes stop arriving, silently, as `.dpkg-dist` files
nobody reads.

The cleanest fix is a symlink, because conffile registration only applies to
regular files:

```sh
# debian/<pkg>.install
usr/lib/<pkg>/foo.sh

# debian/<pkg>.links
usr/lib/<pkg>/foo.sh etc/profile.d/foo.sh
```

Verified: the resulting package ships `/etc/profile.d/foo.sh` and has an **empty**
conffiles list, so the link and its target both update on every upgrade. No
maintainer-script code needed.

Copying the file into place from `postinst` achieves the same thing with more
moving parts, and is worth knowing when a symlink is unacceptable:

```sh
# debian/<pkg>.postinst
set -e
cp /usr/lib/<pkg>/foo.sh /etc/profile.d/foo.sh
#DEBHELPER#
```

To stop an already-shipped file being a conffile, use `debian/<pkg>.maintscript`
with `rm_conffile <path> <last-version-with-it>~ <pkg>`. dpkg will not drop it
on its own, because a conffile vanishing from a package is indistinguishable
from a packaging accident.

Accepting conffile semantics is also a legitimate choice — just write the
consequence into `README.Debian` so it is a decision rather than a discovery.

## rules and the dh sequence

```make
#!/usr/bin/make -f
export DH_VERBOSE = 1
export GOFLAGS = -trimpath -mod=vendor
export GOPROXY = off

%:
	dh $@

override_dh_auto_build:
	go build $(GOFLAGS) -ldflags "-X main.version=$(VERSION)" -o bin/beacond ./cmd/beacond

# dh_installsysusers is NOT in the default sequence until compat 14. Call it
# explicitly, and before anything that chowns a path to the account it creates.
override_dh_installtmpfiles:
	dh_installsysusers
	dh_installtmpfiles

override_dh_installsystemd:
	dh_installsystemd --no-enable --no-start
```

**Check the compat-level changelog rather than assuming.** New helpers ship as
opt-in commands for a release or two before joining the default sequence.
`dh_installsysusers` at compat 13 is the current example; there will be others.
`dh $@ --with installsysusers` is the other way to opt in, and reads better than
an override that calls it by hand. Confirm which commands your compat level
actually runs rather than inferring it:

```sh
grep -n 'installsysusers' /usr/share/perl5/Debian/Debhelper/Sequence/root_sequence.pm
#  51:	$include_if_compat_X_or_newer->(14, 'dh_installsysusers'),
```

**dh decides which commands to skip BEFORE `debian/rules` runs**, based on which
input files exist at that moment. So a helper input generated from a rules hook
is always too late:

```make
# Does nothing. dh already decided to skip dh_installsysusers, because
# debian/mypkg.sysusers did not exist when it planned the sequence.
execute_before_dh_installsysusers:
	install -m 0644 packaging/sysusers/mypkg.conf debian/mypkg.sysusers
```

The file lands, the command never runs, and the only symptom is a missing
service account at install time. Generate such files in the **build script,
before `dpkg-buildpackage` is invoked** — which is natural if you already stage
a source snapshot (see `repo-layout.md`). For the same reason, do not delete
them in `clean`: `dpkg-buildpackage` runs `debian/rules clean` first, so that
puts the file back out of scope before the binary target plans.

This is the same trap in a different costume as `dh_shlibdeps` above: debhelper
is driven by what is on disk at a particular instant, and "I generated it" is
not the same as "it was there when it mattered."

**Read what a flag actually does, not what its name suggests.**
`dh_installsystemd --no-start` suppresses the restart *after upgrades* as well as
the start on first install. If you pass it, the service will not come back after
an upgrade unless you write that yourself — which is why a hand-rolled
`try-restart` block below `#DEBHELPER#` in a `postinst` is often load-bearing
rather than redundant. Check before you "simplify" one away.

## Maintainer scripts

Every script starts `set -e` and contains `#DEBHELPER#` on its own line, where
debhelper injects its generated code.

```sh
#!/bin/sh
set -e

#DEBHELPER#

# Runs on upgrade and reinstall, not on fresh install: $2 is the old version.
if [ "$1" = configure ] && [ -n "$2" ]; then
    if [ -d /run/systemd/system ]; then
        systemctl --quiet try-restart beacond.service || true
    fi
fi
```

The four paths that need thinking about, because they behave differently:

| Action | What must happen |
|---|---|
| install | Create user, create dirs, do not assume anything pre-exists |
| upgrade | Preserve state; restart only if the service was already running |
| remove | Stop the service. Config files stay |
| purge | Config files go. The user account **stays** — files it owns may not |

The remove path is the one that gets skipped. If you passed `--no-start`/
`--no-enable`, debhelper may generate no `prerm` at all, so a service an admin
enabled by hand keeps running against a deleted binary after `apt remove`. Either
add a `prerm` that stops it, or verify that one was generated.

Guard systemd calls with `[ -d /run/systemd/system ]` so they no-op in
containers and chroots.

## High-frequency bugs

| Bug | Symptom | Fix |
|---|---|---|
| Dependency name from another distro | Builds and lints clean; **cannot install** | `apt-cache policy <name>` against the real target |
| Missing `${shlibs:Depends}` | Silent dependency loss if the binary stops being static | Add it to every `Architecture: any` package |
| Code file under `/etc` | Fixes stop reaching anyone who edited it | Ship under `/usr/lib`, copy in `postinst` |
| `dh_installsysusers` not called at compat 13 | User missing; chowns fail | Explicit call in `rules`, before the chown |
| `--no-start` without a manual restart | Service stays down after every upgrade | Hand-written `try-restart` in `postinst` |
| No `prerm` | Service survives `apt remove`, running a deleted binary | Add one, or stop passing the flag that suppressed it |
| `dh_fixperms` resetting a deliberate mode | 0640 secret becomes 0644 | `dh_fixperms -X<path>` for every such file |
| `dh_dwz` on a Go binary | **Build aborts** — dwz refuses Go's compressed DWARF | empty `override_dh_dwz:` |
| Missing `#DEBHELPER#` | Generated code never runs; nothing works and nothing errors | One per maintainer script, on its own line |
| `3.0 (native)` shipped to an archive | Version scheme has no debian revision | Use `3.0 (quilt)` with a real orig tarball |

## Verification

```sh
podman run --rm -v "$PWD":/src:ro golang:1.26-bookworm bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # build-essential is required even for pure Go: dpkg-checkbuilddeps enforces
  # it implicitly whether or not control lists it.
  apt-get install -y -qq --no-install-recommends \
      build-essential debhelper devscripts lintian dpkg-dev git make ca-certificates
  git config --global --add safe.directory "*"
  cp -a /src /build && cd /build
  dpkg-buildpackage -us -uc -b
  lintian --tag-display-limit 0 ../*.deb
  apt-get install -y --no-install-recommends ../*.deb'   # note the ./ or ../ — apt
                                                          # rejects a bare filename

# Inspection
dpkg-deb -I pkg.deb conffiles       # what dpkg will protect on upgrade
dpkg-deb -c  pkg.deb                # files, modes, owners
dpkg-deb -e  pkg.deb ./ctrl && cat ./ctrl/p*    # the generated maintainer scripts
dpkg-parsechangelog -l debian/changelog          # changelog syntax and dates
```

Reading the *generated* maintainer scripts is worth doing at least once per
project. They are where debhelper's implicit decisions become visible, and they
routinely contain neither what you expected nor what you feared.

`scripts/verify-package.sh --format deb` runs build → lint → install → upgrade.
Pass `--image golang:1.26-bookworm` (or similar) when the project needs a
toolchain newer than the base image ships.

## lintian triage

Run it on the built `.deb`, not the source tree. Two flags matter:

```sh
lintian --tag-display-limit 0 pkg.deb    # don't silently truncate repeats
lintian --no-override        pkg.deb    # see what your overrides are hiding
```

The `--no-override` run is the honest one. An override you cannot justify after
seeing the tag's own explanation is a bug you have hidden from yourself — and
the way to justify one properly is to show the tag's suggested fix is
nonsensical for your case, not merely to assert "false positive". A static Go
binary flagged as a shared library lacking prerequisites qualifies: the tag's own
advice is to link against libc, which is meaningless here.

`no-manual-page` is real but low-stakes for self-hosted packages; either ship a
man page or override it deliberately rather than leaving it to accumulate.

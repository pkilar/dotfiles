# Cross-distro semantics

The differences that make multi-distro packaging hard are not syntax. They are
places where the same intent requires *opposite* encodings, so carrying one
distro's idiom into another silently produces a bug. This file is the set of
those places.

## Contents

- [Version ordering — the tilde is not portable](#version-ordering--the-tilde-is-not-portable)
- [Config vs code under /etc](#config-vs-code-under-etc)
- [Service users](#service-users)
- [State directories](#state-directories)
- [Unit enable, start, and restart policy](#unit-enable-start-and-restart-policy)
- [Environment files](#environment-files)
- [Build isolation](#build-isolation)
- [A failing scriptlet does not stop every package manager](#a-failing-scriptlet-does-not-stop-every-package-manager)
- [Equivalence cheat-sheet](#equivalence-cheat-sheet)

## Version ordering — the tilde is not portable

Every guide tells you to write a pre-release as `1.0~rc1`. That advice is
correct for RPM and Debian and **actively wrong for Arch**, where it produces
the exact upgrade-blocking bug it was meant to prevent.

Measured directly with `rpmdev-vercmp`, `dpkg --compare-versions`, and `vercmp`.
Each cell answers: does the release candidate sort *older* than the final `1.0`?

| Encoding | RPM | Debian | Arch |
|---|---|---|---|
| `1.0rc1` | ✗ newer | ✗ newer | **✓ older** |
| `1.0~rc1` | **✓ older** | **✓ older** | ✗ newer |
| `1.0.rc1` | ✗ newer | — | ✗ newer |
| `1.0_rc1` | — | — | ✗ newer |
| `1.0^git…` | ✓ sorts after | **syntax error** | (treated as a plain separator) |

So the correct encoding of "1.0 RC1" is genuinely different per format:

```
RPM      Version: 1.0~rc1     Release: 1%{?dist}
Debian   1.0~rc1-1
Arch     pkgver=1.0rc1        pkgrel=1
```

**Why.** dpkg and modern rpm both special-case `~` to sort before everything,
including the empty string. pacman's `vercmp` is descended from a pre-tilde rpm
and never gained that rule, so `~` is just an ordinary separator — but it *did*
gain a different rule, that a trailing alphabetic segment sorts older than
nothing, which is why the bare `1.0rc1` form works there and only there.

**What it costs you.** A user who installs the RC gets stuck on it forever. The
package manager sees the installed version as newer than the published final
release, reports nothing to upgrade, and gives no error. Nobody notices until
someone asks why a fleet is still on an RC.

Never take this from memory — including from this file. It takes seconds to
check, and the check is the same shape everywhere:

```sh
vercmp 1.0rc1 1.0                        # Arch:   <0 means rc is older (good)
dpkg --compare-versions 1.0~rc1 lt 1.0   # Debian: exit 0 means rc is older
rpmdev-vercmp 1.0~rc1 1.0                # RPM:    prints which side is newer
```

Two rules that *do* generalise: a packaging-only rebuild bumps the second
number (`Release`, `debian_revision`, `pkgrel`) and never the version; and an
epoch is a one-way door — once set it can never be removed or lowered, so
exhaust every encoding above before reaching for it.

## Config vs code under /etc

Both kinds of file live in `/etc`, and they want opposite upgrade behaviour:

- **Config** — the admin edits it. Their edits must survive an upgrade.
- **Code** — a `profile.d` snippet, a helper script. It must be *replaced* on
  upgrade or bug fixes never reach anyone.

RPM and Arch let you express both. **Debian does not**: `dh_installdeb`
registers every file staged under `/etc` as a conffile automatically, and there
is no per-file opt-out — a `debian/<pkg>.conffiles` file can only add entries.

| Intent | RPM | Debian | Arch |
|---|---|---|---|
| Config: preserve site edits | `%config(noreplace)` → new lands as `.rpmnew` | automatic; prompts, or `.dpkg-dist` under `--force-confold` | list in `backup=()` → new lands as `.pacnew` |
| Code: always replace | ship it unmarked | **not directly expressible** — see below | omit from `backup=()` |

**The cleanest Debian workaround is a symlink.** Conffile registration only
applies to *regular files*, so shipping the real content under `/usr/lib` and
linking to it from `/etc` escapes it entirely — with no maintainer-script code
at all:

```sh
# debian/<pkg>.install
usr/lib/<pkg>/foo.sh

# debian/<pkg>.links
usr/lib/<pkg>/foo.sh etc/profile.d/foo.sh
```

Verified: a package built this way ships `/etc/profile.d/foo.sh` and reports an
**empty** conffiles list, so both the link and its target are replaced on every
upgrade — exactly the semantics RPM gets by leaving the file unmarked.

A `postinst` that copies the file into place works too and is worth knowing,
but it is strictly more machinery for the same result:

```sh
# debian/<pkg>.postinst
set -e
cp /usr/lib/<pkg>/foo.sh /etc/profile.d/foo.sh
#DEBHELPER#
```

To *stop* an already-shipped file being a conffile, `debian/<pkg>.maintscript`
with `rm_conffile <path> <last-version-that-had-it>~ <pkg>` — dpkg will not
remove it silently on its own.

The honest alternative is to accept conffile semantics on Debian and write the
consequence down in `README.Debian`: the file auto-updates only while nobody
has touched it. That is a legitimate choice; leaving it *accidental* is not.

Two related traps:

- On upgrade, an **unmodified** config file is silently replaced on all three —
  no suffix, no prompt. The `.rpmnew`/`.dpkg-dist`/`.pacnew` machinery only
  engages once the admin has actually edited the file.
- **pacman never prompts and never tells you** a `.pacnew` appeared. On Arch,
  say so in your post-install output or the file goes stale forever.
- A `*.example` template is arguably not config at all. If nothing reads it,
  it belongs in `/usr/share/doc`, not `/etc`.

## Service users

All three consume the same `sysusers.d` format, which makes it the portable
choice — one file, three packagings:

```
#Type Name    ID  GECOS            Home directory   Shell
u     beacon  -   "beacon daemon"  /var/lib/beacond /usr/sbin/nologin
```

| | Mechanism | Note |
|---|---|---|
| RPM | `%sysusers_create_compat` in `%pre` (or native handling on new Fedora) | Needs `systemd-rpm-macros`. The `getent … \|\| useradd -r` scriptlet is the fallback for older targets |
| Debian | `debian/<pkg>.sysusers` + `dh_installsysusers` | **Not auto-sequenced at compat 13** — call it explicitly in `debian/rules`, before anything chowns to that user |
| Arch | ship to `/usr/lib/sysusers.d/` | A pacman hook runs `systemd-sysusers` for you. Calling it yourself from `.install` is redundant and namcap flags it |

Rules that hold everywhere: creation must be idempotent (scriptlets re-run);
every distinct service account gets its **own** home directory, because two
accounts sharing one defeats the isolation that justified splitting them; and
**never delete the account on uninstall** — files it owns outlive it, and the
uid gets recycled to some unrelated future user.

Note the shell path differs: Arch is merged-`/usr` and has no `/sbin/nologin`.

## State directories

| Path | Ship as a packaged directory? | Use instead |
|---|---|---|
| `/run/<pkg>` | **Never** | `RuntimeDirectory=` in the unit, or `tmpfiles.d` |
| `/var/lib/<pkg>` | Works, but | `StateDirectory=` or `tmpfiles.d` |
| `/var/log/<pkg>` | Works, but | `LogsDirectory=` or `tmpfiles.d` |

`/run` is a tmpfs. A directory created there at install time is gone after the
first reboot, and the service fails to start with a confusing "no such file or
directory" that looks like an application bug. This one is worth internalising
because it passes every test you are likely to run and fails in production a
week later.

`tmpfiles.d` also re-asserts ownership and mode on every boot, which repairs
drift that a one-time `%dir` cannot.

## Unit enable, start, and restart policy

This is policy, not preference — the distros genuinely disagree, and matching
each one is part of packaging correctly.

| | On install | On upgrade |
|---|---|---|
| RPM | `%systemd_post` honours the distro **preset**; most services ship disabled | `%systemd_postun_with_restart` restarts only if already running |
| Debian | `dh_installsystemd` enables **and starts** by default; opt out with `--no-enable` / `--no-start` | restart-after-upgrade by default |
| Arch | never enables or starts, ever | never touches it |

Restarting a running daemon on upgrade is usually right, but not always: it
drops in-flight work, and across a fleet it restarts every node at once,
defeating a rolling upgrade. Where that matters, use the reload variant or
nothing at all — and say which you chose.

What is never right is *starting a stopped service* or *re-enabling a disabled
one*. An admin who stopped it had a reason, and a routine upgrade silently
undoing that is how maintenance windows turn into incidents.

## Environment files

Same mechanism, three locations. The leading `-` means "don't fail if absent":

| | Path | Unit line |
|---|---|---|
| RPM | `/etc/sysconfig/<pkg>` | `EnvironmentFile=-/etc/sysconfig/<pkg>` |
| Debian | `/etc/default/<pkg>` | `EnvironmentFile=-/etc/default/<pkg>` |
| Arch | `/etc/conf.d/<pkg>` | `EnvironmentFile=-/etc/conf.d/<pkg>` |

systemd parses these itself with a restricted `KEY=value` parser — it is **not**
shell. Conditionals and `$(command)` substitution that worked when an init
script sourced the file will silently misbehave here.

## Build isolation

Fedora's build system and Debian's buildds have **no network**. Any language
with a module ecosystem must vendor, or the package builds on a laptop and
fails everywhere that matters. Vendor, then force it — `-mod=vendor` plus
`GOPROXY=off` for Go — so the failure is loud and local rather than deep inside
someone else's CI. See [`languages.md`](languages.md).

Also check that declared build dependencies are actually satisfiable on the
target. A `BuildRequires: golang >= 1.26` is not a constraint if no supported
release ships it; it is an unbuildable package with a confident-looking header.

## A failing scriptlet does not stop every package manager

If a maintainer script is the thing standing between a user and a broken system,
check that its refusal is actually honoured. It is not honoured everywhere.

| | Pre-removal hook | Non-zero exit aborts removal? | Exit status |
|---|---|---|---|
| Debian | `prerm` | **Yes** — package stays installed | non-zero |
| RPM | `%preun` | **Yes** — erasure aborts | non-zero |
| Arch | `pre_remove` | **No** — prints the error, removes anyway | **0** |

pacman treats a failing `pre_remove` as advisory. It prints
`error: command failed to execute correctly`, completes the removal, and exits
`0`, so a guard written once and assumed portable is a guard that silently does
not exist on one of the three.

The only pacman mechanism that can veto a transaction is a **`PreTransaction`
hook with `AbortOnFail`** (`alpm-hooks(5)`), installed to
`/usr/share/libalpm/hooks/`:

```ini
[Trigger]
Operation = Remove
Type = Package
Target = mypkg

[Action]
Description = Checking whether it is safe to remove mypkg...
When = PreTransaction
Exec = /usr/lib/mypkg/check.sh
AbortOnFail
```

Two consequences worth designing for:

- **The hook must be side-effect free.** The transaction it vets may still be
  cancelled, so it can check and refuse but must not restore, migrate, or delete
  anything. That usually means splitting a check-only entry point out of the
  script your `pre_remove` already calls.
- **An override has to cover the whole path.** pacman cannot pass a flag through
  to a hook, so the escape hatch is an environment variable — and it must be
  honoured by *both* the hook and the removal logic. Honouring it in the hook
  alone lets the operator past the veto and straight into the failure the veto
  existed to prevent, since the removal then proceeds with the cleanup skipped.

The same asymmetry applies to install-time scriptlets: verify, per package
manager, whether a failure aborts the transaction or is merely logged, before
relying on one to enforce anything.

## Equivalence cheat-sheet

| Task | RPM | Debian | Arch |
|---|---|---|---|
| List files | `rpm -qlp F` | `dpkg-deb -c F` | `pacman -Qlp F` |
| Metadata | `rpm -qip F` | `dpkg-deb -I F` | `pacman -Qip F` |
| Dependencies | `rpm -qp --requires F` | `dpkg-deb -f F Depends` | `pacman -Qip F` |
| Config files | `rpm -qcp F` | `dpkg-deb -I F conffiles` | `.PKGINFO` `backup =` |
| Scriptlets | `rpm -qp --scripts F` | `dpkg -e F && cat DEBIAN/*` | `bsdtar xOf F .INSTALL` |
| Extract, no install | `rpm2cpio F \| cpio -idmv` | `dpkg-deb -x F out/` | `bsdtar xf F` |
| Lint | `rpmlint` | `lintian` | `namcap` |
| Arch-independent | `BuildArch: noarch` | `Architecture: all` | `arch=('any')` |
| Second version number | `Release:` | `debian_revision` | `pkgrel` |

## The same dependency is not correct everywhere

Declaring what your maintainer scripts actually use is diligence on two formats
and a policy error on the third. `coreutils` and `grep` are Essential on Debian,
so `Depends: coreutils` is `depends-on-essential-package-without-using-version`
— a lintian error — while `Requires: coreutils` on RPM and `depends=('coreutils')`
on Arch are both correct and expected.

The same applies to virtual packages: Debian will not satisfy a dependency on a
virtual name alone, so an awk dependency is `mawk | gawk | original-awk` there
and simply `gawk` on Fedora.

Resolve declared names against each target archive, and expect the *set* to
differ per format rather than assuming one list ports across.

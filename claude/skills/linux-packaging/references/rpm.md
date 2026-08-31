# RPM packaging (Fedora, RHEL, CentOS Stream, Amazon Linux, openSUSE)

Covers authoring and auditing a `.spec`. Cross-distro concerns — version
ordering, config-file semantics, service users, unit policy — are in
[`cross-distro.md`](cross-distro.md); read that too if you are packaging for
more than one format.

## Contents

- [Spec anatomy](#spec-anatomy)
- [Preamble fields](#preamble-fields)
- [%build: use the language macro](#build-use-the-language-macro)
- [Scriptlets](#scriptlets)
- [%files discipline](#files-discipline)
- [Subpackages](#subpackages)
- [High-frequency bugs](#high-frequency-bugs)
- [Verification](#verification)
- [rpmlint triage](#rpmlint-triage)

## Spec anatomy

A spec runs in phases. Knowing which phase your code is in explains most
confusing failures.

| Section | Runs | Notes |
|---|---|---|
| preamble | parse time | Metadata. Macros here are expanded before anything executes. |
| `%prep` | build host | Unpack + patch. Prefer `%autosetup` over `%setup -q` — it applies patches automatically and is the current idiom. |
| `%build` | build host | Compile. **Assume no network.** |
| `%install` | build host | Populate `%{buildroot}`. Never install to the live filesystem. |
| `%check` | build host | Test suite. Treat *omitting* this as the thing needing justification, not including it. |
| `%files` | parse time | Manifest. Anything in `%{buildroot}` but not listed is an error. |
| `%pre/%post/%preun/%postun` | **target host** | Scriptlets. These run on the user's machine, must be idempotent, and must not assume network or a running systemd. |

Scriptlets receive an argument telling them whether this is an install or an
upgrade — `$1` is `1` on first install, `2` on upgrade, `0` on final removal.
Getting this wrong is the classic "uninstalling the old package during an
upgrade deleted my user's data" bug.

## Preamble fields

**Version / Release.** `Release: 1%{?dist}` is correct convention. If `Version`
comes from outside the spec — a CI `--define`, a `VERSION` file — give it an
in-spec fallback (`%{!?myver: %global myver 0.0.0}`) or accept that a bare
`rpmbuild` on the spec produces a confusing downstream failure rather than a
clean error. rpmbuild does not hard-fail on an undefined version macro; it
warns and carries the literal `%{macro}` text forward, which then breaks
`%setup` when the tarball's directory name doesn't match.

**License.** Must be a current SPDX identifier or expression. Verify it against
the actual `LICENSE` text rather than trusting the filename — projects
mislabel this routinely.

**Source0.** Prefer a resolvable URL so provenance is checkable (`%forgemeta`
handles forge tarballs). If only a bare filename is possible because the
tarball is generated locally, put a comment directly above `Source0` saying how
to regenerate it. `rpmlint` will emit `invalid-url` either way; the comment is
what makes it an honest suppression.

**ExclusiveArch with a noarch subpackage.** If the spec restricts
architectures *and* contains a `BuildArch: noarch` subpackage, add `noarch` to
the `ExclusiveArch` list:

```spec
ExclusiveArch:  x86_64 aarch64 noarch
```

Without it, the architecture-independent subpackage becomes needlessly
unbuildable anywhere outside the allowlist — silent until someone builds on a
third architecture.

**BuildRequires.** List what `%build` actually invokes. A `BuildRequires: make`
in a spec whose `%build` hand-rolls `go build` is dead weight that misleads the
next reader. Conversely, make version floors real: if the source tree demands a
newer toolchain than the floor allows, a satisfying-but-too-old compiler either
fails confusingly or (for Go and Rust) silently reaches for the network to
fetch the right one — which fails in a sandboxed build.

## %build: use the language macro

Distro RPM macros exist for most languages (`%gobuild`, `%cargo_build`,
`%cmake`/`%ninja_build`, `%py3_build`). They wire up hardening flags,
reproducible build IDs, and path trimming, and — importantly — leave the binary
in a state debuginfo extraction can still use. Hand-rolling the compiler call
loses all of that silently.

If you hand-roll anyway, at minimum trim build paths (`-trimpath` for Go) so
binaries don't embed `%{_builddir}`, and don't strip at compile time unless you
also disable debuginfo generation *and* explain why.

**Disabling debuginfo requires a written reason.** `%global debug_package
%{nil}` with no comment is a guideline violation and, more practically, robs
anyone debugging a production crash. If the language's macro can produce usable
debuginfo, use it instead:

```spec
# Go binaries with -s -w carry no DWARF, so debuginfo extraction would produce
# an empty package. <justification for why -s -w is required here>
%global debug_package %{nil}
```

**Assume the build has no network.** Fedora's build system runs in a chroot
with no internet, and `mock` does the same locally. Any language with a module
ecosystem must vendor its dependencies (a `Source1` vendor tarball, `go mod
vendor` + `-mod=vendor`, `cargo vendor`) and declare bundled provides. A spec
that only builds on a networked developer laptop is a spec that will fail the
first time it meets a real build system. See [`languages.md`](languages.md).

## Scriptlets

**systemd.** Use the macro triad, one set per unit-shipping subpackage, with
`BuildRequires: systemd-rpm-macros` and `%{?systemd_requires}` in the
subpackage header:

```spec
%post   svc
%systemd_post   myd.service
%preun  svc
%systemd_preun  myd.service
%postun svc
%systemd_postun_with_restart myd.service
```

`%systemd_post` honours the distro's *preset* policy — it does not
unconditionally enable. If your service must be enabled out of the box, that
needs a real preset file, not an assumption.

Choose the `%postun` variant deliberately: `_with_restart` restarts the daemon
on upgrade, which is right for a stateless service and wrong for one that would
drop in-flight work or where the restart is an outage. Plain `%systemd_postun`
leaves it running the old binary until someone restarts it. There is no
universally correct answer — pick one and say why.

**Users.** Ship a `sysusers.d/<pkg>.conf` **and** create the account explicitly.
Neither alone covers every supported target, and the two failure modes point in
opposite directions.

**Why the shipped file is mandatory.** If any `%files` entry names the account,
rpm's dependency generator turns `%attr(0700,myusr,mygrp)` into
`Requires: user(myusr)` and `Requires: group(mygrp)`, and the only thing that
emits the matching `Provides` is a packaged `sysusers.d` file. A hand-rolled
`%pre` creates the same account and provides nothing, so the package builds
clean, lints clean, and then:

```
nothing provides user(myusr) needed by mypkg-1.0-1.fc43.x86_64
```

dnf refuses the whole transaction, and so does low-level `rpm -i`. Nothing below
tier 3 sees it, and a ladder that installs only *one* subpackage will not see it
either — see `verification.md`.

**Why the shipped file is not sufficient.** `%sysusers_create_compat` does not,
despite the name, work everywhere from one code path. Measured directly:

| rpm | Distro | Generates `user()`/`group()` from `%attr` | `%sysusers_create_compat` |
|---|---|---|---|
| 4.14.3 | RHEL 8 | No | **undefined** — `systemd-rpm-macros` is not installable from default repos |
| 4.16.1.3 | RHEL 9 | No | defined, **expands to nothing** |
| 4.20.1 | Fedora 41 | No | defined |
| 6.0.2 | Fedora 43 | **Yes** | defined, works |

So on RHEL 9 a file-only fix leaves the account uncreated and every `%attr` path
root-owned, with only a warning to show for it:

```
warning: group myusr does not exist - using root
```

The package installs, so tier 3 passes; the ownership is simply wrong. Combine
both mechanisms — the `getent` guards make the explicit creation a no-op when
sysusers already ran:

```spec
%pre
%{?sysusers_create_compat:%sysusers_create_compat %{SOURCE1}}
getent group  mygrp >/dev/null || groupadd -r mygrp
getent passwd myusr >/dev/null || \
    useradd -r -g mygrp -d /var/lib/myusr -s /sbin/nologin \
            -c "My daemon" myusr
exit 0
```

The `%{?…:…}` guard matters for RHEL 8, where the macro is undefined and would
otherwise be carried into the scriptlet as literal text.

Two rules that get broken: the guard makes it idempotent (scriptlets rerun), and
**every distinct service account needs its own home directory.** Two accounts
sharing a homedir defeats the isolation that made them separate accounts, and it
reads as a copy-paste artifact even when nothing currently breaks.

Never delete users in `%postun`. Removing an account while files it owns remain
on disk creates orphaned-uid files that a future unrelated user inherits.

**Verify a macro exists before using it in a scriptlet.** An undefined RPM macro
is not an error — it is left verbatim, so `%tmpfiles_create_compat` (which does
not exist; the macro is `%tmpfiles_create`) reaches the shell as a token
starting with `%`, which it reads as a job spec:

```
/var/tmp/rpm-tmp.HavFEH: line 9: fg: no job control
%post(mypkg) scriptlet failed, exit status 1
```

This class of typo survives everything static. `rpmspec -P` exposes undefined
macros in the *metadata*, but a macro used only inside `%pre`/`%post` parses
fine and fails on the user's machine, after the files are already unpacked. List
what is actually available rather than trusting a name that reads plausibly:

```sh
grep -rhoE '^%(tmpfiles|sysusers)[a-z_]*' /usr/lib/rpm/macros.d/ | sort -u
```

## %files discipline

**Own every directory you create.** For each path in `%files`, every custom
parent directory needs an explicit `%dir` entry somewhere in that subpackage or
one it requires. Directories owned by `filesystem` (`/etc`, `/usr/bin`) are the
exception.

This is the single easiest thing to miss because nothing fails — the build
succeeds, the install succeeds, and the directory is simply left behind on
erase with whatever mode `install -D` implicitly gave it. Audit it mechanically:
list every path in `%files`, take each prefix, and confirm a `%dir` exists.

```spec
%dir %attr(0750,root,mygrp) %{_sysconfdir}/mypkg
%config(noreplace) %attr(0640,root,mygrp) %{_sysconfdir}/mypkg/config.yaml
```

**Never glob** `%{_bindir}/*`. An upstream that adds a binary silently joins
your package unreviewed. List paths explicitly.

**Config files.** `%config(noreplace)` preserves site edits (new version lands
as `.rpmnew`). Plain `%config` replaces and saves the old as `.rpmsave` — use it
only when the old format is genuinely incompatible, with a comment. Config
never belongs under `/usr`.

A file under `/etc` that is *code* — a `profile.d` script, a helper — should be
shipped as a plain file with no `%config` marking so fixes always land. This is
one of the places RPM is more expressive than dpkg; see
[`cross-distro.md`](cross-distro.md).

**`%license` vs `%doc`.** Use `%license` for the licence text. A subpackage
needs its own `%license` unless it hard-requires a sibling that already carries
it — decide per subpackage rather than cargo-culting.

## Subpackages

Split along installation boundaries: things a user might reasonably not want.
Arch-dependent binaries and `BuildArch: noarch` content cannot share a package.

Pin tightly-coupled subpackages to the exact build:

```spec
Requires: %{name}-base = %{version}-%{release}
```

**Per-deployment or secret material** — private keys, per-tenant certs,
prebuilt images baking in credentials — is best not packaged at all. If it must
be, make it a non-default subpackage behind an explicit build flag, document
in-spec that it must never reach a shared repo, and make the build script refuse
to combine it with a shared-chroot build. The structural refusal matters more
than the warning text: a warning gets ignored, a build that won't produce the
artifact cannot be.

## High-frequency bugs

| Bug | Symptom | Fix |
|---|---|---|
| Unowned custom directory | Orphaned dir left on erase; `rpm -qf` can't attribute it | Explicit `%dir` for every custom parent |
| `ExclusiveArch` omits `noarch` | noarch subpackage unbuildable on other arches | Add `noarch` to the list |
| Unvendored module deps | Build fails in mock/Koji with network errors | Vendor tarball + `bundled()` provides |
| `debug_package %{nil}` unexplained | No debuginfo for production crashes | Use the language macro, or justify in a comment |
| Undefined `Version` macro | Confusing `%setup` failure, not a clean error | In-spec fallback, or test the bare-spec path |
| Two accounts, one homedir | Silent isolation failure | One homedir per account |
| Scriptlet ignores `$1` | Upgrade runs removal logic | Branch on `$1` (`1`=install, `2`=upgrade, `0`=erase) |
| Globbed `%files` | Unreviewed upstream files ship | List paths explicitly |
| Config marked as code (or vice versa) | Site edits lost, or fixes never land | `%config(noreplace)` for config; plain for code |

## Verification

The host is often not RPM-based; build in a container.

```sh
# Parse-only sanity, works anywhere rpm is installed. Exposes undefined macros.
rpm -q --specfile mypkg.spec --define "myver 1.2.3"

# Build + lint in a container
podman run --rm -v "$PWD":/src:ro -w /src fedora:latest bash -c '
  dnf install -y -q rpm-build rpmdevtools rpmlint golang make systemd-rpm-macros
  rpmbuild --define "_topdir /tmp/rpmb" -ba mypkg.spec
  rpmlint /tmp/rpmb/RPMS/*/*.rpm'

# mock reproduces the real, network-isolated build. This is the one that
# catches unvendored dependencies.
mock --rebuild mypkg-1.2.3-1.src.rpm

# Inspection — run these on the BUILT package, not the spec
rpm -qlvp  pkg.rpm     # files with modes and owners; shows missing %dir
rpm -qcp   pkg.rpm     # config files only
rpm -qp --scripts   pkg.rpm
rpm -qp --requires  pkg.rpm
rpm2cpio pkg.rpm | cpio -tv   # payload without installing
```

`scripts/verify-package.sh --format rpm` runs build → lint → install → upgrade.
The upgrade tier is what catches `%config` and scriptlet mistakes.

## rpmlint triage

Sort every finding into one of three buckets and say which:

- **Real bug** — fix it.
- **Expected for this language or layout** — e.g. Go binaries and
  stripping/RELRO checks. Record why.
- **Deliberate deviation** — e.g. a config file at mode `0640` because it holds
  a credential, or `invalid-url Source0` for a locally generated tarball.
  Record why, next to the suppression.

`macro-in-comment` is worth fixing rather than suppressing: a `%macro` inside a
comment still expands, so comments can change behaviour. Escape as `%%`.

A clean rpmlint run on the *spec* proves very little. Run it on the built
binary packages, where the file-level checks actually have something to inspect.

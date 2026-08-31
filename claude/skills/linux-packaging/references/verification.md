# Verification

Every recipe here has been run. The traps called out are ones that actually bit,
not ones that seemed plausible.

`scripts/verify-package.sh` automates tiers 1–4; this file is what it does, so
you can run the steps by hand, debug it when it misbehaves, or adapt it.

## Contents

- [The ladder](#the-ladder)
- [Container traps](#container-traps)
- [Build recipes](#build-recipes)
- [The install test](#the-install-test)
- [The upgrade test](#the-upgrade-test)
- [Linters](#linters)
- [CI](#ci)
- [What no tier catches](#what-no-tier-catches)

## The ladder

| Tier | Catches | Cost |
|---|---|---|
| 0 recipe lints | Syntax, metadata errors | seconds |
| 1 builds | Missing files, bad paths, unresolved macros, unsatisfiable build deps | ~1 min |
| 2 lint the built package | Unowned files, wrong modes, missing deps, scriptlet smells | seconds |
| 3 install in a clean container | **Dependency names that don't resolve**, install scriptlet failures, file conflicts | ~1 min |
| 4 upgrade N → N+1 | Config clobbering, upgrade scriptlets, restart policy, version ordering | ~2 min |
| 5 remove, and purge | Leftover files, uninstall scriptlet crashes, whether a surviving user is intentional | ~1 min |
| 6 real PID 1 systemd | Unit activation, `User=` resolution, hardening directives that break the daemon | ~2 min, containers only |
| 7 real hardware / VM | SELinux/AppArmor, device access, reboot persistence, true multi-arch | human |

Climb to the tier that would catch what you could plausibly have broken. Tier 3
deserves particular respect: a package name copied from a sibling format builds
clean and lints clean, and only a real install attempt reveals that the
dependency does not exist on the target.

**Tier 1 means building from a pristine export, not your working tree.** A
recipe that references a gitignored file builds perfectly on the machine that
has it, and the package then ships whatever that machine happened to contain —
in one real case a maintainer's own config, complete with debug logging, as a
protected conffile on every user's system. The same build from
`git archive HEAD` fails immediately with `install: cannot stat 'config.yaml'`.
If your build scripts already stage a source snapshot (`repo-layout.md`), you
get this for free; if they build in place, tier 1 is weaker than it looks.

## Container traps

Nine things that cost real time:

1. **`makepkg` refuses to run as root**, by design. Arch builds in a container
   need an unprivileged user and `runuser`.
2. **git refuses to operate on a tree owned by another uid.** Running as root
   over a bind-mounted repo makes `git rev-parse` fail, and build scripts that
   branch on "are we in a git tree?" then silently take their fallback path —
   which may need tools you didn't install. `git config --global --add
   safe.directory '*'` inside the container.
3. **A malformed `~/.docker/config.json` breaks every podman pull** with an
   opaque JSON parse error that looks nothing like an auth problem. Point
   `REGISTRY_AUTH_FILE` at a file containing `{}`.
4. **A fresh install container has no package index.** Without `apt-get update`
   every declared dependency reports "not installable" and you will misread it
   as a dependency bug.
5. **apt rejects a bare filename** for a local `.deb`. It must look like a path:
   `apt-get install ./foo.deb`.
6. **The distro's own toolchain is often too old.** Debian bookworm ships Go
   1.19; Fedora 43 ships Go 1.25. If the project needs newer, use a
   language-specific base image (`golang:1.26-bookworm`) or install the
   toolchain — and treat an unsatisfiable `BuildRequires` as a finding, because
   it means the package cannot be built on its stated target.

Three more, each of which cost someone real debugging time:

7. **`dpkg-buildpackage` writes its output one directory *above* the source
   tree.** If the parent isn't writable by the build user, the build runs to
   completion and then fails at the last step with a permission error. Copy the
   source into a directory the build user owns.
8. **Never `chown -R` a bind mount from inside a rootless container.** Rootless
   podman maps container UIDs to subordinate host UIDs, so the chown reassigns
   ownership of the *host* files and can lock you out of your own tree. Repair
   with `podman unshare chown -R 0:0 <path>`; better, copy into a
   container-native path first.
9. **Official Debian images ship `/usr/sbin/policy-rc.d` returning 101**, which
   blocks service starts during install by design. That is layered on top of
   debhelper's own `[ -d /run/systemd/system ]` guard, so a service not starting
   in a Debian container tells you nothing.

7. **Base images suppress documentation, so doc assertions lie.** The Fedora
   image sets `tsflags=nodocs` in `/etc/dnf/dnf.conf` and the Arch image sets
   `NoExtract` for `usr/share/man/*`. A package containing a man page installs
   without one on disk, so `test -f /usr/share/man/man8/foo.8.gz` fails on a
   correct package — and, worse, an assertion you then weaken to make it pass
   will never fail again. Assert the package *contents* (`rpm -ql`, `pacman -Ql`,
   `dpkg -L`), and lift the suppression if you want the on-disk check too:
   `dnf --setopt=tsflags= install`, or `sed -i '/^NoExtract/d' /etc/pacman.conf`.
8. **`pacman -U` does not accept `--quiet`.** It exits non-zero having installed
   nothing, which reads exactly like a broken package. Several package-manager
   flags are subcommand-specific in ways the man page does not make obvious;
   when an install fails, run it once without your convenience flags before
   believing the package is at fault.

### Containers have no PID 1 — what that does and doesn't cost you

Scriptlets guarded on `[ -d /run/systemd/system ]` no-op, which proves the guard
works but leaves activation untested. Worse, **RPM's systemd macros end their
helper call with `|| :`, so the scriptlet's exit status is discarded** — a clean
`dnf install` exit code says nothing at all about whether the unit was enabled.

Two things rescue this:

```sh
systemctl is-enabled foo.service    # WORKS with no running systemd —
                                    # it reads .wants/ symlinks statically
```

That single command is how you actually verify enable policy per distro (RPM
defers to presets, Debian enables by default, Arch never enables).

And for genuine activation, podman can boot a real init — provided the image
actually has systemd installed:

```sh
podman run -d --name t --systemd=always myimage /usr/sbin/init
podman exec t systemctl enable --now foo.service
podman exec t systemctl is-active foo.service
```

Omitting the explicit init command silently runs the image's default `CMD` and
exits immediately. Docker has no `--systemd=always`, which is the concrete
reason to prefer podman for this tier.

9. **The `archlinux` image sets `NoExtract` for `usr/share/doc/*` and
   `usr/share/man/*`.** Docs and man pages are registered by `pacman -Ql` but
   never written to disk, so a test asserting `[ -f /usr/share/doc/pkg/README ]`
   fails on a package that ships the file correctly. Assert **package
   ownership** (`pacman -Ql pkg | grep ...`), not on-disk presence — and check
   `/etc/pacman.conf` before concluding a file is missing.

## Build recipes

```sh
# Shared preamble
export REGISTRY_AUTH_FILE=$(mktemp -d)/auth.json; echo '{}' > "$REGISTRY_AUTH_FILE"
```

**RPM**

```sh
podman run --rm -v "$PWD":/src:ro fedora:latest bash -c '
  dnf install -y -q rpm-build rpmdevtools rpmlint golang make git tar
  git config --global --add safe.directory "*"
  cp -a /src /build && cd /build
  rpmbuild --define "_topdir /build/rpmbuild" -ba packaging/rpm/foo.spec
  rpmlint /build/rpmbuild/RPMS/*/*.rpm'
```

`mock --rebuild foo.src.rpm` reproduces the real, network-isolated build. It is
the only thing that catches unvendored dependencies, so run it before claiming
the package builds anywhere but your laptop.

**Debian**

```sh
podman run --rm -v "$PWD":/src:ro golang:1.26-bookworm bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
      build-essential debhelper devscripts lintian dpkg-dev git make ca-certificates
  git config --global --add safe.directory "*"
  cp -a /src /build && cd /build
  dpkg-buildpackage -us -uc -b
  lintian --tag-display-limit 0 ../*.deb'
```

`build-essential` is required even for a pure-Go package: `dpkg-checkbuilddeps`
enforces it whether or not `control` lists it.

**Arch**

```sh
podman run --rm -v "$PWD":/src:ro archlinux:base-devel bash -c '
  pacman -Syu --noconfirm --needed base-devel go namcap
  useradd -m builder; cp -a /src /build; chown -R builder /build
  runuser -u builder -- bash -lc "cd /build/packaging/arch && makepkg -sf --noconfirm"
  namcap /build/packaging/arch/*.pkg.tar.zst'
```

## The install test

Installing is not the test; asserting afterwards is. A package manager can exit
zero having installed nothing you care about, so check post-conditions:

**Install every package the build produced, not just the interesting one.** A
split build makes this easy to get wrong: a ladder that installs only the
subpackage under active development will happily report PASS while the *other*
package is completely uninstallable. That is not hypothetical — an RPM whose
`%files` used `%attr(0700,svc,svc)` without a shipped `sysusers.d` file could
not be installed at all (`nothing provides user(svc)`), and a ladder covering
only its sibling subpackage missed it for an entire review round.

```sh
podman run --rm -v "$PWD/dist":/pkgs IMAGE bash -c '
  set -e
  apt-get update -qq                       # or: pacman -Sy
  cd /pkgs && apt-get install -y ./*.deb   # note the ./
  # --- assertions, each of which can fail ---
  getent passwd beacon                     # the service account exists
  test -x /usr/bin/beacond                 # the binary landed
  test -d /var/log/beacond                 # tmpfiles/dir creation worked
  ls -ld /var/log/beacond                  # ...with the right owner and mode
  dpkg-query -W -f="\${Package} \${Status}\n" beacond'
```

Watch for exit codes disappearing into pipes. `cmd | tail -20` returns *tail's*
status, so a failed install reads as success. Either drop the pipe, check
`PIPESTATUS`, or `set -o pipefail`. This is not hypothetical — an early version
of `verify-package.sh` shipped exactly that bug and confidently reported PASS on
a broken install.

## The upgrade test

The highest-value tier, and the one almost nobody runs. You need two builds: the
previous release and the candidate.

The method matters — installing old then new proves very little on its own,
because the interesting behaviour only triggers once a config file has been
*modified*:

1. Install version N.
2. Enumerate the config files the packages actually claim — `rpm -qcp`,
   `dpkg-deb -I <pkg> conffiles`, or `backup =` from Arch's `.PKGINFO`. Use the
   package's own list, not your memory of what you marked.
3. Append a recognisable marker line to each one.
4. Upgrade to N+1.
5. Assert every marker survived, and look for `.rpmnew` / `.dpkg-dist` /
   `.pacnew` / `.rpmsave` / `.pacsave` files.

A marker that vanished means that file's semantics are wrong — site edits are
being destroyed. A `.pacnew` appearing is correct behaviour on Arch, but note
pacman never tells the admin it happened.

**Debian will hang and then fail this test unless you force a conffile answer.**
Once a conffile is modified, `apt-get install ./new.deb` drops into an
interactive prompt; with no TTY it dies with `end of file on stdin at conffile
prompt` and exit 100. That is dpkg behaving correctly, but it makes an automated
tier 4 look like a packaging failure. Pass an explicit answer:

```sh
apt-get install -y -o Dpkg::Options::=--force-confold ./new.deb
```

`--force-confold` keeps the admin's file and writes the new one as
`.dpkg-dist` — the behaviour you want to assert. This is a real difference in
kind: RPM and pacman resolve the same situation silently and automatically,
Debian asks.

**Do not reach for `--nodeps` to make an RPM upgrade succeed.** It discards the
dependency check the tier exists to perform. Use `dnf install -y ./pkg.rpm`,
which resolves dependencies properly on the upgrade path; plain `rpm` cannot.

Then keep going one more tier: `remove` and, on Debian, `purge` separately.
Removal exercises scriptlet paths nothing else touches, and it is where you
confirm that the service account surviving is a deliberate choice rather than an
oversight. On Debian, `remove` leaves conffiles on disk and only `purge` deletes
them — verify both, because packages routinely get one right and the other
wrong.

`verify-package.sh --upgrade-from DIR` does exactly this. Without that flag it
reports tier 4 as **skipped**, never as passed — an untested upgrade path is not
a working one.

## Linters

Run them on the **built package**, not the recipe. A clean run against a spec
proves little; the file-level checks need files to inspect.

**This tier is not redundant with tiers 3-4, and skipping it is the most common
way a real defect ships.** It catches a class the install and upgrade tests
structurally cannot: defects invisible in the recipe that *also* survive a clean
install. Three from one audit of packaging that built, installed and upgraded
cleanly on all three formats:

- The package shipped `/etc/logrotate.d/<name>` and nothing depended on
  logrotate, which is in neither the Fedora nor the Debian base image. Rotation
  silently never ran and the log directory grew without bound.
  (`E: missing-dependency-to-logrotate`)
- `%tmpfiles_create %{SOURCE2}` baked the *builder's* SOURCES path into the
  shipped scriptlet, so every installed host ran `systemd-tmpfiles --create`
  against a path that cannot exist there. The macro ends in `|| :`, so it failed
  silently -- and the install test passed anyway, because `%files` shipped the
  same directories. (`W: post-without-tmpfile-creation`)
- A logrotate config with no `su` directive for a log directory owned `0700` by
  an unprivileged account, so logrotate would have processed it as root.
  (`E: logrotate-user-writable-log-dir`)

Reading the recipes finds none of them, and an install test passes with all
three present.

```sh
rpmlint pkg.rpm
lintian --tag-display-limit 0 pkg.deb
lintian --no-override        pkg.deb    # what your overrides are hiding
namcap pkg.tar.zst; namcap PKGBUILD     # namcap is worth running on both
```

Sort every finding into one of three buckets, and be able to say which:

| Bucket | Examples | Action |
|---|---|---|
| Real bug | `audit` is not a Debian package; unowned directory | Fix |
| Expected for this language | Go binaries: `lacks FULL RELRO`, `no-manual-page`, spelling errors in `%description` | Record why, once |
| Deliberate | Config at `0640` because it holds a credential; `invalid-url Source0` for a locally generated tarball | Record why, next to the suppression |

The discipline that keeps this honest: state the reason where the suppression
lives, and check with `lintian --no-override` what you have hidden. If you cannot
articulate why a finding does not apply, it probably does.

Some findings you *can* fix that look like language noise:
`position-independent-executable-suggested` on a Go binary means the build is
not passing `-buildmode=pie`, which it should.

### Prove the suppression file suppresses

A filter file that is loaded but ineffective looks exactly like a clean package.
Two checks, both cheap:

1. **Compare filtered counts with and without it.** rpmlint prints
   `N errors, N warnings, N filtered` on its last line. If that line does not
   move when you pass your filter file, the file is not doing anything —
   regardless of what the tool says it loaded.
2. **Run it against a package you know is bad.** Keep a pre-fix artifact, or
   temporarily reintroduce a defect. Every finding you did not deliberately
   filter must still fire. This is what stops a broad filter from quietly
   swallowing the next real bug.

### rpmlint's filter file has three traps

All three were hit in one sitting, and each one fails silently:

- The option is **`-r` / `--rpmlintrc`**, not `-f`. Passing `-f` makes rpmlint
  exit with a usage error, which reads as "no findings" to anything grepping its
  output for error lines.
- rpmlint 2.x accepts a **TOML `Filters = [...]`** rpmlintrc, reports it in the
  loaded-configuration list, and then **filters nothing**. Use the legacy
  `addFilter("tag-name")` form. Verified by count: `addFilter` moved one package
  from 3 filtered to 13; the TOML form left it at 3.
- One rpmlintrc covering several subpackages needs
  **`--ignore-unused-rpmlintrc`**. A filter that applies to one subpackage is by
  definition unused when linting its sibling, and rpmlint reports that as an
  *error* — failing the build for no defect.

Worse, rpmlint disagrees with *itself* across distributions: 1.x (RHEL 9) takes
`-f` for a config file where 2.x takes `-r`, and 1.x checks `URL:` over the
network where 2.x does not — which is how a spec still carrying its template's
`https://github.com/example/foo` gets caught. Running the same linter on two
distributions is not redundant. Some distributions package no linter at all
(UBI 10 has no rpmlint); see
[`multi-distro-builds.md`](multi-distro-builds.md#what-varies-between-distributions-in-practice).

`lintian` is better behaved: `--fail-on error` gives a usable exit status, and
per-package overrides live in `debian/<pkg>.lintian-overrides` with the reason in
a comment above each entry. `namcap` **always exits 0**, so its output is the
only signal — a namcap gate must parse output and separately assert that a
package was actually inspected.

## CI

**Build and lint every format on every change.** Packaging rots between releases
precisely because nothing exercises it between releases: the recipe is edited to
add a file, the dependency it needs is forgotten, and nobody finds out until
someone installs on a host that is missing it. Tiers 1 and 2 are fast enough that
there is no reason to run them only at release time.

A matrix over distro containers, one leg per format. Each leg builds, lints, and
installs; the upgrade leg additionally fetches the previous release's artifacts.

Three things worth getting right:

- **`fail-fast: false`.** A broken RPM must not hide a broken `.deb`. Formats
  fail independently and you want all the results in one run.
- **Invoke the same command a developer runs** — a Makefile target or a script in
  the repo, not an equivalent inlined into the workflow. Two spellings of the
  same check drift, and the CI copy is the one nobody runs locally before
  pushing.
- **Gate on error-level findings, not on all output.** Warnings that reflect the
  language's build output will always be there; a gate that fails on them gets
  disabled within a week. Findings that genuinely do not apply belong in that
  format's justified filter file, never in a widened gate.

```yaml
  packaging:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    strategy:
      fail-fast: false
      matrix:
        format: [rpm, deb, arch]
    steps:
    - uses: actions/checkout@v4
    # No language toolchain setup: the build runs inside the container, on the
    # toolchain that format's distribution actually ships, which is the thing
    # being tested.
    - name: Build and lint the ${{ matrix.format }} package
      run: make lint-packaging-${{ matrix.format }}
```

Cost is lower than it looks. Measured on `ubuntu-latest`, with each leg starting
from an empty container and installing its own build dependencies: rpm 1m58s,
deb 1m49s, arch 1m28s. Because the legs run in parallel with each other and with
the existing build and lint jobs, wall-clock CI grew by about 30 seconds. Resist
path-filtering these jobs to `packaging/**` — the package contains the built
binaries, so a source change can alter what lands in it.

If the build stages from `git archive HEAD` (see
[`repo-layout.md`](repo-layout.md)), the job lints **committed** state. That is
right for CI, which checks out a commit, but means a developer running the same
target locally lints their last commit, not their working tree. Say so in the
script.

None of it needs privileged mode — package building and installing inside a
container are unprivileged operations. What CI cannot give you is tier 5: no
runner offers a real init system inside the build container, so unit activation
stays untested until a real host or a VM-based job.

Cache the toolchain layer, not the build output; packaging builds are fast and
the dependency install dominates.

### A gate that cannot fail is not a gate

The failure mode is specific and it is quiet: a linter that never ran reports
nothing, and "nothing" is indistinguishable from "clean". This happened with
`rpmlint -f` (the option is `-r`) — the linter died with a usage error on every
package, the job grepped its output for `: E: `, found none, and passed.

So make each gate assert three things, not one:

```sh
rc=0; n=0
for f in <artifacts>; do
    [ -e "$f" ] || continue
    n=$((n + 1))
    if <linter> "$f" >/tmp/out 2>&1; then :; else rc=1; fi   # 1. exit status
    cat /tmp/out
    if grep -qE "<error-pattern>" /tmp/out; then rc=1; fi     # 2. error findings
done
[ "$n" -gt 0 ] || { echo "no packages were linted" >&2; exit 1; }  # 3. it ran
exit $rc
```

The third check is the one people leave out, and it is the one that catches a
glob that matched nothing because the build silently produced no artifact.

And collect only what *this* build produced. A repo often carries packages from
earlier runs — a `dist/` tree, a stale `rpmbuild/` — and a bare
`find . -name '*.rpm'` sweeps them up, so old artifacts get linted as current and
installed in the install tier. Snapshot the matching paths before the build and
take the difference.

One more trap in the same family, because it silently destroys the evidence you
need when a gate does fire. These build steps are usually **compound** commands:

```sh
BOOTSTRAP='dnf install -y rpm-build make && { dnf install -y rpmlint || echo note; }'
...
$BOOTSTRAP >/tmp/bootstrap.log 2>&1 || { cat /tmp/bootstrap.log; exit 1; }
```

`A && { B; } >log` binds the redirect to the **brace group alone**. When the
first clause fails, its output goes to the terminal, the log file is never
created, and the handler prints `cat: /tmp/bootstrap.log: No such file or
directory` instead of the error you needed. Wrap the whole thing:

```sh
{ $BOOTSTRAP ; } >/tmp/bootstrap.log 2>&1 || { cat /tmp/bootstrap.log 2>/dev/null; exit 1; }
```

### Recipes run your test suite during the build

`%check`, `dh_auto_test` and Arch's `check()` all execute the project's tests
inside the build container. That makes test-suite portability a *packaging*
concern: a test that shells out to something the build container lacks — a
container engine especially, if your own tooling has tests — breaks the package
build, not merely the test run. RPM specs frequently omit `%check` while Debian
and Arch run tests by default, so the same defect fails two formats and passes
the third, which reads as a distro-specific bug and is not one.

## What no tier catches

Be explicit about this when reporting, because it is where the residual risk
lives:

- **Unit activation** under a real init — `ExecStart` paths, `User=` resolution,
  ordering and dependency edges, socket activation.
- **Hardening directives that break the daemon** — `ProtectHome`,
  `RestrictAddressFamilies`, `SystemCallFilter`. These fail at runtime with
  errors that read like application bugs.
- **SELinux / AppArmor** policy.
- **Device and hardware access.**
- **Multi-architecture behaviour**, unless you actually built for the other arch.
- **Anything about a real upgrade from a version you did not test against.**

"Builds, installs, and upgrades cleanly on Fedora 43 and Debian 12; not tested
under a live systemd" is a useful claim. "Verified" is not.

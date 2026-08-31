# Building for many distributions, and both architectures

Packaging is usually written on one machine, for the distribution that machine
runs. That makes every other target theoretical: the recipe compiles somewhere
nobody has tried, against a toolchain nobody has checked, and the first person
to find out is a user.

This is the shape that makes the other targets real, and what it costs.

**Working tooling for all of it is in
[`assets/templates/multi-distro/`](../assets/templates/multi-distro/)** — the
manifest, the driver, the make targets and the CI jobs, as they were run to
build five distributions end to end. Start there and adapt; this file is the
reasoning behind it.

## Contents

- [The model](#the-model)
- [Why not cross-compile or emulate](#why-not-cross-compile-or-emulate)
- [The manifest](#the-manifest)
- [The driver](#the-driver)
- [What varies between distributions, in practice](#what-varies-between-distributions-in-practice)
- [CI](#ci)

## The model

**The container supplies the distribution. The machine supplies the
architecture.**

Nothing in the build mentions an architecture — no `--platform`, no `--target`,
no `GOARCH`/`--host`, no qemu. A build runs `podman run <image>` and the package
is tagged for whatever the host is, because the builder genuinely is that. An
x86_64 machine produces the x86_64 half of the matrix; an aarch64 machine
produces the other half. **Neither can produce the other's**, and saying so
plainly is better than a mechanism that pretends otherwise.

Add one assertion, because it is what keeps the claim true: before building,
compare `uname -m` inside the container against the host's and fail on
mismatch. With binfmt registered, or an arch-specific image reference, a leg can
silently emulate — producing a correct-looking package very slowly, which is the
failure the design exists to avoid. An unenforced convention is not a property.

## Why not cross-compile or emulate

Both alternatives work until the project needs a C compiler, and then they stop.

**Cross-compilation** is nearly free for a language with a self-contained
toolchain — Go with `CGO_ENABLED=0` cross-compiles with one environment
variable. Turn cgo on and the binary links against the build environment's
glibc, so a binary built on Fedora and run on RHEL 9 fails with
`GLIBC_2.34 not found`. Cross-building it then needs a C toolchain *and a
sysroot matched to each target distribution*, not merely to the target
architecture. Debian has a first-class story for this (`dpkg --add-architecture`,
`libfoo-dev:arm64`, `crossbuild-essential-*`); Fedora and RHEL have a weak one;
Arch effectively none.

A second-order effect that catches people: a cgo binary acquires real
shared-library dependencies, which the packaging must generate. RPM does it
automatically via `elfdeps`; Debian needs `dh_shlibdeps` filling
`${shlibs:Depends}` — and `dh_shlibdeps` can only resolve libraries for the
architecture it is running on. That is another reason the *packaging* step
belongs inside the target environment even if the compile did not.

**Emulation** (`--platform` plus `qemu-user-static`) avoids all of that and is
uniform, at 5–15× on compilation. It is a reasonable choice when a project's
test suite is short and one machine must produce everything. It is a poor one
when the recipe runs the test suite during the build, which Arch's `check()` and
Debian's `dh_auto_test` do by default.

**Native-only is the option that keeps working in every case**, which is why it
is the default recommendation here. Its cost is real and singular: you need a
machine, or a CI runner, of each architecture.

## The manifest

Put the target list in a file that both the local driver and CI read, so the two
cannot drift:

```
# id            format  image                                    arches
fedora          rpm     fedora:latest                            amd64,arm64
rhel9           rpm     registry.access.redhat.com/ubi9/ubi      amd64,arm64
debian-stable   deb     debian:stable                            amd64,arm64
arch            arch    archlinux:latest                         amd64
```

TSV keeps the shell reader parser-free; a `--json` mode feeds the CI matrix.

**The `arches` column is load-bearing, not documentation.** Base images do not
all publish both architectures, and the exception is not obvious: the official
`archlinux` image is **amd64-only**, while Fedora, Debian, Ubuntu, Rocky,
AlmaLinux and Red Hat's UBI all publish amd64 and arm64. Without the column, CI
schedules an Arch leg onto an ARM runner and fails for a reason that has nothing
to do with the packaging.

Check before adding a row, rather than assuming:

```sh
skopeo inspect --raw docker://docker.io/library/archlinux:latest |
    jq -r '.manifests[].platform.architecture' | sort -u
```

For RHEL, `registry.access.redhat.com/ubi9/ubi` and `ubi10/ubi` need no
subscription and are the practical way to build for RHEL. Rocky and AlmaLinux
are the community rebuilds.

## The driver

One script per repo, taking a target id:

1. Resolve the target to a format and image.
2. **Refuse an impossible request.** If the host architecture is not in the
   target's list, exit non-zero — the caller asked for something that cannot be
   produced here. Whatever loops over all targets consults the manifest itself
   and only invokes supported pairs, so silence never means success.
3. Mount the repo read-only, copy it inside, and build there — a build must not
   be able to dirty the working tree.
4. **Resolve build dependencies from the recipe's own declarations** —
   `dnf builddep <spec>`, `mk-build-deps debian/control`, `makepkg -s` — never a
   hardcoded package list. This is the single decision that makes the manifest
   extensible: a distribution nobody anticipated works without editing the
   driver.
5. Assert the container's architecture matches the host's.
6. Copy artifacts to `dist/<target>/<arch>/`, **clearing it first** — the lint
   step inspects everything there and CI uploads it, so a leftover artifact from
   an earlier build gets linted as current and shipped as fresh.

## What varies between distributions, in practice

Each of these cost real debugging time, and none is visible from a recipe.

**A package that exists everywhere except your targets.** `protobuf-compiler` is
in Fedora and Debian and in no RHEL-family repository at all. A `BuildRequires`
naming it makes every RHEL target unbuildable — including one the spec declared
but never actually used.

**The language toolchain's own bootstrap floor.** A distro's compiler may be too
old to *fetch* the one the project wants. Go's `GOTOOLCHAIN=auto` downloads a
newer toolchain, but only from a recent enough Go: 1.24 fetches 1.27, while 1.22
fails with `toolchain not available`. So "the distro ships Go, and Go can
bootstrap" is not enough — see [`languages.md`](languages.md#go).

**Declared dependency floors that are false.** The failure above surfaced deep
inside `go clean`, with a message naming nothing, because the recipe declared
`golang-go (>= 2:1.21~)` — a version that cannot build the project at all. A
floor that is merely optimistic converts a clean dependency error into a
mystery. Declare the version you have actually built with.

**Linters differ across distributions, and find different bugs.** rpmlint 1.x
(RHEL 9) takes `-f` for a config file and has no unused-filter check; 2.x
(Fedora) takes `-r` and reports unused filters as errors. Both read the
`addFilter()` rpmlintrc. More usefully: 1.x checks `URL:` over the network and
2.x does not, which is how a spec still carrying its template's
`https://github.com/example/foo` gets caught. Running two versions of one linter
is not redundant.

**A distribution that ships no linter at all.** UBI 10 packages no rpmlint.
Install it opportunistically and, when it is absent, say so — "the packages were
BUILT but NOT LINTED" — rather than exiting quietly. A tooling gap must not make
the target unbuildable, and must not read as a clean lint either.

**Recipes run the test suite during the build.** `%check`, `dh_auto_test` and
Arch's `check()` all execute the project's tests inside the build container. A
test that shells out to something the build container lacks — a container engine
especially — therefore breaks *packaging*, not just testing. If your tooling has
tests, make sure the parts they exercise degrade cleanly: a "resolve and report"
mode must not require the engine it would otherwise launch.

## Restricted networks

A container build assumes it can reach a registry, the distribution's mirrors,
and the language's package index. Behind a corporate firewall none of those
holds, and the failures are misleading — a blocked mirror looks like a broken
recipe, and an intercepted TLS connection looks like a network outage.

Handle it with a **site directory kept outside the repository**, because
internal mirror hostnames and proxy URLs are site-specific and usually not
public. Mount it read-only and apply it inside the container before anything
touches the network, in this order:

1. **Source an `env` file** — extra variables, an internal `GOPROXY`, and so on.
2. **Install and trust extra CA anchors.** If the proxy intercepts TLS this is
   not optional: without it every HTTPS fetch fails with a certificate error.
   The destination is per-format — `/etc/pki/ca-trust/source/anchors` +
   `update-ca-trust`, `/usr/local/share/ca-certificates` +
   `update-ca-certificates`, `/etc/ca-certificates/trust-source/anchors` +
   `trust extract-compat`.
3. **Place repository configuration** — `/etc/yum.repos.d`,
   `/etc/apt/sources.list.d`, `/etc/pacman.d/mirrorlist`. Install **exactly one
   file, chosen by target id** (`rhel9.repo` for the `rhel9` target,
   `fedora.repo` for `fedora`), with `default.<ext>` as the fallback. Copying
   every file in the directory would let one site directory serve only one
   distribution: two mirror definitions landing in `/etc/yum.repos.d` and the
   wrong one consulted. Selecting by name is what lets a single site directory
   carry the whole fleet. A directory whose files match nothing is a naming
   mistake — report it, because a silent skip leaves the build pointed at
   unreachable default mirrors and fails later somewhere that says nothing about
   the cause.

   **Write it under a prefixed name, never the source's own.** A target id is
   frequently the distribution's own repo filename — `fedora.repo`,
   `rocky.repo` and `ubi.repo` all ship in `/etc/yum.repos.d` — so copying
   `fedora.repo` into place *deletes Fedora's base repository*. The build then
   fails with `No match for argument: make`, which names a missing package and
   says nothing about the repo you just destroyed. `00-site-<name>.<ext>` is
   collision-proof and obviously yours. Arch is the deliberate exception: its
   destination is fixed at `/etc/pacman.d/mirrorlist` because `pacman.conf`
   includes that exact path.
4. **Run an optional `setup.sh` last**, so it can override the rest. Its usual
   job is removing the distribution's own unreachable mirrors — **by name, never
   by glob**, or it deletes the site files placed a moment earlier.

Forward proxy variables **by name, not by value**: `podman run -e https_proxy`
takes the value from the calling environment, so a URL carrying credentials
never appears in a command line, in `ps`, or in a build log. Passing
`-e https_proxy=http://user:pass@...` leaks it into all three.

Working example: [`assets/templates/multi-distro/site.example/`](../assets/templates/multi-distro/site.example/).
`scripts/verify-package.sh` takes the same `--site DIR` (and `PKG_SITE_DIR`), so
the verification ladder works on a restricted network too.

Both were exercised against a real RHEL 9 container; the deb and arch site paths
are written from the same pattern but have not been run.

## CI

The matrix comes from the manifest, and the architecture axis is satisfied by
*which runner picks up the job* — a label that genuinely is that architecture,
since nothing emulates:

```yaml
  targets:
    runs-on: ubuntu-latest
    outputs: { matrix: "${{ steps.gen.outputs.matrix }}" }
    steps:
    - uses: actions/checkout@v4
    - id: gen
      run: echo "matrix=$(./packaging/targets.sh json --arches amd64,arm64)" >> "$GITHUB_OUTPUT"

  packages:
    needs: targets
    runs-on: ${{ matrix.runner }}      # amd64 → ubuntu-latest, arm64 → ubuntu-24.04-arm
    strategy:
      fail-fast: false
      matrix: ${{ fromJSON(needs.targets.outputs.matrix) }}
    steps:
    - uses: actions/checkout@v4
    - run: ./packaging/build-in-container.sh ${{ matrix.id }} --lint
```

Keep an `--arches` filter as the degradation path: where arm64 runners are
unavailable, the matrix should have fewer rows rather than fail. GitHub's
arm64-hosted runners are free for public repositories; private repositories need
a paid plan, so confirm availability before making arm64 legs required.

Two operational notes that are easy to learn the hard way:

- If the build stages from `git archive HEAD` (the usual way to get a pristine
  export — see [`repo-layout.md`](repo-layout.md)), it builds **committed**
  state. Verifying a change by running a container build *before* committing it
  verifies the previous revision.
- Do not edit a shell script while it is running. `sh` reads the file
  incrementally, so an edit shifts byte offsets under the running interpreter and
  produces a syntax error in a script that is perfectly valid on disk.

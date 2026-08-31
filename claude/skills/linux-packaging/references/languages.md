# Language-specific packaging concerns

The packaging *shape* is language-agnostic; what changes is how the thing gets
built, what hardening actually applies to it, whether debug symbols survive, and
how dependencies reach a network-isolated builder. Go is covered in depth
because it violates the most C-shaped assumptions; the rest note only where they
materially differ.

## Go

### Build flags

```sh
go build -trimpath -ldflags "-X main.version=$VER" -o bin/foo ./cmd/foo
```

- **`-trimpath`** strips filesystem paths from the binary. Without it the binary
  embeds the build directory, so two builds from different checkouts differ
  byte-for-byte and reproducibility is impossible.
- **`-ldflags -X pkg.var=value`** is how the version gets stamped. Take the value
  from the same single source the packaging uses, not a hand-typed literal.
- **`-buildvcs=false`** stops Go stamping VCS metadata. Builds from an extracted
  tarball have no `.git` and skip it anyway; setting it explicitly makes the
  guarantee deliberate rather than incidental.

### Hardening: most of it does not apply

This is where packaging descriptions routinely overclaim. For a **pure Go**
binary built with the internal linker:

| Flag | Applies to Go? |
|---|---|
| PIE | **Yes**, natively — `-buildmode=pie`, no C toolchain needed |
| RELRO / BIND_NOW | **Only** if you force `-ldflags=-linkmode=external` so the system linker does the final link |
| FORTIFY_SOURCE | **No.** It is a glibc header macro; Go's own code never routes through those headers |
| Stack protector | **No.** GCC canaries do not apply to gc-compiled code, which has its own bounds-checking model |

With cgo enabled, the C parts get the C treatment via `CGO_CFLAGS`/`CGO_LDFLAGS`
and the external linker gets used, so RELRO flows through.

Practical consequence: linters will complain, correctly, about things you cannot
fix by passing more flags.

- namcap: `ELF file lacks FULL RELRO, check LDFLAGS` — expected unless you force
  external linking.
- rpmlint: `position-independent-executable-suggested` — this one you *can*
  fix, with `-buildmode=pie`. If you see it, the build isn't passing that flag.

Do not claim "fully hardened" for a pure-Go binary. Claim PIE, and RELRO only if
you actually forced external linking.

### Debug symbols break quietly

Distro debuginfo tooling keys off the ELF build-id note. Go's internal linker
does not reliably produce one, so:

- Fedora's `find-debuginfo` yields an empty or useless `-debuginfo` package.
- Debian's `dh_strip` silently drops the binary from `-dbgsym` entirely.

Nothing errors. You discover it when someone needs a symbolised backtrace from a
production crash and there is nothing to symbolise.

**On Debian there is one failure mode that is not quiet: `dh_dwz` aborts the
build.** Go's linker compresses DWARF by default, and dwz refuses a compressed
`.debug_abbrev` section — `dh_dwz: error: dwz ... exit code 1` takes the whole
package down. Neutralise it explicitly:

```make
# Go compresses DWARF; dwz refuses compressed sections and fails the build.
override_dh_dwz:
```

Expect a companion warning from `dh_strip` — `Could not find the BuildID` — if
you build with `-buildid=`. That one is not fatal, but it does mean no `-dbgsym`
package is produced, which is the silent case above.

Fedora's `%gobuild` macro fixes this by injecting a deterministic, content-derived
build-id and disabling DWARF compression:

```
-ldflags "-B 0x$(printf '%s' "$NAME-$VERSION" | sha1sum | cut -d' ' -f1) -compressdwarf=false"
```

If you hand-roll the build, replicate that. Derive the hash from the **binary
name**, not just the package name — a multi-binary package that reuses one
build-id across all of them breaks symbol correlation just as thoroughly as
having none.

The opposite choice is also legitimate: strip aggressively with `-ldflags "-s -w"`
and disable debuginfo generation — but then say so in a comment, because a
silently empty debuginfo package is the worst of both.

### Vendoring for network-isolated builds

Fedora's Koji/mock and Debian's buildds have no network. A build that fetches
modules works on a laptop and fails there.

```sh
go mod vendor                    # commit or ship vendor/ as a second Source
export GOFLAGS="-mod=vendor"
export GOPROXY=off               # make any escape attempt fail loudly
```

`-mod=vendor` is already the default when `go.mod` declares Go ≥1.14 and
`vendor/` exists, but set it explicitly — relying on the implicit default means
a `vendor/` directory that fails to ship degrades to a silent network fetch.

**The `toolchain` directive is a hidden network dependency.** If `go.mod` says
`toolchain go1.26.6` and the build host has an older Go, the toolchain machinery
*downloads* the right one. In a sandbox that fails; on a networked laptop it
silently succeeds and nobody notices the dependency. Set `GOTOOLCHAIN=local` so
a mismatch fails immediately and legibly, and make the declared build dependency
match what the source actually requires.

Also check the requirement is satisfiable at all: `BuildRequires: golang >= 1.26`
is not a constraint if no supported release of the target distro ships it.

**When the project needs a newer Go than any target ships, `GOTOOLCHAIN=local`
is the wrong call** — it is the reproducibility-first advice above, and it makes
such a build fail outright. The recipe then has to set `GOTOOLCHAIN=auto`
explicitly and accept the network dependency, documenting that a sealed builder
must vendor a toolchain. Set it in the recipe rather than relying on a default,
because **distributions disagree about that default**: Red Hat patches
`GOTOOLCHAIN=local` into `go.env`, so a bare `go build` on RHEL 9 or 10 dies with
`go.mod requires go >= 1.27 (running go 1.26.7; GOTOOLCHAIN=local)`, while
Debian leaves it `auto`. Neither can be inferred from the other; check the
target with `go env GOTOOLCHAIN`.

**The bootstrap has its own floor, and it is not the version `go.mod` names.**
Fetching a newer toolchain only works from a recent enough Go: 1.24 can fetch
1.27, 1.22 fails with `toolchain not available`. So the declared build
dependency must name the version that can *bootstrap*, not the version the
module requires — a floor of `golang-go (>= 2:1.21~)` on a module needing 1.27
is simply false, and the lie is expensive: instead of a clean unsatisfiable
dependency naming a package and a version, the build dies deep inside
`go clean` with a message that explains nothing. Declare the version you have
actually built with, and verify it on the oldest target you claim to support.

### Reproducibility

`SOURCE_DATE_EPOCH` plus `-trimpath` gets you most of the way. Go binaries do not
embed a build timestamp the way C's `__DATE__` does, so the usual remaining
sources of variance are paths (fixed by `-trimpath`) and build-ids (fixed by
deriving them from content). Verify with `diffoscope` across two builds rather
than assuming.

## Rust

Closest to the C model. rustc invokes the system linker by default, so RELRO and
friends flow through, and most targets are PIE already. Distro wrappers exist
(`%cargo_build` / rust2rpm on Fedora, `dh-cargo` on Debian). `cargo vendor` is
the analogue of `go mod vendor` and the same network-isolation reasoning applies.
Standard DWARF, so debug packages work without Go's build-id workaround.

## C / C++

The case all the tooling was designed for. Distro build flags apply in full,
debuginfo extraction works, and dependencies come from real distro packages
rather than a language-level lockfile. The main packaging work is getting
`BuildRequires`/`Build-Depends` complete and letting the distro's flag macros do
their job instead of hardcoding `-O2`.

## Python

Pure Python is architecture-independent — the package should be `noarch` /
`Architecture: all` / `arch=('any')`. Compiled extensions are not, and a package
containing both is architecture-dependent.

Watch for: byte-compiled `.pyc` files (the distro macros handle placement and
they must not be shipped stale), shebang lines rewritten to the distro's
interpreter path, and the fact that pip-style dependency pinning has no
relationship to distro dependencies — you must express them again.

## Node

Bundles its dependency tree, which distros dislike and self-hosted packaging
usually tolerates. `node_modules` must be present at build time without network,
so vendor it. The result is architecture-independent unless a native addon is
compiled in, at which point it is not.

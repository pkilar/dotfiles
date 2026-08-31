# Multi-distribution, multi-architecture package builds

Working tooling to build a project's packages for any supported distribution in
a clean container, on both x86_64 and aarch64, without installing build
dependencies on the host. These were run, not sketched: the scripts here built
and linted five targets end to end (Fedora, RHEL 9, RHEL 10, Debian stable,
Arch) before being copied in.

They compose with the per-format templates beside them — `../rpm/`,
`../debian/`, `../arch/` — and call those directories' `build-*.sh` scripts.

## The model

**The container supplies the distribution. The machine supplies the
architecture.**

Nothing passes an architecture to the container engine: no `--platform`, no
`--target`, no `GOARCH`, no qemu. A build runs `podman run <image>` and the
package is tagged for whatever the host is, because the builder genuinely is
that. An x86_64 machine builds the x86_64 half of the matrix; an aarch64 machine
builds the other half; **neither can build the other's**.

That constraint is the price of the property that matters: it keeps working when
the project needs cgo, where cross-compiling needs a sysroot per *target
distribution* and emulation costs 5–15× on every compile. See
[`../../../references/multi-distro-builds.md`](../../../references/multi-distro-builds.md)
for the full argument.

## Files

| File | Goes to | Purpose |
|---|---|---|
| `targets.tsv` | `packaging/targets.tsv` | The single source of truth: what can be built, from which image, on which architectures |
| `targets.sh` | `packaging/targets.sh` | Reads the manifest; emits the CI matrix as JSON |
| `build-in-container.sh` | `packaging/build-in-container.sh` | Resolves a target and builds it; `--lint` also lints the result |
| `Makefile.include` | merge into `Makefile` | `make targets`, `build-package-<id>`, `lint-package-<id>`, `lint-packages` |
| `ci-packages.yml` | merge into a workflow | Two jobs: one emits the matrix from the manifest, one builds each row |
| `site.example/` | *outside* the repo | Internal repos, proxy and CA for a restricted network — see [its README](site.example/README.md) |

## Adapting them

1. **Rename.** The scripts reference `packaging/rpm/beacond.spec`,
   `packaging/rpm/beacond.rpmlintrc` and `packaging/debian/control`. Change
   `beacond` to your package name in `build-in-container.sh`. The rpmlintrc is
   optional — the driver lints without it if the file is absent.
2. **Edit `targets.tsv`.** Delete rows you do not support; add rows you do. Two
   things to check before adding one, both of which have bitten:
   - **Does the image publish that architecture?** The official `archlinux`
     image is amd64-only. `skopeo inspect --raw docker://<image> | jq -r
     '.manifests[].platform.architecture' | sort -u`
   - **Is the distribution's toolchain new enough?** Not merely present —
     Ubuntu 24.04 LTS ships Go 1.22, which cannot bootstrap the 1.27 a `go.mod`
     may require, and fails deep in the build rather than at dependency
     resolution.
3. **Check the build commands** in `build-in-container.sh` match your repo's
   layout (`./packaging/rpm/build-rpm.sh` and friends).
4. **Ignore the output directory** — add `dist/` to `.gitignore`.

## Behind a firewall

The build reaches the network three times: pulling the image, installing build
dependencies, and fetching language dependencies. Redirect all three:

- **The image** — point the `image` column in `targets.tsv` at an internal
  registry mirror. No code change.
- **Everything else** — a *site directory* passed with `--site DIR` or
  `PKG_SITE_DIR`, holding internal repo files, extra CA anchors, an `env` file
  and an optional `setup.sh`. Exactly one repository file is installed, chosen
  by target id (`rhel9.repo` for `rhel9`, `default.repo` as fallback) and
  installed under a prefixed name so it cannot clobber the distribution's own
  repo file, so one directory serves every distribution. Copy `site.example/` outside the
  repository and fill it in; its README has the layout and the traps.
- **Proxy variables** already set in your shell are forwarded automatically, by
  name rather than by value, so credentials embedded in a proxy URL never reach
  a command line or a build log.

Verified on RHEL 9: `env` sourced, CA installed **and trusted** (`trust list`
finds it), repo file placed, `setup.sh` run, build and lint clean. Pointed at a
deliberately unreachable proxy, dnf honoured it and failed with
`Could not resolve proxy` — which is what proves the forwarding works rather
than being silently ignored.

**The deb and arch site paths are unexercised.** Their destinations and refresh
commands follow the same pattern and are almost certainly right, but only the
rpm path was run end to end. Treat the first deb or arch use as the test.

## The parts worth keeping when you rewrite these

- **Build dependencies come from the recipe's own declarations** —
  `dnf builddep <spec>`, `mk-build-deps debian/control`, `makepkg -s` — never a
  package list maintained in the driver. This is what lets a distribution nobody
  anticipated work without editing the tooling.
- **The architecture assertion.** The container compares its `uname -m` against
  the host's and refuses on mismatch. With binfmt registered a leg can silently
  emulate, producing a correct-looking package very slowly. An unenforced
  convention is not a property.
- **Refusing an impossible request.** Asking for a target this machine's
  architecture cannot build exits non-zero. The all-targets loop consults the
  manifest and skips by name, so silence never means success.
- **The output directory is cleared per build.** The lint step inspects
  everything there and CI uploads it, so a leftover artifact from an earlier
  build gets linted as current and shipped as fresh.
- **Linter gates check exit status, not just output.** An earlier version passed
  `-f` to an rpmlint that wanted `-r`; the linter died with a usage error on
  every package and the job reported a clean pass, because "unrecognized
  arguments" does not match `: E: `. Each gate also asserts that at least one
  package was actually inspected.
- **A missing linter is stated, not skipped silently.** UBI 10 packages no
  rpmlint; the driver says the packages were BUILT but NOT LINTED rather than
  exiting quietly.

## Verified, and not

Built and linted end to end on x86_64: `fedora`, `rhel9`, `rhel10` (no rpmlint
available), `debian-stable`, `arch` — 13 artifacts with correct dist tags.

**The aarch64 half is designed and asserted but was never executed** — the work
was done on an x86_64 machine, so every arm64 row, and the driver's refusal path
when a target does not support the host architecture, remain unproven. Treat the
arm64 behaviour as reasoned, not demonstrated, until a run on ARM hardware says
otherwise.

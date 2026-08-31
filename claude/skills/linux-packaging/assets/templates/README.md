# Reference packaging templates

Working packaging for the same small Go daemon in all three formats. Every one
of these was built, linted, and inspected — they are not sketches.

The example software is `beacond`: a compiled daemon, an architecture-independent
shell client, a config file under `/etc`, a `profile.d` snippet that is *code*
rather than config, a systemd unit, a dedicated system user, and a log directory.
That set was chosen because it exercises all eight decisions in `SKILL.md`.

Use these as a starting point, not a stencil. Copy the structure and the
reasoning; replace the specifics. The inline comments explain *why* each choice
was made, which is the part worth carrying over.

## Where these go in a repo

These are the contents of `packaging/rpm/`, `packaging/debian/`, and
`packaging/arch/`. The surrounding layout matters as much as the recipes:

```
VERSION                  # one line, no "v" — the only place the version is written
packaging/
├── rpm/                 # these templates
├── debian/
├── arch/
├── targets.tsv          # multi-distro/: what can be built, and on which arches
├── targets.sh           # multi-distro/: manifest reader + CI matrix emitter
├── build-in-container.sh # multi-distro/: build one target in a clean container
└── <shared-asset>/      # anything more than one format installs: ONE copy
```

`multi-distro/` is the fourth directory here, and it is not a format: it is the
tooling that builds the other three for a distribution you are not running, on
either architecture, without installing build dependencies on the host. See its
own [README](multi-distro/README.md).

Each format derives its version from `VERSION` rather than restating it, and the
build scripts rewrite the format's own version field in a staging copy so the two
cannot drift. `references/repo-layout.md` has the mechanics and the traps;
`scripts/audit-layout.sh` checks an existing repo against it.

## What each one demonstrates

| | RPM | Debian | Arch |
|---|---|---|---|
| Split into daemon + arch-independent client | `%package -n` + `BuildArch: noarch` | two stanzas, `Architecture: any` / `all` | `pkgname` array, `arch=('any')` override |
| Config preserves site edits | `%config(noreplace)` | automatic conffile | `backup=()` |
| `profile.d` code always replaced | shipped unmarked | **symlink from `/usr/lib`** — verified to produce an empty conffiles list | omitted from `backup=()` |
| Service user | `%sysusers_create_compat` in `%pre` | `dh_installsysusers`, called explicitly (not auto-sequenced at compat 13) | `sysusers.d`, applied by a pacman hook |
| Unit policy | `%systemd_post` triad, honours presets | `dh_installsystemd` default | never enabled |
| Directory ownership | explicit `%dir` for every custom path | `.dirs` | `install -Dm` |
| Version source | `VERSION` file with an in-spec fallback | `debian/changelog` | `pkgver` |

## Verified state

- **RPM** — builds on Fedora; `%dir` covers every custom directory; `rpm -qcp`
  confirms only the real config is marked, and the `profile.d` script is not.
- **Debian** — builds on `golang:1.26-bookworm`; lintian clean apart from
  `no-manual-page` and the known Go `shared-library-lacks-prerequisites` false
  positive; the client's conffiles list is empty, proving the symlink technique.
- **Arch** — builds with `makepkg`; namcap reports only a `curl` dependency
  false positive; `.PKGINFO` confirms `backup=` on the config and `arch = any`
  on the client.

## Known warts

- Both `build-deb.sh` and `build-rpm.sh` fall back to `rsync` when the tree is
  not a git checkout, without declaring it as a prerequisite. If you reuse these
  scripts, either declare the dependency or drop the fallback.
- `debian/control` sets `Standards-Version: 4.6.2`, which trails current. Bump it
  after reading the upgrading checklist rather than blindly.
- The Arch `PKGBUILD` reads `pkgver` from the `VERSION` file via command
  substitution. That is fine for a local build driven by a wrapper, but the AUR
  expects a literal `pkgver` or a `pkgver()` function — change it before
  publishing there.

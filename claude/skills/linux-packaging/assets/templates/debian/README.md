# Debian / Ubuntu packaging

A `debhelper` multi-binary source package producing two packages from one
source tree.

## Packages produced

| Package          | Contents                                                              | Architecture |
| ---------------- | ---------------------------------------------------------------------| ------------ |
| `beacond`        | daemon binary, systemd unit, `beacond.yaml` config, sysusers/tmpfiles | any          |
| `beacond-client` | `beacon-status` script, `/etc/profile.d/` shell integration          | all          |

`beacond-client` does not depend on `beacond`: it only ever talks to a
`beacond` endpoint over the network, commonly on a different host.

## Build

```sh
# Prerequisites: build-essential debhelper dpkg-dev fakeroot, plus Go >= 1.22
# on PATH (newer than Debian stable's golang-go -- use the golang:1.26
# image or similar, or a manual toolchain install).
./packaging/debian/build-deb.sh
# -> packages land in ./debbuild/*.deb

sudo apt install ./debbuild/beacond-client_*.deb   # or dpkg -i + apt -f install
```

`build-deb.sh` stages a source snapshot from the working tree and pins
`debian/changelog`'s version from the top-level `VERSION` file. It uses the
`3.0 (native)` source format, so there is no separate upstream tarball to
manage -- this project is built and distributed in-house, not uploaded to a
Debian archive (where a non-native format would be expected instead).

## Decisions worth knowing before changing this tree

- **Version**: single source of truth is the top-level `VERSION` file
  (`build-deb.sh` stamps it into `debian/changelog` at build time). Native
  source format, so the changelog version has no Debian-revision suffix.
- **`/etc/beacond/beacond.yaml`** is real site configuration and is a normal
  dpkg conffile (the `/etc` default) -- edits survive upgrades.
- **`/etc/profile.d/beacon-env.sh`** is code, not configuration, so it is
  *not* a plain file under `/etc`. The real file lives at
  `/usr/lib/beacond/beacon-env.sh` (an ordinary, non-conffile package file)
  and `/etc/profile.d/beacon-env.sh` is a symlink to it
  (`beacond-client.links`), which structurally guarantees every upgrade
  replaces its content -- there is no plain `/etc` file an admin could edit
  and thereby freeze out future fixes. Site overrides belong in the
  package-owned-but-empty `/etc/beacon/` directory
  (`beacond-client.dirs`), in a `beacon-site.sh` the admin creates and this
  package never touches. See `beacond-client.README.Debian`.
- **Service user**: `beacon`, created via `sysusers.d` + `dh_installsysusers`
  (explicitly invoked in `debian/rules`, immediately before
  `dh_installtmpfiles`, since `dh_installsysusers` is not auto-sequenced
  until debhelper compat 14). Never deleted, including on purge.
- **State**: `/var/lib/beacond` (the account's home) and `/var/log/beacond`
  (0750 `beacon:beacon`) are created by `tmpfiles.d`, not shipped as
  package-owned empty directories.
- **systemd**: `dh_installsystemd` runs at its default policy -- enabled and
  started on install, restarted on upgrade. That default is deliberately
  *not* overridden to `--no-enable --no-start`: unlike a service that needs
  site config or another host, `beacond` works immediately with the packaged
  config, and a restart on upgrade is safe since it is stateless.
- **Go build**: `CGO_ENABLED=0`, `-trimpath`, `-buildmode=pie` (ASLR
  hardening); the actual compile is delegated to `$(MAKE) build` so
  packaging cannot drift from the upstream `Makefile`'s `-ldflags`. `dh_dwz`
  is skipped (dwz does not reliably parse Go's DWARF); `dh_strip` is left at
  its default so a real `beacond-dbgsym` package is produced, since the
  Makefile does not pre-strip with `-s -w`.
- **`Rules-Requires-Root: no`**: nothing in this build needs real root: all
  ownership (the `beacon` user, `/var/log/beacond`) is established at
  install time by `systemd-sysusers`/`systemd-tmpfiles`, not baked into the
  package's own file ownership metadata.

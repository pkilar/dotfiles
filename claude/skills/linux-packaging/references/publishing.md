# Signing, publishing, and the official-repo fork

Two different games. Self-hosted distribution — you build the packages and serve
them — is pure mechanics and is what most projects need. Submission to a
distro's own repositories adds a human gatekeeper and a substantially higher
bar. This file covers the mechanics first, then says exactly what changes if you
go official, so you know which rules you can skip.

## Contents

- [Signing](#signing)
- [Serving a repository](#serving-a-repository)
- [Consumer configuration](#consumer-configuration)
- [What changes for official repositories](#what-changes-for-official-repositories)

## Signing

Signing a package and signing the repository *index* are different things, and
conflating them leaves a real hole.

| | Sign the package | Sign the index |
|---|---|---|
| RPM | `rpm --addsign pkg.rpm` (or `rpmsign`) | **Separate step** — detached-sign `repodata/repomd.xml` after every `createrepo_c` run |
| Debian | `dpkg-buildpackage -k<keyid>`, or `debsign` after the fact | `InRelease` (inline-signed) and/or `Release` + `Release.gpg` — `reprepro`'s `SignWith:` does it |
| Arch | `makepkg --sign`, or `SIGNKEY` in `makepkg.conf` | `repo-add -s -k <keyid>` signs the database |

**The RPM case is the one people get wrong.** `createrepo_c` does not sign
metadata. If every `.rpm` is signed but `repomd.xml` is not, an attacker with
write access to the repo can serve an older, still-validly-signed version of a
package — a downgrade attack that forges no signature at all. Sign both layers.

## Serving a repository

```sh
# RPM
createrepo_c /srv/repo/el9/x86_64/
gpg --detach-sign --armor /srv/repo/el9/x86_64/repodata/repomd.xml

# Debian — reprepro reads conf/distributions, including `SignWith: <keyid>`
reprepro -b /srv/repo includedeb stable ./*.deb
# aptly is the alternative when you want snapshots and S3 publishing

# Arch
repo-add -s -k <keyid> /srv/repo/myrepo.db.tar.gz ./*.pkg.tar.zst
```

Serve over HTTPS. The signature protects integrity; TLS protects the fact of
what you fetched, and costs nothing.

## Consumer configuration

```ini
# RPM — /etc/yum.repos.d/myrepo.repo
[myrepo]
name=My Repo
baseurl=https://repo.example.com/el9/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://repo.example.com/RPM-GPG-KEY-myrepo
```

`gpgcheck` defaults to off. A repo file you ship without it is unverified by
default — set it explicitly.

```
# Debian — /etc/apt/sources.list.d/myrepo.sources
Types: deb
URIs: https://repo.example.com/debian
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/myrepo.asc
```

`apt-key` is deprecated and was removed in Debian 13. Do **not** drop keys into
`/etc/apt/trusted.gpg.d/` — that trusts the key for every repository on the
system, so a second, unrelated repo could then serve packages "signed" by a key
the admin only meant to trust for you. `Signed-By` scopes trust to one source,
which is the entire point of the post-`apt-key` model.

```ini
# Arch — /etc/pacman.conf
[myrepo]
SigLevel = Required DatabaseOptional
Server = https://repo.example.com/arch/$arch
```

`SigLevel = TrustAll` exists for debugging. It is never the answer for a real
repository.

Whatever you do, never ship a repo definition with verification disabled as a
"temporary" fix for a key-distribution problem. It is the one packaging mistake
that converts a broken build into a supply-chain vulnerability, and temporary
configuration is not.

## What changes for official repositories

Everything above is all self-hosting requires. None of the following applies
unless you are submitting to a distribution.

| | Extra requirement | Notes |
|---|---|---|
| **Fedora** | A **sponsor** if you are not already in the `packager` group | Flag the review request `FE-NEEDSPONSOR` |
| | A formal **package review** in Bugzilla | A reviewer works the MUST/SHOULD guideline list against your spec and SRPM |
| | Dependencies **must be vendored and declared**, and bundling is scrutinised | `bundled(golang(...))` provides, generated from `vendor/modules.txt` |
| | Run `fedora-review` on your own package first | Worth running regardless — it catches real bugs |
| **Debian** | A **sponsor** (DD or DM) if you are neither | Upload signed to `mentors.debian.net`; they review, build, and upload |
| | The **ftp-master NEW queue** | Every genuinely new package is manually vetted, with particular attention to `debian/copyright` against the DFSG. Their opinion is binding |
| | A complete, accurate, machine-readable `debian/copyright` | This is usually the single largest piece of work, and it is a real audit of every file's licence — not a formality |
| | Lintian-clean, in practice | Not a formal gate, but no sponsor will touch a package that isn't |
| **AUR** | No sponsor, no review — anyone can push | The trust model is post-hoc: Trusted Users flag and orphan bad packages, nobody pre-screens |
| | `.SRCINFO` regenerated and committed with every change | `makepkg --printsrcinfo > .SRCINFO`. The web UI reads only this file, not the `PKGBUILD` |
| | `namcap` clean by community norm | Not enforced at push time |

The honest summary: Fedora and Debian cost you a human review cycle measured in
weeks and a genuine licence audit. The AUR costs you almost nothing procedurally
but offers correspondingly little assurance to the people installing your
package. Self-hosting costs you a signing key and a web server.

One thing worth carrying back from the official rules even when self-hosting:
they assume the build has **no network access**. Structuring for that is what
makes a build reproducible by someone who is not you, on a machine that is not
yours — which is worth having regardless of where the package ends up.

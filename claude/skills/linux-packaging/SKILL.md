---
name: linux-packaging
description: >-
  Create, audit, and fix native Linux packaging for Red Hat/Fedora/RHEL (RPM .spec),
  Debian/Ubuntu (debian/ + debhelper), and Arch (PKGBUILD) — split packages, systemd
  units, service users, config-file upgrade semantics, repo publishing, and
  containerized build/install/upgrade verification. Use this skill whenever the user
  mentions packaging, RPM, .spec, rpmbuild, .deb, debian/, dpkg-buildpackage, PKGBUILD,
  makepkg, AUR, rpmlint, lintian, namcap, "ship this as a package", "make it
  installable", "build an installer for Linux", distro repos, or asks why an upgrade
  clobbered a config file, failed to restart a daemon, or left files behind on
  uninstall — even if they never name a specific distribution.
---

# Linux Distribution Packaging

Packaging is easy to fake and hard to get right. A `.spec` file that looks
correct, a `debian/control` that parses, and a `PKGBUILD` that runs are all
cheap to produce and tell you almost nothing. The bugs that matter — a config
file silently replaced, a daemon that never restarts, a user that isn't created
before the files it owns land, a version that sorts backwards so upgrades stop
arriving — only appear when a real package manager installs a real package on
top of an older one.

So the standard here is empirical: **you have not packaged anything until a
package manager has installed it, and then upgraded it, in a clean container.**
Reading the files you just wrote is not verification. See
[Verification](#verification-the-only-part-that-proves-anything).

That standard governs what you may *claim*. It is not the fastest way to *find*
problems — reading is, and container work is slow enough that leading with it
will burn a whole budget on one format while defects sit unread in the others.
When auditing, sweep broadly first and verify what matters most; see
[Mode B](#mode-b-audit-existing-packaging).

## Pick your mode

| The user wants | Go to | Typical phrasing |
|---|---|---|
| Packaging that doesn't exist yet | [Mode A: Author](#mode-a-author-packaging-from-scratch) | "package this for Debian", "ship an RPM", "make it installable" |
| A review of packaging that exists | [Mode B: Audit](#mode-b-audit-existing-packaging) | "is our packaging any good", "review the spec file", "why did lintian complain" |
| One specific thing changed or fixed | [Mode C: Targeted fix](#mode-c-targeted-fix) | "the upgrade wipes my config", "add a systemd unit", "port our RPM to Arch" |

All three modes share the decision core below and the same verification bar.
If the user's request spans modes — "audit this and fix what you find" — run
Mode B to completion first, agree on findings, then apply fixes as Mode C.

## The decision core

Almost every packaging bug traces back to one of eight decisions made wrong or
made implicitly. Settle these *before* writing files, because each one lands
differently in each format and retrofitting them means rewriting all three.

| # | Decision | Why it is load-bearing |
|---|---|---|
| 1 | **What are the packages?** | The split determines everything else. Arch-dependent binaries and arch-independent scripts/data cannot share a package without lying about the architecture. |
| 2 | **How does the version map?** | The three formats order versions by genuinely different algorithms, and the familiar `1.0~rc1` fix is correct on two of them and backwards on the third. Get it wrong and upgrades silently stop arriving. |
| 3 | **Is each `/etc` file config or code?** | Config must survive site edits; code must be replaced. The formats disagree about the default, and Debian makes *every* `/etc` file config unless you work around it. |
| 4 | **Who creates the service user?** | The user must exist before files owned by it are installed, and must not be deleted while files still reference it. |
| 5 | **Where does mutable state live?** | `/var/log`, `/var/lib`, `/run`. Shipping these as package-owned directories vs. declaring them in `tmpfiles.d` changes ownership, permissions, and what happens on uninstall. |
| 6 | **Enable/start on install; restart on upgrade?** | Distros disagree by *policy*, not preference. Restarting a daemon mid-upgrade is sometimes the correct behavior and sometimes an outage. |
| 7 | **What toolchain builds it, and is there network?** | Some build environments forbid network access, which forces vendoring. A `BuildRequires` the target distro cannot satisfy makes the package unbuildable there — verify the constraint is real, not aspirational. |
| 8 | **Is any of this per-deployment or secret?** | Keys, certificates, and site-specific blobs usually should not be in a package at all. If they must be, the package must be structurally incapable of reaching a public repo. |

**Why these are load-bearing, concretely.** Take decision 3 and one file: a
`profile.d` snippet that is *code*, so it must be replaced on upgrade or bug
fixes never reach anyone. RPM ships it unmarked and upgrades replace it. Arch
omits it from `backup=()`, same effect. Debian **cannot express it directly** —
every regular file staged under `/etc` becomes a conffile — so you ship the real
file under `/usr/lib` and symlink to it, because a symlink is never a conffile.
One intent, three encodings, one of them a workaround. Miss it and a subset of
your users silently stop receiving fixes, with nothing in any log to say so.

The per-format expression of each decision is in the distro references below;
the cross-cutting comparison tables (version ordering, config semantics, user
creation, unit policy) are in
[`references/cross-distro.md`](references/cross-distro.md). Read that file
before writing packaging for more than one distro — it exists specifically to
stop you carrying one distro's idiom into another, which is the most common way
multi-distro packaging goes wrong.

## Mode A: Author packaging from scratch

1. **Settle the repository layout first** if the project has none — everything
   packaging-related under `packaging/<format>/`, anything shared by more than
   one format in its own sibling directory, and a single top-level `VERSION`
   that every format derives from rather than restates. It costs nothing on day
   one and is expensive to retrofit, because it touches every format at once.
   See [`references/repo-layout.md`](references/repo-layout.md).
2. **Inventory the software.** What binaries, scripts, config, units, and data
   exist? What does it need at runtime that the package must declare? Read the
   build system rather than guessing — a `Makefile` `install` target usually
   already encodes the intended layout, and reusing it keeps packaging and
   upstream from drifting.
3. **Settle the eight decisions** above, explicitly. Where the answer isn't
   determined by the software, say what you chose and why. If a decision
   genuinely depends on operator intent — most often #6 (should this start on
   install?) and #8 (should this ship at all?) — ask rather than assume; both
   have safe-but-annoying and dangerous-but-convenient answers.
4. **Write the packaging**, one format at a time, consulting that format's
   reference. Do not write all three by copying the first — translate each
   decision into that format's idiom.
5. **Verify** every format through the ladder below. Fix what it finds. To build
   for distributions you do not run, lift the working tooling in
   [`assets/templates/multi-distro/`](assets/templates/multi-distro/) rather
   than writing your own — a manifest, a container driver, make targets and CI
   jobs that were run against five distributions.
6. **Report** what you built, what you verified, and what you could not.

Prefer a shared source of truth over three copies. One `VERSION`, one copy of
each shared asset, referenced by all three packagings, is the difference between
packaging that stays correct and packaging that rots — a file duplicated per
format gets edited in one and forgotten in the others, which review will not
catch. Where the formats genuinely require different content (env-file paths and
helper-script locations differ by distro convention), keep the files separate but
otherwise identical, and treat any *other* drift between them as a bug.
[`references/repo-layout.md`](references/repo-layout.md) has the layout and the
version-injection mechanics.

## Mode B: Audit existing packaging

Order matters here, and the intuitive order is wrong. Verification is what
*proves* a finding, but reading is what *discovers* most of them — and container
work is slow enough that starting there will consume the whole budget on one
format while defects sit unread in the other two.

So: cheap and complete first, expensive and deep second.

1. **Inventory, including the layout.** Which formats exist, which packages each
   produces, which assets are shared, and where the build entry points are.
   `scripts/audit-layout.sh` answers most of this in one pass and flags the
   organisational defects — a version hardcoded where it should be derived, an
   asset duplicated per format, a build tree committed to git. Those are cheap
   to find and they predict where the *semantic* drift will be, because a file
   duplicated three times is a file that was updated once.
2. **Static sweep across every format**, before touching a container. Walk the
   eight decisions against each recipe and write down what you find. This is the
   highest-yield step per minute spent: most config-semantics, scriptlet,
   dependency-name, and architecture defects are plainly visible in the recipe
   once you know to look. Do this for *all* formats before going deeper in any.
3. **Build each format.** A tree that no longer builds is itself a finding —
   record the exact failure and **move on to the next format**. A broken build
   must never stop the audit of the others, and it does not invalidate the
   static findings you already have.
4. **Lint the built packages**, not just the recipes — `rpmlint` for RPM,
   `lintian` for Debian, `namcap` for Arch. Triage every finding into *real bug*,
   *expected noise for this language*, or *deliberate deviation*, and say which.
   This step routinely finds defects the install and upgrade tests pass straight
   through; see [Linting is not optional](#linting-is-not-optional).
5. **Verify the most severe findings** by install and upgrade in clean
   containers. Use depth to confirm and to rank what you already suspect, not to
   discover from scratch. A dependency name that does not resolve, or a config
   file whose site edits vanish, is worth the container time; a missing
   `%license` is not.
6. **Cross-format parity.** When a project ships more than one format, diff what
   they actually produce — file lists, users, config treatment, unit policy. A
   file added to one format and forgotten in the others is common, invisible in
   review, and breaks exactly one class of user. `scripts/parity-check.sh`
   compares built packages across formats and reports the drift.
7. **Report** with severity, evidence, and the minimal fix.

If the budget runs short, a complete static sweep with one or two findings
proven beats a deep investigation of a single format. Coverage is the thing the
user cannot get later; proof they can ask you for.

One check earns its place in every audit because it is cheap and catches a bug
nothing else does: **resolve every declared dependency name against the actual
target archive.** Package names differ across distributions, so a name carried
over from a sibling format produces a package that builds clean, lints clean,
and cannot be installed at all. `apt-cache policy <name>`, `dnf info <name>`,
`pacman -Si <name>`.

Rank findings by what they do to a user, not by how much they offend a style
guide. "Upgrade discards site config" outranks a dozen naming warnings.

## Mode C: Targeted fix

Change the smallest thing that fixes the problem, then verify at the tier that
would have caught it. A conffile bug needs the upgrade test; a dependency bug
needs the clean-container install; a typo in a description needs neither.

Resist the urge to rewrite surrounding packaging you find distasteful while
you're in there. Packaging accretes deliberate-looking oddities that encode a
production incident someone had at 3am — check the commit message before
"simplifying" something strange. If you believe adjacent code is wrong, say so
in your report and let the user decide.

## Verification: the only part that proves anything

Climb until the tier that would catch the class of bug you could have
introduced. Each tier catches what the ones below it structurally cannot.

| Tier | What you do | Catches | Cost |
|---|---|---|---|
| 0 | Recipe parses / lints | Syntax, obvious metadata errors | Seconds |
| 1 | Package builds **from a pristine export** | Missing files, bad paths, unresolved macros, unsatisfiable build deps, recipes referencing gitignored files | ~1 min |
| 2 | **Lint the *built* package** — `rpmlint`, `lintian`, `namcap` | Missing runtime deps, unowned files, wrong permissions, scriptlets naming build-time paths. Catches defects that are invisible in the recipe *and* survive a clean install | Seconds |
| 3 | Install into a clean container | Dependency gaps, install scriptlet failures, file conflicts | ~1 min |
| 4 | **Upgrade N → N+1** | Conffile handling, upgrade scriptlets, restart policy, version ordering | ~2 min |
| 5 | Real init system / real hardware | Unit activation, socket/device access, SELinux | Expensive |

Two cheap ways to make the ladder weaker than it looks: building tier 1 from
your working tree rather than a clean export, which hides any recipe that
references an untracked file; and installing only the subpackage you are working
on, which hides a sibling that cannot be installed at all.

### Linting is not optional

Tier 2 is cheap, and it is the only tier that reads the *metadata* of what you
built. Tiers 3 and 4 exercise a package on a host that already has whatever the
package forgot to declare, so they pass straight through a whole class of defect.
Three found this way, in packaging that built, installed and upgraded cleanly on
all three formats:

- a `logrotate` config with nothing depending on logrotate, so rotation silently
  never ran and the log directory grew without bound;
- a `%post` that ran `systemd-tmpfiles --create` against the *builder's* SOURCES
  directory, failing silently on every host — and passing the install test,
  because `%files` shipped the same directories anyway;
- a log directory owned `0700` by a service account that logrotate would have
  processed as root, for want of an `su` directive.

Run `rpmlint`, `lintian` and `namcap` on the built artifacts, keep the
justifications next to the suppressions, and **wire all of it into CI so it runs
on every change** — packaging rots between releases precisely because nothing
exercises it between releases. A matrix leg per format costs a couple of minutes
and runs in parallel with the existing jobs. See
[`references/verification.md`](references/verification.md) for the linter traps
(rpmlint silently ignores a TOML filter file, and `namcap` always exits 0), the
gate design that makes a failing linter fail the build rather than read as clean,
and a worked CI job.

**Tier 4 is the one that matters and the one everybody skips.** Upgrade is the
only moment when old and new package state interact, so it is the only test
that exercises the scriptlet paths where production breaks. A fresh install
proves almost nothing about an upgrade.

`scripts/verify-package.sh` runs tiers 1–4 in a container for any of the three
formats. Use it rather than hand-rolling container invocations. On a restricted
network it takes `--site DIR` for internal repositories, a corporate CA and an
`env` file, and forwards proxy variables automatically — see
[`references/multi-distro-builds.md`](references/multi-distro-builds.md#restricted-networks):

```sh
scripts/verify-package.sh --format deb --repo . --build-cmd './packaging/debian/build-deb.sh' \
    --expect-user beacon --expect-files '/usr/bin/beacond /etc/beacond/beacond.yaml'
scripts/verify-package.sh --format rpm --repo . --build-cmd './build-rpm.sh' --upgrade-from ./dist/old
```

`scripts/parity-check.sh --rpm DIR --deb DIR --arch DIR` compares what the
formats actually ship, for projects maintaining more than one.

A caution learned the hard way while building these: verification tooling can
lie. An early version of `verify-package.sh` piped its install command into
`tail`, which discarded the exit status and reported a confident PASS for an
install that had actually failed. When a check passes, satisfy yourself it
*could* have failed — assert a post-condition, don't trust a command's silence.

Read [`references/verification.md`](references/verification.md) for the manual
recipes, the per-format inspection cheat-sheet, and what each tier genuinely
cannot test.

Be precise about coverage when you report. "Builds and installs cleanly on
Fedora 43; upgrade path tested 1.4.1 → 1.4.2; not tested under a live systemd"
is useful. "Verified" is not.

### Suppressing a linter finding

Suppression is sometimes right — linters encode assumptions that don't hold for
every language or layout. It is also the easiest way to make a real bug
disappear, so treat each one as a claim you have to justify: name the finding,
say why it does not apply here, and record that justification next to the
suppression rather than in a commit message nobody will find. If you cannot
articulate why it's wrong, it probably isn't.

Two honest categories recur: findings that reflect a language's build output
rather than your packaging (Go binaries and RELRO/debug-symbol checks are the
usual example), and findings that contradict a deliberate security choice
(a config file that is mode `0640` because it holds a credential). Both deserve
a written reason. Everything else deserves a fix.

Then prove the suppression file actually suppresses, because one that is loaded
but ineffective looks exactly like a clean package: check that the tool's
filtered count moves when you pass it, and run it against a package you know is
bad to confirm the findings you did *not* filter still fire. rpmlint in
particular will accept a TOML filter file, report it as loaded, and filter
nothing.

## Distro references

Read the reference for the format you are working in. They assume the decision
core above and cover the format's specifics, its idioms, and the traps that are
unique to it.

| Format | Reference | Read it when |
|---|---|---|
| Repository layout | [`references/repo-layout.md`](references/repo-layout.md) | Setting up packaging in a repo, or auditing how it is organised — the `packaging/` tree, shared assets, and the single `VERSION` file |
| RPM (Fedora, RHEL, CentOS, Amazon Linux, openSUSE) | [`references/rpm.md`](references/rpm.md) | Writing or auditing a `.spec` |
| Debian (Debian, Ubuntu, derivatives) | [`references/debian.md`](references/debian.md) | Writing or auditing `debian/` |
| Arch | [`references/arch.md`](references/arch.md) | Writing or auditing a `PKGBUILD` |
| All of them | [`references/cross-distro.md`](references/cross-distro.md) | Any multi-distro work, or any of decisions 2–6 |
| Many distros / both arches | [`references/multi-distro-builds.md`](references/multi-distro-builds.md) | Building for distributions you do not run — the container-per-distro model, the target manifest, why native beats cross-compiling and emulation once cgo is involved, and **building behind a firewall** (internal repos, proxy, corporate CA) |
| Language specifics | [`references/languages.md`](references/languages.md) | The software isn't C — Go, Rust, Python, Node have distinct build/strip/vendor concerns |
| Signing & publishing | [`references/publishing.md`](references/publishing.md) | Shipping packages to users — GPG signing, hosting a repo, and what changes if you target Fedora review, Debian mentors, or the AUR |
| Verification & tooling | [`references/verification.md`](references/verification.md) | Running the ladder by hand, or CI |

Self-hosted distribution — you build the packages and serve them yourself — is
the default assumption throughout. Official repositories impose substantial
extra requirements that do not apply to you otherwise; `official-repos.md` says
which rules you can skip and which you cannot.

## Reporting

For an audit, lead with what a user would actually suffer, then the evidence:

```
## Findings

### 1. [severity] One-line statement of the defect
**Breaks:** the concrete scenario — who does what, and what goes wrong.
**Evidence:** file:line, or the command output that demonstrates it.
**Fix:** the minimal change.

## Verified
What you built, installed, and upgraded — with versions and images.

## Not verified
What you could not test, and why. Be specific; this is where the residual
risk lives.
```

For authoring, state the eight decisions you made and why, then the same
verified/not-verified split. The decisions are the part a reviewer needs to
check; the files are just their consequence.

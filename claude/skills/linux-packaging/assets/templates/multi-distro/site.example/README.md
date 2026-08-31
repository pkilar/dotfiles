# Site directory (example)

Everything the build needs to reach a network it is not allowed to reach
directly. Copy this tree somewhere **outside the repository**, fill it in, and
pass it with `--site DIR` or `PKG_SITE_DIR`.

It lives outside the repo deliberately: internal mirror hostnames and proxy URLs
are site-specific and usually not public, so they must not be committed.

```
site/
├── env                      # sourced before anything hits the network
├── ca/*.crt                 # trust anchors, installed and trusted per format
├── rpm/
│   ├── rhel9.repo           # used for the rhel9 target
│   ├── fedora.repo          # used for the fedora target
│   └── default.repo         # fallback for any rpm target with no file of its own
├── deb/
│   └── debian-stable.list   # or .sources
├── arch/
│   └── arch.mirrorlist      # destination is always /etc/pacman.d/mirrorlist
└── setup.sh                 # optional, runs last, can override the rest
```

**Exactly one repository file is installed, chosen by target id.** That is what
lets this one directory serve every distribution: `rhel9.repo` and `fedora.repo`
sit side by side and never collide. `default.<ext>` is the fallback where
several targets share a mirror — an RPM `baseurl` using `$releasever` usually
serves rhel9 and rhel10 from one file.

The file lands under a **prefixed** name — `rhel9.repo` becomes
`/etc/yum.repos.d/00-site-rhel9.repo`. A target id is often the distribution's
own repo filename (`fedora.repo`, `rocky.repo`, `ubi.repo` all ship there), and
overwriting one deletes the base repository; the build then fails with
`No match for argument: make`, which says nothing about the cause. Arch is the
deliberate exception — its destination stays `/etc/pacman.d/mirrorlist`.

A directory holding files that match nothing is reported, naming both the
pattern looked for and what was found. A silent skip would leave the build
pointed at unreachable default mirrors, to fail later somewhere that says
nothing about the cause.

Applied in that order, and the order matters: the CA has to be trusted before an
HTTPS mirror is contacted, and the mirrors have to exist before the first
install.

Proxy variables already set in your shell — `http_proxy`, `https_proxy`,
`no_proxy`, their uppercase forms, and `GOPROXY`, `GOSUMDB`, `GONOSUMDB`,
`GOPRIVATE`, `GOFLAGS` — are forwarded automatically, **by name rather than by
value**, so a proxy URL carrying credentials never reaches a command line, `ps`,
or a build log. Put anything else in `env`, which is sourced for the same reason.

The container image is not covered here: point the `image` column in
`targets.tsv` at an internal registry mirror.

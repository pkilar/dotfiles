# beacond.spec
#
# Reference RPM packaging for beacond, a small heartbeat daemon with zero
# module dependencies (see go.mod / README.md "Build"). Produces two binary
# packages:
#
#   beacond         -- the daemon, its systemd unit, and its config.
#                      Architecture-dependent (it ships a compiled binary).
#   beacond-client  -- the beacon-status status-check script. BuildArch:
#                      noarch, and deliberately carries no dependency on the
#                      beacond package: it talks to a beacond over HTTP and
#                      may run against a remote host with no local beacond
#                      installation at all.
#
# Build with packaging/rpm/build-rpm.sh, which stages a source tarball from
# the working tree and passes the real version via `--define beacond_version`.

# %%{beacond_version} is normally injected by build-rpm.sh, which reads it
# from the top-level VERSION file -- the single source of truth (see
# README.md, "Version"). The fallback below only fires for a bare
# `rpmbuild -ba beacond.spec` invocation with no --define: it lets the spec
# parse cleanly and fail later, at a well-understood point (the missing
# Source0 tarball, in %%prep), instead of carrying a literal, unexpanded
# "%%{beacond_version}" into %%{name}-%%{version} paths and failing obscurely.
%{!?beacond_version: %global beacond_version 0.0.0}

# Fedora's guidelines require a written reason whenever debuginfo generation is
# switched off, so: this binary is built by Go's internal linker, and Fedora's
# find-debuginfo pipeline cannot process the result. Two separate failures show
# up, in order -- first "No build ID note found" from --strict-build-id, because
# Go emits no NT_GNU_BUILD_ID note; then, once a build-id is injected by hand,
# "eu-strip: illformed file" and "No debugging symbols", because eu-strip cannot
# read Go's DWARF either.
#
# Producing a genuinely useful -debuginfo package would mean forcing
# `-linkmode=external -compressdwarf=false` (what Fedora's own %%gobuild macro
# does), which pulls in a C toolchain and gives up the static binary this
# project deliberately builds. That trade is not worth it here, so debuginfo is
# off. Revisit if this ever grows cgo dependencies.
%global debug_package %{nil}

Name:           beacond
Version:        %{beacond_version}
Release:        1%{?dist}
Summary:        Small heartbeat daemon that answers /health

License:        MIT
URL:            https://github.com/example/beacond
# Generated locally by build-rpm.sh (a tar of the working tree, not a
# published upstream release -- this example project has no release URL).
# Regenerate with: packaging/rpm/build-rpm.sh
Source0:        %{name}-%{version}.tar.gz
Source1:        beacond.service
Source2:        beacond.sysusers
Source3:        beacond.sysconfig

BuildRequires:  golang
BuildRequires:  make
BuildRequires:  systemd-rpm-macros
# shadow-utils backs %%sysusers_create_compat's fallback path for targets
# where systemd-sysusers itself is unavailable.
Requires(pre):  shadow-utils
%{?systemd_requires}

%description
beacond is a small heartbeat daemon. It reads a config file, listens on a
TCP port, and answers /health with the build version.

This package installs the beacond binary, its systemd unit, and its
configuration under /etc/beacond.

%package -n beacond-client
Summary:        Status-check client for a beacond instance
BuildArch:      noarch
Requires:       bash
Requires:       curl
# Deliberately no "Requires: beacond" -- beacon-status queries a *remote*
# beacond instance's /health endpoint over HTTP (see BEACON_ENDPOINT / -e).
# It has no functional dependency on the daemon being installed locally.

%description -n beacond-client
beacon-status is a small bash client that queries a beacond instance's
/health endpoint over HTTP and reports whether it answered. Point it at any
reachable beacond -- local or remote -- via BEACON_ENDPOINT or -e; it does
not require the beacond daemon package to be installed.

%prep
%autosetup

%build
# Keep the build hermetic: no network, and no writes outside the build tree.
# beacond has zero module dependencies (see go.mod), so GOPROXY=off never
# actually has anything to fetch -- this just makes that guarantee explicit.
export GOPROXY=off
export GOCACHE="$(pwd)/.gocache"
export GOPATH="$(pwd)/.gopath"
# Reuse the project's own build recipe (version stamping, -trimpath, and a
# stable -buildid all live in the Makefile) instead of re-deriving the go
# build invocation here, so packaging can't drift from how upstream builds
# the same binary.
#
make build

%check
export GOPROXY=off
export GOCACHE="$(pwd)/.gocache"
export GOPATH="$(pwd)/.gopath"
go test ./...

%install
# Note: the Makefile's `install` target depends on the .PHONY `build` target,
# so this recompiles rather than reusing %%build's output. Any flag passed to
# make in %%build must be repeated here or it is silently discarded.
make install DESTDIR=%{buildroot} PREFIX=/usr

install -Dm0644 %{SOURCE1} %{buildroot}%{_unitdir}/beacond.service
install -Dm0644 %{SOURCE2} %{buildroot}%{_sysusersdir}/%{name}.conf
install -Dm0644 %{SOURCE3} %{buildroot}%{_sysconfdir}/sysconfig/%{name}

# State/log directories are package-owned (see %%files) rather than created
# via tmpfiles.d, so ownership and the 0750 mode are guaranteed from install
# through every upgrade without depending on a tmpfiles.d pass ever running.
install -d -m0750 %{buildroot}%{_localstatedir}/lib/beacond
install -d -m0750 %{buildroot}%{_localstatedir}/log/beacond

%pre
# Creates the beacon:beacon system user/group from the sysusers.d fragment
# in Source2 (see beacond.sysusers). %%sysusers_create_compat works whether
# or not systemd-sysusers is present on the target, and must run in %%pre --
# before this package's own files are unpacked -- because the %%attr(...
# beacon,beacon...) entries in %%install/%%files below need that account to
# already exist. Idempotent by construction (sysusers.d directives are),
# and this is never invoked from %%postun, so the account is never removed
# on erase.
%sysusers_create_compat %{SOURCE2}
exit 0

%post
%systemd_post beacond.service

%preun
%systemd_preun beacond.service

%postun
# beacond is stateless (no in-flight work to drain, no local data beyond its
# own log directory), so restarting it on upgrade to pick up the new binary
# is correct here, not just convenient. This never enables/starts the unit
# on initial install -- that is %%systemd_post's job below, and it honours
# distro presets rather than forcing the service on.
%systemd_postun_with_restart beacond.service

%files
%license LICENSE
%doc README.md
%{_bindir}/beacond
%{_unitdir}/beacond.service
%{_sysusersdir}/%{name}.conf
%dir %attr(0750,root,beacon) %{_sysconfdir}/beacond
%config(noreplace) %attr(0640,root,beacon) %{_sysconfdir}/beacond/beacond.yaml
%config(noreplace) %attr(0644,root,root) %{_sysconfdir}/sysconfig/%{name}
%dir %attr(0750,beacon,beacon) %{_localstatedir}/lib/beacond
%dir %attr(0750,beacon,beacon) %{_localstatedir}/log/beacond

%files -n beacond-client
%license LICENSE
%{_bindir}/beacon-status
%{_sysconfdir}/profile.d/beacon-env.sh

%changelog
* Mon Aug 17 2026 Beacond Packaging <packaging@example.com> - 1.4.2-1
- Initial RPM packaging: beacond daemon (systemd unit, sysusers, config)
  plus the noarch beacond-client subpackage.

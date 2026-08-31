# Domain: Supply-Chain & Dependency Security

**Maps to:** OWASP A06:2021 Vulnerable & Outdated Components; CWE-1035/CWE-937 (known-vulnerable
components), CWE-1104 (unmaintained third-party components).

This domain is where Stage 2's SCA research (`sca-inventory.md`) becomes findings — but only with
**reachability**. A CVE in a dependency is a *candidate*; it's a confirmed finding when the
vulnerable code path is reachable in this project and, ideally, exercised in the sandbox.

## What to look for
- **Known-vulnerable versions:** for the exact versions from the lockfiles, CVEs/advisories with a
  fix available. Prioritize by reachability, not raw CVSS.
- **Reachability:** does this project actually call the affected API or hit the affected feature?
  Trace from the CVE's affected function to a call site on a reachable path. Record the call site
  (or the reason it's unreachable) in `sca-inventory.md`.
- **Unmaintained / deprecated packages:** no security updates, archived repos, abandoned forks.
- **Lockfile & integrity issues:** missing lockfile (non-reproducible builds), integrity hashes
  absent, direct-from-VCS or floating-version dependencies.
- **Install-time execution:** packages running scripts on install (a build-time RCE surface).
- **Dependency confusion / typosquatting:** internal package names that could be shadowed by a
  public package of the same name; near-miss names suggesting a typosquat already pulled in.

## Why it's exploitable *here*
Don't report the advisory verbatim — report what it means for this project. "CVE-XXXX in lib@1.2.3,
affecting its `parse()` function, which `ImportController.upload()` calls on user-supplied files
that reach it unauthenticated" is a finding. "lib@1.2.3 has a CVE" is a candidate awaiting
reachability analysis.

## How to test in the sandbox (Stage 4)
For advisories whose path is reachable, attempt to **exercise the reachable CVE path** against the
running target with a benign in-sandbox demonstration of the vulnerable behavior (e.g. trigger the
parser bug and observe the documented failure/behavior). Confirm the project's usage actually
reaches the sink the advisory describes. Where the path is reachable but a full exploit isn't
feasible in-sandbox, mark it reachable-unproven with reasoning rather than over- or under-claiming.

## Root-cause fixes (Stage 6 direction)
- **Upgrade** to the fixed version (preferred); if a major bump is required, note the migration as
  an out-of-scope coordinated follow-up.
- If no fix exists: apply the advisory's mitigation, constrain input before the vulnerable call,
  or replace the dependency.
- Add/repair the **lockfile with integrity hashes**; pin versions; disable unnecessary install
  scripts; claim internal package names / configure the registry to prevent confusion.
- **Verification:** after upgrading, re-run the Stage-4 reachability PoC and confirm the behavior is
  gone; add a test asserting the minimum safe version (a dependency regression guard).

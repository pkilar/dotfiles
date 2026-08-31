<!--
SCHEMA: sca-inventory.md — Software Composition Analysis inventory.
The full dependency list with versions, the CVEs/advisories/deprecations found for those exact
versions, and — crucially — whether the vulnerable code path is actually REACHABLE in this
project. Reachability is what separates a real supply-chain finding from noise.

WRITE-BACK TRIGGER:
- Stage 2: enumerate dependencies + versions from lockfiles; research advisories per version;
  record an initial reachability hypothesis (does this project call the affected API at all?).
- Stage 4: after attempting to exercise the reachable CVE paths in the sandbox, record the
  verdict (exercised/confirmed, reachable-but-not-demonstrated, not-reachable) and link finding IDs.
-->

# SCA Inventory — <project name>

- **Manifest/lockfiles analyzed:** (paths)
- **Advisory sources consulted:** (e.g. OSV, GitHub Advisories, ecosystem DBs — with date)

## Direct dependencies
| Package | Version | Advisory / CVE | Severity | Affected API | Reachable here? | Verdict (S4) | Finding |
|---------|---------|----------------|----------|--------------|-----------------|--------------|---------|
| | | (ID + link) | | (function/feature) | yes/no/unknown + where | exercised / reachable-unproven / not-reachable | F-ID |

## Transitive dependencies of concern
| Package | Version | Pulled in by | Advisory / CVE | Reachable here? | Verdict | Finding |
|---------|---------|--------------|----------------|-----------------|---------|---------|

## Other supply-chain notes
- Deprecated/unmaintained packages; lockfile integrity; install-time script risks; typosquat/
  dependency-confusion exposure (internal names resolvable from public registries?).

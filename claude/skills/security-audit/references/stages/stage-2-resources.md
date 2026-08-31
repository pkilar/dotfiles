# Stage 2 — Dynamic Resource Gathering & Self-Updating References

**Goal:** pull in *only* the reference material this project actually needs, and get current,
project-specific intelligence (CVEs for the exact versions in use, framework-specific hardening).
Then tailor the living documents so the reference set becomes specific to this target. Still
read-only on project code.

## Load selectively, not everything
Open `references/domains/_index.md` and load the domain files that match the applicable-domains
list from `recon.md` — and only those. Loading domains the project doesn't implicate wastes
context and dilutes focus. Each domain file tells you the checks, the standards it maps to
(OWASP Top 10 / ASVS, CWE Top 25, framework guides, CIS benchmarks), and the Stage-4 techniques
that go with it.

## Research project-specific intelligence

### Software Composition Analysis (own file: `sca-inventory.md`)
For the exact dependency versions from Stage 1:
- Look up known CVEs, security advisories, and deprecations (consult current advisory databases;
  if web access is available use it, and date-stamp what you consulted, since advisories change).
- For each hit, decide whether the vulnerable code path is **reachable** in this project — does
  the code actually call the affected API/feature? A critical CVE in an unreached path is lower
  priority than a medium one on a hot path. Record an initial reachability hypothesis; Stage 4
  attempts to actually exercise the reachable ones.
- Note deprecated/unmaintained packages, lockfile integrity, install-time script risks, and
  dependency-confusion/typosquat exposure (are internal package names resolvable from public
  registries?).

### Framework/library hardening & exploit patterns
For the specific frameworks and libraries in use, gather known misuse patterns and hardening
guidance (e.g. this ORM's raw-query escape hatches, this template engine's SSTI surface, this
framework's CSRF defaults, this serializer's unsafe modes). Fold anything project-relevant into
the threat model and the checklist.

### Recent best-practice shifts
Note any recent shifts relevant to the stack (deprecated primitives, changed secure defaults, new
advisory classes) so the audit reflects current practice, not stale habits.

## The self-updating reference mechanism (do this every stage; here is where it starts in earnest)
The skill's intelligence compounds because the living documents in the workspace are rewritten as
you learn. Concretely, at the end of THIS stage you write back into:
- `tailored-checklist.md` — instantiate concrete, project-specific items from each loaded domain
  (name the actual routes/functions to check; drop inapplicable standard items).
- `sca-inventory.md` — the dependency + advisory + reachability table.
- `threat-model.md` — refine with framework-specific threats and supply-chain threats for
  reachable CVEs; add abuse cases the domain reading surfaced.
- `coverage-matrix.md` — annotate each surface with the domain(s) and checklist items that map to it.
- `AUDIT-LOG.md` — what you loaded, the notable CVEs/advisories, and what Stage 3 should focus on.

The write-back trigger is simply: **a stage does not end until the files it owns reflect what the
stage learned.** That discipline is what lets a later stage — or a resumed session — build on
accumulated context instead of re-deriving it.

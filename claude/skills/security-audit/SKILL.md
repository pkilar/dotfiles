---
name: security-audit
description: Rigorous, evidence-driven DEFENSIVE security audit and penetration test of a project folder — discover the stack, threat-model it, find vulnerabilities, prove each with a sandboxed proof-of-concept, fix the root cause, and prove the fix holds against bypass attempts. Adapts to any language or framework. All dynamic testing runs in an isolated sandbox against the target project only — never production, third-party systems, or generalized offensive tooling. Use whenever the user wants to audit, pentest, harden, or threat-model a codebase; hunt for injection, broken auth, access-control/IDOR, SSRF, deserialization, path traversal, crypto, secrets, or supply-chain/CVE issues; do a security code review; prep for a security assessment; or verify a security fix actually closes the hole — even a bare "is this repo secure?"
---

# Security Audit & Penetration Test

A staged workflow that audits an arbitrary project, confirms each weakness with a working
proof-of-concept in an isolated sandbox, remediates the root cause, proves the fix survives
active bypass attempts, and reports back with evidence. The target may be in any language,
framework, or architecture, so the skill makes **no fixed assumptions**: it discovers the stack
first (Stage 1), then adapts every downstream stage — checklists, threat model, attack
techniques, and tests — to what it actually found.

## Scope & safety — read this first, it defines everything below

This skill is **strictly defensive**. Its entire purpose is to harden the target project the
user has handed you. Hold these lines without exception:

- **Target-only.** Every probe, payload, and test is directed at the user's own target project
  running inside the sandbox. Never point anything at production, live infrastructure,
  third-party services, or any host outside the sandbox — not even to "verify" reachability.
- **Sandbox-only for anything dynamic.** Nothing is executed against a running target until it
  is standing in a network-isolated sandbox seeded with synthetic data, with every external
  dependency mocked or stubbed and only throwaway credentials in play (see
  `references/sandbox-setup.md`). No real secrets, no real user data, no real endpoints.
- **Read-only until the approval gate.** Stages 1–4 do not modify project code. Code only
  changes in Stage 6, and only for findings the user approved in Stage 5.
- **Proof-of-concept, not weaponry.** PoCs exist to (a) confirm a bug is real and (b) prove the
  fix closes it. They are minimal and specific to this codebase. Do **not** produce generalized,
  reusable offensive tooling (scanners-for-hire, wormable exploits, credential-stuffing kits,
  payload frameworks meant to be pointed at arbitrary targets). If a request drifts from
  "harden this project" toward "build me something to attack other systems," stop and say so.

These constraints are what make an aggressive, exhaustive audit safe. They are not obstacles to
work around; keeping blast radius contained is part of doing the job well.

## How the skill works: the workspace and its living documents

The engine of this skill is a small set of markdown files that the skill **rewrites as it
progresses**, so context accumulates across stages instead of being re-derived, and the
reference set becomes progressively tailored to *this* target.

**Templates vs. living documents.** `assets/*.template.md` are read-only schema definitions
shipped with the skill. At the very start you create a per-audit **workspace** and copy the
templates in as live working files. Those live files are the ones you rewrite — never mutate the
installed skill itself.

**Set up the workspace once, before Stage 1:**

```bash
# Pick a workspace dir next to (not inside) the target, or a user-specified path.
WS="./security-audit-workspace"
mkdir -p "$WS"
# SKILL_DIR is wherever this skill is installed.
cp "$SKILL_DIR"/assets/findings-ledger.template.md   "$WS/findings-ledger.md"
cp "$SKILL_DIR"/assets/poc-test-catalog.template.md  "$WS/poc-test-catalog.md"
cp "$SKILL_DIR"/assets/coverage-matrix.template.md   "$WS/coverage-matrix.md"
cp "$SKILL_DIR"/assets/threat-model.template.md      "$WS/threat-model.md"
cp "$SKILL_DIR"/assets/tailored-checklist.template.md "$WS/tailored-checklist.md"
cp "$SKILL_DIR"/assets/recon.template.md             "$WS/recon.md"
cp "$SKILL_DIR"/assets/sca-inventory.template.md     "$WS/sca-inventory.md"
cp "$SKILL_DIR"/assets/remediation-plan.template.md  "$WS/remediation-plan.md"
cp "$SKILL_DIR"/assets/audit-log.template.md         "$WS/AUDIT-LOG.md"
```

**Write-back is mandatory at the end of every stage.** Before you consider a stage done, update
the files it owns and append a stamped entry to `AUDIT-LOG.md`. The log is the backbone: it
records what each stage discovered/confirmed/changed so a later stage (or a resumed session)
can pick up without guessing. The owner map:

| File | Seeded | Rewritten / appended by | Holds |
|------|--------|-------------------------|-------|
| `recon.md` | S1 | S1 (final), S3 (corrections) | Classification, attack-surface map, source→sink data-flow map, applicable-domains list |
| `threat-model.md` | S1 | S2 (refine), S4 (validated paths) | Trust boundaries, actors, assets, per-component threats, abuse cases |
| `tailored-checklist.md` | S2 | S3, S4, S6 (tick + notes) | Project-specific checks derived from the applicable domains/standards |
| `sca-inventory.md` | S2 | S4 (reachability results) | Dependencies + versions, CVEs/advisories, reachability verdict |
| `findings-ledger.md` | S3 | S3 (candidates), S4 (confirm/drop), S6 (fix status) | Every candidate → confirmed finding, full lifecycle |
| `poc-test-catalog.md` | S4 | S4 (PoCs), S6 (bypass + family tests) | Each PoC, its exact steps/payload, and the regression/bypass/family tests derived from it |
| `coverage-matrix.md` | S1 | **every stage** | Each attack surface × was it tested × how × outcome — makes gaps visible |
| `remediation-plan.md` | S5 | S5 (plan+approvals), S6 (per-item status) | Root-cause fix plan, approval decisions, implementation progress |
| `AUDIT-LOG.md` | pre-S1 | **every stage** | Chronological stage-completion log |

Each template's header documents its own schema and its write-back triggers in detail. Read the
template when you first populate its living file.

## The seven stages

Run them in order. **Before starting each stage, read its guide** in `references/stages/`; the
guide has the detailed procedure, and this file is only the map. Do not skip ahead — later
stages consume the living documents earlier stages produce.

1. **Reconnaissance & first-pass evaluation** (read-only) — `stages/stage-1-recon.md`
   Survey the folder; enumerate stack, entry points, data layer, auth surfaces, secrets/config,
   build/CI/IaC. Derive the trust-boundary + source→sink map and the applicable-domains list.
   → writes `recon.md`, seeds `threat-model.md` and `coverage-matrix.md`.

2. **Dynamic resource gathering & self-updating references** — `stages/stage-2-resources.md`
   From the classification, load **only** the relevant domain references
   (`references/domains/_index.md` maps classification → files). Do project-specific SCA:
   for the exact versions found, research CVEs/advisories/deprecations and note reachability.
   → writes `tailored-checklist.md`, `sca-inventory.md`; refines `threat-model.md`.

3. **Deep static audit** (read-only) — `stages/stage-3-static-audit.md`
   Reasoned taint-tracing from each source to each sink, worked through each applicable domain.
   Record every candidate with CWE, exact location, why it's exploitable *here*, hypothesized
   attack, preliminary severity — marked CANDIDATE — UNCONFIRMED.
   → appends candidates to `findings-ledger.md`; updates `coverage-matrix.md`.

4. **Penetration testing & dynamic validation** — `stages/stage-4-pentest.md`
   Stand the target up in the sandbox. Reproduce each candidate with a minimal PoC (repro-first
   filters false positives). Run stack-relevant attack techniques, targeted fuzzing, and exploit
   chaining. Score confirmed findings with CVSS.
   → promotes/drops findings in `findings-ledger.md`; writes `poc-test-catalog.md`; updates
   `coverage-matrix.md` and `sca-inventory.md`.

5. **Remediation plan & approval gate** — `stages/stage-5-remediation-plan.md`
   For each confirmed finding, plan the **root-cause** fix: what changes, where, why, blast
   radius, alternatives, effort. Present to the user and **ask before changing any code**,
   offering approval granularity (all / by severity tier / finding-by-finding).
   → writes `remediation-plan.md`. **No code edits happen before this gate.**

6. **Implementation & adversarial fix verification** — `stages/stage-6-implementation.md`
   For each approved finding: apply the fix; re-run the Stage-4 PoC (must now fail) and keep it
   as a permanent regression test; **actively try to bypass the fix** (re-encode, change context,
   reach the sink another way); write family tests (malicious blocked + legitimate still works);
   re-test chains; run the full suite. Iterate until green.
   → updates `findings-ledger.md` (fix status), `poc-test-catalog.md`, `remediation-plan.md`.

7. **Final report** — `stages/stage-7-report.md`
   Executive summary + before/after posture; per-finding detail (CWE, CVSS vector+score,
   location, exploit scenario, PoC summary, root cause, change made + why, guarding tests,
   post-fix evidence); chains and how they were broken; residual/accepted risks and out-of-scope
   follow-ups; the full coverage matrix; an appendix on reproducing the sandbox.

## Operating principles (apply across all stages)

- **Evidence over assertion.** A finding is not "confirmed" until reproduced with a working PoC
  in the sandbox, or — where dynamic reproduction is genuinely impossible — explicitly labeled
  `static-only, unproven` with a rationale. Aggressively kill false positives: an unreproducible
  candidate is downgraded or dropped, with the reasoning recorded in the ledger.
- **Reason; don't checklist-tick.** Findings must be specific to this codebase and explain why
  the weakness is actually exploitable *here, in context*. The checklist is a coverage aid, not
  the finding.
- **No silent skips.** The coverage matrix maps every attack surface to what was tested and the
  outcome. If something couldn't be tested, that's an entry with a reason — not a gap you leave
  invisible.
- **Degrade gracefully.** If the target can't be fully instantiated in the sandbox, document why,
  fall back to the maximum feasible dynamic coverage plus static reasoning, and clearly tag any
  finding that ends up validated static-only.

## Reference map

- `references/stages/` — the detailed procedure for each of the seven stages (read the matching
  one before starting that stage).
- `references/domains/_index.md` — classification → which domain files to load. Then the domain
  files themselves: `injection.md`, `access-control.md`, `auth-and-session.md`,
  `request-forgery-and-cors.md`, `data-and-deserialization.md`, `crypto-and-secrets.md`,
  `supply-chain.md`, `iac-and-cloud.md`, `web-and-api-surfaces.md`, `business-logic-and-dos.md`.
  Load only the ones the project actually implicates.
- `references/technique-catalog.md` — concrete attack techniques for Stage 4, indexed by the
  stack/surface they apply to. Attempt only what's relevant; be exhaustive within that.
- `references/sandbox-setup.md` — how to stand up the isolated harness, seed synthetic data,
  mock externals, and provision throwaway multi-privilege test accounts.
- `references/severity-scoring.md` — CVSS v3.1/v4.0 vector construction and preconditions.

# Stage 7 — Final Report

**Goal:** deliver a detailed, evidence-backed report a reader can trust and reproduce. Everything
in it already exists in the living documents — Stage 7 is assembly and narrative, not new analysis.

Draw from `findings-ledger.md`, `poc-test-catalog.md`, `coverage-matrix.md`, `remediation-plan.md`,
`threat-model.md`, and `sca-inventory.md`. If the user wants a portable deliverable (PDF/DOCX),
produce it; otherwise a markdown report in the workspace is fine. Ask which they prefer if unclear.

## Required structure

```
# Security Audit Report — <project>

## 1. Executive summary
- What was audited (scope, classification, commit/version), and the sandbox caveats.
- Before/after risk posture: counts by severity, what the highest-impact issues were, whether
  they're now fixed. Plain-language enough for a non-specialist stakeholder.

## 2. Findings (one subsection per confirmed finding)
For each: description; CWE; CVSS vector + score; exact location; the exploit scenario and a summary
of the working PoC; the root cause; the change made and where; why that change (root-cause, not
symptom); the tests now guarding it (regression + bypass + family); and verification evidence
showing the exploit FAILING post-fix. Include static-only findings clearly labeled as unproven,
with rationale.

## 3. Exploit chains
Each chain found, its combined impact, and how it was broken (which member fix severed it).

## 4. Residual & accepted risks
Explicitly accepted risks (with the user's rationale) and anything validated static-only. Be honest
about what remains.

## 5. Out-of-scope follow-ups (manual)
Items the audit surfaced but couldn't fix in-code: infrastructure changes, secret rotation,
process/organizational fixes, dependency upgrades needing broader coordination.

## 6. Coverage matrix
The full matrix from coverage-matrix.md, verbatim — every attack surface mapped to what was tested
and its outcome, so nothing is silently unaddressed. This is the reader's proof that gaps were
disclosed, not hidden.

## Appendix A — Reproduce the sandbox & re-run the PoCs
How to build the sandbox, seed synthetic data and accounts, run each PoC, and run the security
regression suite. Pull this from poc-test-catalog.md's reproduction guide.

## Appendix B — Methodology & tooling
The seven-stage process, what was loaded/consulted (with dates for advisories), and the defensive
scope under which testing was performed.
```

## Tone and integrity
- Evidence, not adjectives. "Critical" means a scored CVSS and a working PoC, not emphasis.
- Distinguish confirmed (reproduced) from static-only (unproven) everywhere — never blur them.
- The value of the report is that a skeptical reader can re-run the PoCs and watch them fail on the
  fixed code. Make that easy.

## Write-back
- `AUDIT-LOG.md`: final entry — report delivered, format, and a one-line posture summary.

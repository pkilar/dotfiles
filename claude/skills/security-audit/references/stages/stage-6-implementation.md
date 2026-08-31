# Stage 6 — Implementation & Adversarial Fix Verification

**Goal:** apply each approved fix and then *prove it holds* — not by one passing unit test, but by
surviving active attempts to defeat it. Only touch findings the user approved in Stage 5.

The governing idea: **a fix is a hypothesis until you've tried and failed to break it.** Attackers
don't stop at the first blocked payload, so neither do you. Work each finding through the
sub-phases; iterate until everything is green.

## 6a. Regression proof (before / after)
Apply the root-cause fix, then re-run the *exact* Stage-4 PoC against the patched code. It must now
**fail**. Preserve that PoC as a permanent **security regression test** — one that fails against the
vulnerable version and passes only against the fixed version. That asymmetry is what makes it a
real guard rather than a tautology. Record the test path in `poc-test-catalog.md`.

## 6b. Bypass / evasion testing (mandatory)
Actively try to defeat the fix. This is the step most often skipped and most often where an
"applied" fix turns out to be incomplete. Attempt, as applicable:
- **Mutate and re-encode** the payload (alternate encodings, double-encoding, case/Unicode
  variants, whitespace/comment tricks).
- **Switch context** — a different injection/encoding context the fix may not cover.
- **Reach the same sink another way** — a different route, parameter, interface, or content type
  that hits the same dangerous operation the fix guarded at only one entrance.
- **Canonicalization / normalization edge cases** — path normalization, URL parsing quirks,
  homoglyphs, trailing-dot/case-folding, parser differentials.
- **Inputs the fix may not have considered** — boundary values, nested structures, null bytes.

A fix is accepted only when these bypass attempts **also fail**. If any bypass succeeds, the fix is
incomplete — iterate on it (usually meaning: move the fix to a more fundamental layer). Record the
full bypass battery and its results in `poc-test-catalog.md`.

## 6c. Dedicated security tests (the whole family, not one payload)
Write unit/integration tests covering the entire vulnerability **family**:
- **Negative cases** — a spread of malicious variants across the class are blocked.
- **Positive cases** — representative legitimate inputs still work, so the fix introduces **no
  functional regression**. A fix that also breaks valid behavior isn't done.

## 6d. Chain re-test
Re-run any exploit chains (C-IDs) end-to-end to confirm they're now broken. Note which member fix
severed each chain in the ledger.

## 6e. Full regression
Run the project's existing test suite to catch functional breakage, and confirm coverage over the
security-relevant paths you touched. If the fix changed behavior that legitimately needed changing,
update the affected tests deliberately and note it.

## 6f. Iterate — the exit condition
For any finding whose PoC still succeeds, whose fix is bypassable, or whose tests are red, keep
remediating. **Do not return to the user (Stage 7) until every confirmed, approved finding is
mitigated with green regression + bypass + family tests**, chains are broken, and the existing
suite passes (or deltas are understood and justified).

## Write-back throughout Stage 6
- `findings-ledger.md`: move each item FIX APPLIED — VERIFYING → FIXED — VERIFIED; fill section 10
  (root cause, change + where, regression proof, bypass results, family tests, approval ref).
- `poc-test-catalog.md`: derived tests (regression + bypass battery + family) with codebase paths.
- `remediation-plan.md`: per-item implementation status → verified.
- `coverage-matrix.md`: re-verified column for touched surfaces.
- `AUDIT-LOG.md`: per-finding fix + verification summary; any fix that needed iteration and why.

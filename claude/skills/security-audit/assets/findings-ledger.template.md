<!--
SCHEMA: findings-ledger.md — the running ledger of every weakness, from candidate to fixed.
This is the spine of the audit. A finding has a lifecycle and the ledger records the WHOLE arc,
including the ones you dropped (dropping a false positive with a reason is itself valuable output).

STATUS values:
  CANDIDATE — UNCONFIRMED  (Stage 3: found statically, not yet validated)
  CONFIRMED                (Stage 4: reproduced with a working PoC in the sandbox)
  STATIC-ONLY, UNPROVEN    (Stage 4: dynamic repro genuinely impossible — rationale required)
  DROPPED — FALSE POSITIVE (Stage 4: not reproducible / not actually exploitable — rationale required)
  FIX APPLIED — VERIFYING  (Stage 6: fix in place, verification in progress)
  FIXED — VERIFIED         (Stage 6: PoC now fails + bypass attempts fail + family tests green)
  ACCEPTED RISK            (Stage 5/6: user chose not to fix — record who/why)

ID scheme: F-001, F-002, ... Chains get C-001, C-002 (see the Chains section) and reference the
member finding IDs.

WRITE-BACK TRIGGER:
- Stage 3: append each candidate with sections 1–6 filled, status CANDIDATE — UNCONFIRMED.
- Stage 4: update status; fill sections 7–9 (evidence, CVSS, catalog link) or the drop rationale.
- Stage 6: fill section 10 (fix + verification) and move status toward FIXED — VERIFIED.

Keep one block per finding, in the format below.
-->

# Findings Ledger — <project name>

## Summary table (regenerate whenever status changes)
| ID | Title | CWE | Status | Severity (CVSS) | Chain | Fix status |
|----|-------|-----|--------|-----------------|-------|------------|
| F-001 | | | | | | |

---

## F-001 — <short title>
**Status:** CANDIDATE — UNCONFIRMED
**Vulnerability class / CWE:** <class> (CWE-XXX)
**Applicable domain:** <domain file>

1. **Location:** `path/to/file:line` (and any secondary locations)
2. **Untrusted source → sink:** <which source, which sink, via what path> (ref recon.md flow #)
3. **Why exploitable *here*:** the specific reason this is reachable and unguarded in THIS code
   and context — not a generic description of the bug class.
4. **Hypothesized attack scenario:** who does what, with what precondition (auth level, config).
5. **Preliminary severity (pre-validation):** <low/med/high/critical> + one-line reasoning.
6. **Coverage-matrix ref:** <which surface/row this maps to>

<!-- Filled in Stage 4 -->
7. **Validation result & evidence:**
   - Outcome: CONFIRMED / STATIC-ONLY / DROPPED (+ rationale if not confirmed).
   - Exact PoC steps / request / payload: (or link to poc-test-catalog.md entry PoC-ID)
   - Observed result: response, side effect, state change proving impact.
8. **CVSS:** vector string + score + rationale; exploitability preconditions (auth, config).
9. **PoC/Test catalog ref:** PoC-ID in poc-test-catalog.md.

<!-- Filled in Stage 6 -->
10. **Remediation & verification:**
    - Root cause: <the underlying defect, not the symptom>.
    - Change made + where: `path/to/file` — <what changed and why this closes the root cause>.
    - Regression proof: original PoC now FAILS (evidence/link).
    - Bypass attempts tried and their results (must all fail): <re-encoding, alt route, canon edge cases…>.
    - Family tests: negative (malicious variants blocked) + positive (legit input still works).
    - Approval ref: remediation-plan.md item; approved by <user> on <when>.

---

## Chains
### C-001 — <chain title>
- **Members:** F-00X → F-00Y → F-00Z
- **Combined impact:** <what the chain achieves that the parts don't>
- **Chain PoC:** poc-test-catalog.md PoC-ID
- **CVSS (chain):** vector + score
- **Broken by:** which member fix severs it (verified in Stage 6d).

<!--
SCHEMA: remediation-plan.md — the Stage 5 plan and the record of the approval gate.
For each confirmed finding it specifies the ROOT-CAUSE fix (not a symptom patch) and captures the
user's approval decision. Stage 6 annotates each item with implementation status. NO CODE CHANGES
happen before the user approves the corresponding item here.

WRITE-BACK TRIGGER:
- Stage 5: one plan item per confirmed finding, ordered by severity → exploitability → chain
  membership. Record the approval decision once the user responds.
- Stage 6: update each item's implementation status as fixes land and pass verification.

APPROVAL states: PENDING · APPROVED · DEFERRED · REJECTED (accepted risk → note in ledger)
IMPLEMENTATION states: not started · in progress · fix landed · verified · needs iteration
-->

# Remediation Plan — <project name>

## Approval summary
- **Granularity offered:** all-at-once / by-severity-tier / finding-by-finding
- **User decision (verbatim):** <what they approved, when>

## Plan items (ordered)
### R-001 → fixes F-001 <title>  ·  Severity <…>  ·  Chain <C-ID or none>
- **Root cause:** the underlying defect to eliminate.
- **Fix approach:** what will change and why this addresses the root cause (parameterize the query
  / enforce authz at the boundary / replace the primitive / etc.), not just "sanitize input".
- **Where:** exact files/functions to touch.
- **Blast radius / risk of the change:** what else this could affect; migration or compat concerns.
- **Alternatives & tradeoffs:** other viable fixes and why this one.
- **Effort:** rough estimate.
- **Approval:** PENDING
- **Implementation status:** not started

<!-- Repeat per confirmed finding. Group by severity tier so the user can approve tier-by-tier. -->

## Notes
- Items deferred or rejected (accepted risks) — carry the rationale into the final report's
  residual-risk section and the ledger's ACCEPTED RISK status.

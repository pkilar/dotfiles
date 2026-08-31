# Stage 5 — Remediation Plan & Approval Gate

**Goal:** produce a root-cause remediation plan and get explicit user approval **before any code
changes.** This is a hard gate: Stages 1–4 touched no project code, and Stage 6 only proceeds on
approved items.

Output goes in `remediation-plan.md`. This is the one stage that is primarily a conversation with
the user.

## Plan each fix at the root cause, not the symptom
For each confirmed finding, specify:
- **Root cause** — the underlying defect. "Escape this one string" is a symptom patch; "this query
  is built by concatenation and must be parameterized (and the same pattern exists in N other
  queries)" is the root cause.
- **Fix approach** — what changes and why it closes the root cause. Prefer structural fixes
  (parameterized queries, centralized authz checks, safe deserialization modes, well-reviewed
  library primitives) over ad-hoc filtering that attackers route around.
- **Where** — exact files/functions.
- **Blast radius / risk of the change** — what else it could affect, compatibility/migration
  concerns, behavior changes callers might notice.
- **Alternatives & tradeoffs** — other viable fixes and why this one.
- **Effort** — rough estimate.

## Order the plan
Sort by severity → exploitability (preconditions, auth required) → chain membership (fixing a chain
member that severs a high-impact chain can outrank a nominally higher CVSS in isolation). Group by
severity tier so the user can approve tier-by-tier.

## Present and ask — offer approval granularity
Present the plan and **explicitly ask whether to proceed.** Accepting one large diff is often
undesirable on a bigger codebase, so offer a choice:
- **Approve everything**, or
- **Approve by severity tier** (e.g. criticals+highs now, mediums later), or
- **Approve finding-by-finding.**

Make **no** code changes until the user approves, and only proceed on the approved items. If the
user chooses to accept a risk rather than fix it, record that decision (who, when, why) — it
becomes an `ACCEPTED RISK` in the ledger and a residual-risk entry in the final report.

## Write-back before leaving Stage 5
- `remediation-plan.md`: all plan items (ordered, grouped by tier) + the verbatim approval decision.
- `findings-ledger.md`: mark any accepted-risk items.
- `AUDIT-LOG.md`: what was presented and exactly what the user approved / deferred / rejected.

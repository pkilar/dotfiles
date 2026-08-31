<!--
SCHEMA: AUDIT-LOG.md
Purpose: The chronological backbone of the audit. One appended entry per stage (and per
significant sub-step). It lets a later stage — or a resumed session after a context reset —
reconstruct what has already happened without re-deriving it.

WRITE-BACK TRIGGER: Append an entry at the end of EVERY stage, and whenever you finish a
meaningful sub-step (e.g. "sandbox stood up", "SCA complete"). Never rewrite past entries;
only append. If you correct an earlier conclusion, add a new entry that says so.

ENTRY FORMAT:
### [UTC timestamp] — Stage N: <short title>
- **Did:** what you actually ran/read/wrote this step.
- **Found/changed:** key outcomes (counts, notable items) — keep it to signal.
- **Files updated:** which living documents you rewrote.
- **Next:** what the following stage should pick up, plus any open blockers.
-->

# Audit Log — <project name>

- **Target path:** <path>
- **Workspace:** <path>
- **Started (UTC):** <timestamp>
- **Operator note:** Defensive audit. All dynamic testing is sandbox-only, against this target
  only. Read-only until the Stage 5 approval gate.

---

### <timestamp> — Stage 0: Workspace initialized
- **Did:** Created workspace, copied templates to living documents.
- **Files updated:** all living docs seeded from templates.
- **Next:** Stage 1 reconnaissance.

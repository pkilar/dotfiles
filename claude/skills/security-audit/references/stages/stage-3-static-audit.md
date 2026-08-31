# Stage 3 — Deep Static Audit (read-only)

**Goal:** a reasoned, context-aware static analysis that produces *candidate* findings specific to
this codebase — not a scanner-style pattern dump. Still no code changes.

Every candidate is appended to `findings-ledger.md` with status **CANDIDATE — UNCONFIRMED**. It
only graduates to a confirmed finding after Stage 4 reproduces it (or is explicitly labeled
static-only there). Update `coverage-matrix.md` and `tailored-checklist.md` as you go.

## Two passes, run together

### Pass A — taint tracing (source → sink)
Walk the source→sink map from `recon.md`. For each untrusted source, follow the data to each
sensitive sink it can reach and ask: is there adequate **validation, encoding, parameterization,
or authorization** on the path? Flag every flow that lacks it. Trace through function boundaries,
not just single files — the source and sink are often far apart, and the missing guard is often
an assumption ("the caller already validated this") that nothing enforces.

### Pass B — per-domain depth
Work through each applicable domain file (`references/domains/*`), scoped to what the project
actually exposes. The domain files carry the specifics; use them as the depth reference, and let
the `tailored-checklist.md` track that you covered each item. Reason about *this* code — why a
given weakness is or isn't exploitable given the surrounding validation, framework behavior, and
configuration you found in Stages 1–2.

## Record every candidate with enough to validate it later
For each candidate, capture in the ledger:
- **Vulnerability class + CWE.**
- **Exact location** (`file:line`/region; list secondary locations).
- **Why it's exploitable *here*** — the concrete, in-context reason, referencing the specific
  source, the missing guard, and the reachable sink. "User input reaches a SQL string" is a start;
  "the `sort` query param is concatenated into the ORDER BY clause in `list_orders()` with no
  allow-list, and the endpoint is reachable by any authenticated user" is a candidate.
- **Hypothesized attack scenario** — actor, precondition (auth level, config), and the payload
  shape you'll try in Stage 4.
- **Preliminary severity** — a first cut; Stage 4 assigns the real CVSS.
- **Coverage-matrix ref** — which surface row this maps to.

## Keep signal high
If, while reading, you conclude a suspicious-looking pattern is actually safe here (framework
auto-escapes it, the input is constrained upstream, the sink isn't what it appears), say so
briefly in the log rather than logging a candidate you already know is a false positive. The
ledger is for things genuinely worth validating.

## Write-back before leaving Stage 3
- `findings-ledger.md`: all candidates appended (sections 1–6), summary table regenerated.
- `coverage-matrix.md`: static column filled for each surface examined.
- `tailored-checklist.md`: items marked static-checked; finding IDs linked.
- `recon.md`: correct any source/sink/surface the deeper read revealed the survey had missed.
- `AUDIT-LOG.md`: candidate count, hottest flows, and what Stage 4 should prioritize reproducing.

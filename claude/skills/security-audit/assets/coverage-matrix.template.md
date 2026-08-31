<!--
SCHEMA: coverage-matrix.md — the anti-blind-spot ledger.
Every attack surface from recon, mapped to whether/how it was tested and the outcome. Its whole
job is to make GAPS VISIBLE: an untested surface should appear here as an explicit row with a
reason, never as a silent omission. This table is reproduced verbatim in the final report.

WRITE-BACK TRIGGER: update at the END OF EVERY STAGE.
- Stage 1: create one row per attack surface / entry point discovered.
- Stage 2: annotate which domain(s) and checklist items map to each surface.
- Stage 3: fill the "static" column (examined? candidate raised?).
- Stage 4: fill the "dynamic" column (tested how? outcome? finding ID?).
- Stage 6: fill the "re-verified" column after fixes.

STATUS legend for the outcome columns:
  ✅ tested, clean · ⚠️ finding (→ F-ID) · ⏭️ not applicable (reason) ·
  🚫 blocked (reason) · 🕓 static-only (reason)
-->

# Coverage Matrix — <project name>

| # | Attack surface / entry point | Applicable domain(s) | Static (S3) | Dynamic (S4) | Finding(s) | Re-verified (S6) | Notes / why-if-skipped |
|---|------------------------------|----------------------|-------------|--------------|------------|------------------|------------------------|
| 1 | <route/CLI/job/consumer + location> | | | | | | |

<!-- Add a row for EVERY surface. If a surface is untested, the row still exists and the Notes
     column explains why (out of scope, could not instantiate, no realistic vector, etc.). The
     absence of a row is a bug in the audit, not an acceptable outcome. -->

## Domain coverage roll-up
| Domain | In scope? | Depth reached | Gaps / caveats |
|--------|-----------|---------------|----------------|
| injection | | static+dynamic / static-only / n/a | |
| access-control | | | |
| auth-and-session | | | |
| request-forgery-and-cors | | | |
| data-and-deserialization | | | |
| crypto-and-secrets | | | |
| supply-chain | | | |
| iac-and-cloud | | | |
| web-and-api-surfaces | | | |
| business-logic-and-dos | | | |

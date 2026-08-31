<!--
SCHEMA: tailored-checklist.md — the project-specific checklist.
Built in Stage 2 by pulling the relevant items from the applicable domain references and standards
(OWASP Top 10 / ASVS, CWE Top 25, framework guides, CIS benchmarks) and dropping everything that
doesn't apply to this target. It is a COVERAGE AID, not a place to record findings — findings live
in findings-ledger.md. Each item just tracks "did we look, and what happened".

WRITE-BACK TRIGGER:
- Stage 2: populate items from the loaded domains; each starts as [ ] not-yet-checked.
- Stage 3: mark items examined statically; link any candidate finding IDs raised.
- Stage 4: mark items dynamically tested; link confirmed finding IDs.
- Stage 6: mark items re-verified after fixes.

ITEM STATES: [ ] not checked · [~] static-only · [x] dynamically tested · [!] finding raised (see F-IDs)
-->

# Tailored Security Checklist — <project name>

> Only items relevant to this target's applicable domains are listed. Standard references:
> OWASP Top 10 / ASVS, CWE Top 25, plus framework- and stack-specific guides. Source domain
> noted per item so you can re-open the domain file for depth.

## <Domain, e.g. Injection>
- [ ] (item) — *source domain: injection.md* — check: <what to verify in this codebase> — findings: <F-IDs>
- [ ] ...

## <Domain, e.g. Access control>
- [ ] ...

<!-- Repeat one section per applicable domain. Keep items concrete and tied to this project's
     actual surfaces (name the route/function), not generic restatements of the standard. -->

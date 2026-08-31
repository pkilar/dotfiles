<!--
SCHEMA: poc-test-catalog.md — the catalog of proof-of-concept exploits and the security tests
derived from them. This is what makes the audit reproducible and what turns each PoC into a
permanent guard so the vulnerability can't silently come back.

Every PoC here targets the sandboxed instance of THIS project only. No PoC in this file should be
usable as a generic, retargetable exploit tool.

WRITE-BACK TRIGGER:
- Stage 4: add a PoC entry for each finding you attempt (confirmed or not — a failed repro that
  filtered a false positive is worth recording). Include exact, minimal steps.
- Stage 6: add the derived tests — the regression test (fails on vuln, passes on fix), the bypass
  battery, and the family tests — and link them to the codebase test paths.

ID scheme: PoC-001, PoC-002, ... paired to finding IDs.
-->

# PoC & Test Catalog — <project name>

## PoC-001 — for F-001 <title>
- **Sandbox preconditions:** which service(s) up, seeded data, which throwaway account/privilege.
- **Setup commands:** (exact, reproducible)
- **Exploit steps / request / payload:** the minimal sequence that demonstrates it.
  ```
  <exact request or command>
  ```
- **Expected vulnerable result:** what proves the exploit (status, body, side effect, timing).
- **Actual result (baseline / vulnerable version):** captured output.
- **Repro outcome:** CONFIRMED / NOT REPRODUCIBLE / ENVIRONMENT-BLOCKED (+ note).

### Derived security tests (added Stage 6)
- **Regression test:** `path/to/test` — asserts the exploit FAILS on fixed code; would FAIL on the
  vulnerable version (that asymmetry is the point).
- **Bypass battery:** variants attempted against the fix and their results — re-encoded payloads,
  alternate injection/encoding context, same sink via a different route/interface, canonicalization/
  normalization edge cases, inputs the fix might not cover. All must fail for the fix to pass.
- **Family tests:** negative cases (a spread of malicious variants across the whole vuln class are
  blocked) AND positive cases (representative legitimate inputs still succeed — no functional
  regression).

---

## Sandbox reproduction guide (fill once the harness exists; mirror into the final report appendix)
- **How to build the sandbox:** (compose file / scripts, see references/sandbox-setup.md)
- **How to seed synthetic data & accounts:**
- **How to run all PoCs:**
- **How to run the security regression suite:**

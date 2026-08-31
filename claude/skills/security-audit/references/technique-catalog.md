# Attack-Technique Catalog (Stage 4)

Concrete techniques for **validating candidate findings against the sandboxed target**, indexed by
the surface they apply to. Attempt only techniques relevant to the discovered stack; within that,
be exhaustive. Every technique here is for proving a bug in *your own* target and then proving the
fix — keep PoCs **minimal, benign, and in-sandbox** (a marker file in a temp dir, a controlled
delay, a returned row that shouldn't be returned — never destructive or data-exfiltrating actions,
never aimed outside the sandbox).

## Table of contents
1. General PoC discipline
2. Injection
3. Access control & IDOR
4. Auth & session
5. SSRF / CSRF / CORS / redirect
6. Deserialization / XXE / path / upload / mass assignment
7. Crypto & secrets
8. Web/API surfaces
9. Business logic, races, DoS
10. Fuzzing
11. Exploit chaining

## 1. General PoC discipline
- **Reproduce minimally first** (Stage 4b) before elaborating. The smallest input that demonstrates
  impact is the best evidence and the clearest regression test later.
- Capture **input + response + side effect/state change** for every attempt. Impact evidence
  (unauthorized row, changed state, executed side effect) beats signal evidence (an error message).
- Record every attempt — including failures — in `poc-test-catalog.md`; failed repros are how you
  justify dropping false positives.

## 2. Injection
- **SQL:** boolean-based (`' OR '1'='1`-style semantics against seeded data), error-based, and
  time-based (observe induced delay) probes; confirm a *semantic* change, not just an error. For
  `ORDER BY`/identifier positions, test allow-list bypass.
- **NoSQL:** operator injection (`$gt`, `$ne`, `$where`, `$regex`) via JSON bodies; authentication
  bypass by turning a scalar match into an always-true operator.
- **OS command:** prove execution with a benign observable (write a temp marker, echo into a
  captured stream, controlled sleep); separators and substitution (`;`, `|`, `$(...)`, backticks).
- **SSTI:** submit an expression that renders its evaluated result (arithmetic) to prove evaluation.
- **CRLF/header:** inject `%0d%0a` to split headers/redirects; observe an injected header/line.

## 3. Access control & IDOR
- Stand up **multiple principals** (anonymous, user A, user B, admin). Then:
  - **Horizontal:** swap object IDs between A and B; success proves IDOR.
  - **Vertical:** call privileged endpoints with a low-priv token; tamper role-bearing values.
  - **Forced browsing:** request known/guessable privileged routes unauthenticated or low-priv.
  - **Interface parity:** repeat each check via REST, GraphQL, websocket, and bulk/batch endpoints.

## 4. Auth & session
- Collect many tokens → entropy/predictability check. Session id before/after login → fixation.
- **JWT battery:** `alg:none`; algorithm confusion (verify RS with public key as HMAC secret);
  tampered claims; expired `exp`; missing `aud`/`iss`. See which the target accepts.
- Password-reset flow: token reuse, guessing, non-invalidation, host-header poisoning, enumeration.
- MFA: step-skip, code replay, unbound code, unlimited attempts. Lockout: attempt flooding.

## 5. SSRF / CSRF / CORS / redirect
- **SSRF:** point the fetcher at a **mock in-sandbox** service; try `file://`/`gopher://`, redirect
  bypass, and a mocked metadata endpoint. Never target real internal/cloud IPs.
- **CSRF:** forged cross-origin state-changing request with a valid cookie, no token → success?
- **CORS:** vary `Origin`, inspect ACAO/ACAC reflection; test `null` and sloppy matching.
- **Open redirect:** external / scheme-relative / encoded targets; note chain potential.

## 6. Deserialization / XXE / path / upload / mass assignment
- **Deserialization:** crafted payloads that instantiate types / trigger callbacks (benign,
  in-sandbox); combine with fuzzing.
- **XXE:** external entity to a mocked in-sandbox resource; billion-laughs for DoS.
- **Path traversal:** `../`, absolute, encoded/double-encoded/Unicode, null byte; zip-slip archives.
- **Upload:** dangerous extensions, content-type mismatch, polyglots, oversized; check storage/serve.
- **Mass assignment:** POST privileged/extra fields and prototype-polluting keys; confirm effect.

## 7. Crypto & secrets
- Demonstrate consequence: predict a token from weak randomness; show ECB block patterns; tamper a
  non-authenticated ciphertext and have it accepted; trigger verbose errors; hit debug/admin routes
  with low-priv/anonymous principals; inspect sandbox logs for secret leakage.

## 8. Web/API surfaces
- **XSS:** context-appropriate payloads (HTML/attr/JS/URL); stored→rendered paths; mutation-XSS.
- **Headers/framing:** inspect response headers; attempt to frame sensitive pages.
- **GraphQL:** introspection; deep/nested and aliased/batched queries; cross-user field access.
- **gRPC:** per-method authz with each privilege; reflection enumeration; oversized messages.
- **Websockets:** foreign-origin connect with valid session; privileged messages as low-priv; flood.

## 9. Business logic, races, DoS
- **Logic:** walk workflows with throwaway accounts; skip/reorder/replay steps; tamper economic
  params; violate state transitions; confirm the forbidden outcome.
- **Races/TOCTOU:** fire concurrent requests at check-then-act operations; look for the invariant
  breaking (double-redeem, negative balance, duplicate create).
- **DoS:** oversized/pathological inputs (ReDoS strings, nested JSON/GraphQL, expansion bombs);
  measure in-sandbox resource impact; require a *realistic* trigger.

## 10. Fuzzing
Target parsers, deserializers, file handlers, and permissive/typed API parameters. Feed malformed,
oversized, boundary, and structurally-invalid inputs; watch for crashes, hangs, unhandled
exceptions, and state corruption. Minimize any crashing input to the smallest reproducer and treat
it as a candidate to validate like any other. Keep the fuzzing scoped to the sandboxed target.

## 11. Exploit chaining
Look for primitives that feed each other: open redirect → SSRF → metadata credential theft; IDOR →
privilege escalation → data access; XSS → session/token theft → account takeover; file upload →
path control → code exposure; race → limit bypass → economic abuse. Build one PoC that runs the
chain end-to-end, give it a C-ID, score it on combined impact, and record which single fix severs
it (Stage 6d re-tests that).

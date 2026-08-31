# Domain: Web UI & API Surfaces (XSS, headers, GraphQL, gRPC, websockets)

**Maps to:** OWASP A03 (XSS as injection), A05 (misconfiguration/headers), and the OWASP API
Security Top 10; CWE-79 (XSS), CWE-1021 (clickjacking/framing), CWE-693 (protection mechanism
failure). Load when the project exposes a browser UI or a REST/GraphQL/gRPC/websocket API.

## Cross-Site Scripting (CWE-79)
**Look for:** input reflected into HTML/JS/attribute/URL contexts without context-correct encoding;
`innerHTML`/`dangerouslySetInnerHTML`/template `| safe` filters on user data; DOM sinks fed by
`location`/`postMessage`; stored content rendered without sanitization. **Why exploitable here:**
identify the exact sink and the missing/incorrect encoding for *that* context (HTML body vs.
attribute vs. JS vs. URL differ). **Test in sandbox:** inject context-appropriate payloads and
confirm script execution or attribute breakout against the running UI; check stored→rendered paths.
**Fix:** context-aware output encoding (let the framework auto-escape; avoid raw-HTML sinks),
sanitize rich HTML with a vetted library, and add a **Content-Security-Policy** as defense-in-depth.
Bypass battery: alternate contexts, encoded/broken-up payloads, mutation-XSS.

## Security headers & framing
**Look for:** missing/weak `Content-Security-Policy`, `X-Content-Type-Options: nosniff`,
`Strict-Transport-Security`, and anti-framing (`X-Frame-Options`/CSP `frame-ancestors` →
clickjacking, CWE-1021); overly permissive `Referrer-Policy`/`Permissions-Policy`. **Test:** inspect
response headers; attempt to frame sensitive pages. **Fix:** set a tuned CSP, HSTS, nosniff, and
`frame-ancestors`; don't ship security headers only on some routes.

## GraphQL
**Look for:** introspection enabled in production; no query depth/complexity limits (DoS via nested
queries); missing field-level authorization (a resolver returning data the caller can't access —
overlaps `access-control.md`); batching/aliasing used to amplify or brute-force; verbose errors.
**Test in sandbox:** run introspection, deeply-nested and aliased/batched queries, and cross-user
field access with different-privilege tokens. **Fix:** disable introspection where appropriate,
enforce depth/complexity/cost limits and rate limits, apply authorization at the resolver/field
level, and trim error verbosity.

## gRPC
**Look for:** missing per-RPC authentication/authorization (transport auth ≠ per-method authz);
reflection exposed publicly; missing message size limits; insecure channel (no TLS). **Test in
sandbox:** call methods with each privilege level; enumerate via reflection if enabled; send
oversized messages. **Fix:** enforce per-method authz, disable public reflection, set size limits,
require TLS.

## Websockets
**Look for:** no `Origin` validation on the upgrade (cross-site websocket hijacking); auth performed
only at handshake with unauthenticated message handlers; per-message authorization missing;
no rate limiting. **Test in sandbox:** connect from a foreign origin with a valid session; send
privileged messages as a low-priv principal; flood messages. **Fix:** validate `Origin` on upgrade,
authenticate the connection *and* authorize each message, and rate-limit.

## API-wide concerns
Excessive data exposure (returning whole objects and filtering client-side), lack of resource/rate
limiting, and inconsistent authz across REST/GraphQL/websocket entrances to the same logic — always
re-test each fixed control through *every* API surface (Stage 6 bypass step).

# Domain: Broken Access Control & IDOR

**Maps to:** OWASP A01:2021 Broken Access Control; CWE-639 (IDOR / authorization bypass via
user-controlled key), CWE-284 (improper access control), CWE-862 (missing authorization),
CWE-863 (incorrect authorization), CWE-566 (privilege escalation).

Access control is the hardest class to catch statically because the bug is usually an **absence** —
a check that should be there and isn't — and because "authenticated" is routinely confused with
"authorized." Enumerate deliberately.

## What to look for statically
- **Object references by ID:** endpoints that take an `id`/`uuid`/filename/account number and fetch
  or mutate the object **without verifying the current principal owns or may access it** (IDOR /
  BOLA). Look for `find(id)` with no `AND owner = current_user` equivalent.
- **Missing function-level authz:** admin/privileged actions whose only protection is that the UI
  doesn't link to them (forced browsing), or a role check on the list endpoint but not the detail/
  mutate endpoint.
- **Vertical escalation:** a low-priv user reaching high-priv functionality; role/permission derived
  from a client-supplied value (a header, a JWT claim the client can set, a form field).
- **Horizontal escalation:** user A acting on user B's resources.
- **Inconsistent enforcement:** authz enforced in middleware for some routes but bypassed for
  others (e.g. a second router, an internal endpoint, a websocket message handler, a batch API).
- **Mass assignment adjacency:** an update that lets the client set fields like `role`,
  `is_admin`, `owner_id` (also see `data-and-deserialization.md`).

## Why it's exploitable *here*
Map each object-accessing endpoint to the authorization decision that guards it, and find the ones
with none or with a client-controllable basis. Confirm the resource is genuinely another
principal's and that the action has impact (read PII, mutate state, escalate).

## How to test in the sandbox (Stage 4)
- Provision accounts at each privilege level (anonymous, user A, user B, admin). This multi-account
  setup is what makes access-control testing possible — see `sandbox-setup.md`.
- **Horizontal:** as user A, request/mutate user B's object IDs; success = IDOR.
- **Vertical:** as a low-priv user, call admin functions directly (not via the UI); tamper with
  role-carrying values and see if privilege changes.
- **Forced browsing:** hit un-linked but guessable/known routes with a low-priv token.
- **Enforcement gaps:** exercise the same action through every interface (REST, GraphQL, websocket,
  batch/bulk endpoint, internal API) — a check on one path often doesn't cover the others.
- Feed these into **exploit chaining** (IDOR → privesc is a common chain).

## Root-cause fixes (Stage 6 direction)
- Enforce authorization **server-side, at the resource**, keyed to the authenticated principal —
  centralize it so every path shares one decision rather than re-implementing (and forgetting) it.
- Derive identity and role from the **server-side session/verified token**, never from a
  client-settable field.
- Use non-guessable references only as defense-in-depth, not as the authorization control.
- Family tests must cover: every privilege level × every object-accessing route (negative: other
  principals blocked; positive: rightful owner still works). Bypass tests must re-try each fixed
  route through the *other* interfaces to prove the check isn't only on the front door.

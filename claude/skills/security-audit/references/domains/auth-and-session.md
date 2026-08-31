# Domain: Authentication & Session Management

**Maps to:** OWASP A07:2021 Identification & Authentication Failures; CWE-287 (improper auth),
CWE-384 (session fixation), CWE-345/CWE-347 (insufficient verification / improper signature
verification, incl. JWT), CWE-522 (insufficiently protected credentials), CWE-640 (weak password
recovery), CWE-307 (improper restriction of excessive auth attempts).

## What to look for statically
- **Token/session generation:** predictable or low-entropy session IDs/tokens; tokens derived from
  guessable inputs (user id + timestamp); tokens not rotated on privilege change.
- **Session fixation:** session identifier not regenerated at login.
- **JWT pitfalls:** `alg: none` accepted; algorithm not pinned (HS/RS confusion — verifying an
  RS256 token with the public key as an HMAC secret); missing `exp`/`nbf`/`aud`/`iss` checks;
  signature not actually verified; secret weak or committed.
- **Credential storage/transport:** passwords hashed with fast/weak or unsalted algorithms (MD5,
  SHA-1, unsalted SHA-256) instead of a slow KDF (bcrypt/scrypt/argon2); secrets/credentials sent
  or logged in the clear; API keys compared with non-constant-time equality.
- **Password reset / account recovery:** guessable or long-lived reset tokens; reset that doesn't
  invalidate sessions; host-header-based reset links (poisoning); user-enumeration via differing
  responses.
- **MFA:** bypassable second factor (skippable step, code not bound to session, unlimited attempts,
  reusable codes), or MFA enforced on login but not on sensitive actions.
- **Rate limiting / lockout:** absent on login, token, OTP, and reset endpoints.

## Why it's exploitable *here*
Pin down the concrete weakness: which algorithm, which endpoint, which missing check. "Uses JWT" is
not a finding; "the verifier accepts `alg:none`, so a forged unsigned token authenticates as any
user" is. Note preconditions.

## How to test in the sandbox (Stage 4)
- **Token strength:** collect many tokens from the running target and check for structure/low
  entropy/predictability.
- **Fixation:** capture pre-login session id, authenticate, check whether it changed.
- **JWT:** craft tokens with `alg:none`, with the algorithm swapped, with tampered claims, and with
  an expired `exp`, and see which the target accepts.
- **Credential handling:** confirm hashing choice from behavior/config; test constant-time compare
  by timing where feasible.
- **Reset/MFA flows:** walk the full flow with throwaway accounts — try token reuse, token
  guessing, skipping the MFA step, replaying codes, and poisoning the reset link host header.
- **Lockout:** hammer the login/OTP endpoint (in-sandbox) to confirm whether attempts are limited.

## Root-cause fixes (Stage 6 direction)
- Generate tokens from a CSPRNG with adequate length; regenerate session IDs on login and
  privilege change; set short, sensible lifetimes.
- **JWT:** pin the exact expected algorithm; reject `none`; verify signature and all of
  `exp/nbf/aud/iss`; keep the secret/key out of the repo and strong.
- Hash passwords with argon2id/bcrypt/scrypt + per-user salt; use constant-time comparison for
  secrets; never log credentials.
- Make reset tokens single-use, short-lived, and session-invalidating; build reset links from
  server config, not the Host header; equalize responses to prevent enumeration.
- Enforce MFA on sensitive actions, bind codes to the session, cap attempts.
- Rate-limit/lock out auth-adjacent endpoints. Verify each with family + bypass tests (e.g. after
  pinning the JWT algorithm, re-try `none` and the confusion attack and confirm both now fail).

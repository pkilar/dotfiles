# Domain: Cryptographic Misuse & Secrets/Data Exposure

**Maps to:** OWASP A02:2021 Cryptographic Failures; CWE-327 (broken/risky algorithm), CWE-329/
CWE-330 (static IV / weak randomness), CWE-798 (hardcoded credentials), CWE-312/CWE-532 (cleartext
or logged sensitive data), CWE-209 (information exposure via error messages).

## Cryptographic misuse
**Look for:**
- **Weak or misused algorithms:** MD5/SHA-1 for security purposes; DES/RC4/ECB-mode ciphers;
  RSA without proper padding; homemade crypto.
- **Static or reused IVs/nonces/keys;** keys embedded in source; a single global key with no
  rotation; nonce reuse in AEAD (catastrophic for GCM).
- **Weak randomness:** non-CSPRNG (`Math.random`, `rand()`) for tokens, keys, IVs, salts.
- **Missing integrity:** encryption without authentication (no MAC/AEAD); trusting ciphertext that
  can be tampered (padding-oracle-prone constructions).
- **TLS/transport:** disabled certificate verification; downgraded/legacy protocol versions.

**Why exploitable here:** tie it to impact — e.g. "session tokens are AES-ECB with a static key, so
identical plaintext blocks leak and tokens are forgeable," not just "uses ECB." **Test in sandbox:**
demonstrate the concrete consequence where feasible (predict a token from observed randomness,
show ECB block patterns, tamper a non-authenticated ciphertext and have it accepted). **Fix:** use
vetted primitives via a maintained library — AEAD (AES-GCM/ChaCha20-Poly1305) with unique nonces,
argon2/bcrypt/scrypt for passwords, SHA-256+ for hashing, CSPRNG for all secret material, proper
RSA/EC padding, and enforced TLS certificate verification. Never roll your own.

## Secrets & data exposure
**Look for:**
- **Hardcoded credentials/keys** in source, config, or committed history (`path:line` — record the
  location, don't propagate the value); secrets baked into container images or client bundles.
- **PII / sensitive data exposure:** endpoints returning more than the caller needs; sensitive data
  in URLs (logged everywhere), in caches, or in client-visible responses.
- **Verbose errors / debug surfaces:** stack traces, SQL, or internal paths returned to clients;
  debug endpoints, profilers, or admin consoles reachable in production config.
- **Sensitive data in logs:** credentials, tokens, full PII, or card/financial data written to logs.

**Why exploitable here:** confirm the secret is live/reachable or the data is genuinely sensitive
and exposed to a party who shouldn't see it. **Test in sandbox:** trigger error paths and inspect
responses; hit debug/actuator/admin routes with a low-priv or anonymous principal; check log output
(in the sandbox) for secret leakage. **Fix:** move secrets to a secrets manager / environment
injection and **rotate anything that was committed** (flag rotation as an out-of-scope operational
follow-up in the report — the code fix alone doesn't undo exposure); return minimal fields; disable
debug in production config; scrub logs and add redaction; keep secrets out of URLs and client
bundles.

## Note on committed-secret findings
A committed secret is both a code finding (remove it, load from a manager) **and** an operational
one (rotate it, and treat it as potentially compromised). Capture both in the ledger and carry the
rotation item into the final report's out-of-scope follow-ups.

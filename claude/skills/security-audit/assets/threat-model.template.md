<!--
SCHEMA: threat-model.md — the project's threat model, kept alive across stages.
Not a generic STRIDE dump: it is anchored to THIS project's components, actors, and assets, and
it is what tells Stage 3/4 which abuse cases are worth chasing.

WRITE-BACK TRIGGER:
- Stage 1: seed from recon — actors, assets, trust boundaries, first-cut per-component threats.
- Stage 2: refine using the loaded domain references and SCA intel (add framework-specific
  threats, supply-chain threats for reachable CVEs).
- Stage 4: mark which hypothesized threats were actually demonstrated (link to finding IDs), and
  record any new abuse case discovered while testing.
-->

# Threat Model — <project name>

## Actors & trust levels
| Actor | Trust level | How they reach the system | What they should NOT be able to do |
|-------|-------------|---------------------------|-------------------------------------|
| Anonymous / internet | untrusted | | |
| Low-priv authenticated user | semi-trusted | | |
| Admin / privileged | trusted | | |
| Service / job / integration | varies | | |

## Assets to protect
- **Data:** (PII, credentials, tokens, financial/regulated data, business records)
- **Integrity/availability:** (which operations must not be forged, replayed, or exhausted)
- **Secrets:** (keys, signing material, DB creds)

## Trust boundaries
Where control crosses from less-trusted to more-trusted (network edge, auth middleware, service
hops, deserialization points). For each, note what enforcement sits on the boundary.

## Per-component threats
For each significant component/entry point, enumerate plausible threats. Use STRIDE as a
prompt (Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of
privilege) but only record threats that make sense here.
| Component | Threat | STRIDE | Prerequisite | Mapped domain | Status |
|-----------|--------|--------|--------------|---------------|--------|
| | | | (auth? config?) | (which domain file) | hypothesized / demonstrated (→ F-ID) / n/a |

## Abuse cases (domain-specific workflow attacks)
Business-logic misuse specific to what the app does (e.g. "replay a signed request to double-spend",
"skip the approval step by calling the finalize endpoint directly"). These often don't map to a
generic CWE and are easy to miss — enumerate them deliberately.

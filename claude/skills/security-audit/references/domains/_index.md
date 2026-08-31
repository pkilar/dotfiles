# Domain Reference Index

Load **only** the domain files whose triggers match this target (from `recon.md`). Each file is a
depth reference for Stage 3 (what to look for statically, and why it's exploitable in context) and
Stage 4 (how to test it in the sandbox), plus the root-cause fix direction for Stage 6 and the
standards it maps to.

All domain guidance is defensive: it describes how to find, prove-against-your-own-target, and fix
weaknesses. It is not a recipe for attacking systems you don't own.

## Classification → domains

| If the project has… | Load |
|---------------------|------|
| Any code that builds queries/commands/paths/templates from input | `injection.md` |
| Any authenticated multi-user surface or object references by ID | `access-control.md` |
| Login, sessions, tokens, JWT, password reset, MFA, API keys | `auth-and-session.md` |
| Outbound requests, URL handling, cross-origin config, redirects | `request-forgery-and-cors.md` |
| Deserialization, XML parsing, file uploads, path handling, object binding | `data-and-deserialization.md` |
| Encryption, signing, hashing, randomness, or any secret/key handling | `crypto-and-secrets.md` |
| Third-party dependencies with lockfiles (i.e. almost always) | `supply-chain.md` |
| Terraform/CloudFormation/K8s/Docker/cloud config | `iac-and-cloud.md` |
| A browser-facing web UI, REST/GraphQL/gRPC, or websockets | `web-and-api-surfaces.md` |
| Multi-step workflows, money/quota/state machines, or DoS-exposed endpoints | `business-logic-and-dos.md` |

Most web apps implicate the majority of these. A CLI tool might only implicate `injection`,
`crypto-and-secrets`, `data-and-deserialization`, and `supply-chain`. An IaC repo leans on
`iac-and-cloud` and `secrets`. Scope honestly and record what you dropped in `recon.md`.

## Cross-cutting standards (referenced by the domain files)
- **OWASP Top 10** and **OWASP ASVS** — web/app baseline and verification levels.
- **CWE Top 25** — the common weakness classes; every finding gets a CWE.
- **OWASP Web Security Testing Guide / Cheat Sheet Series** — testing techniques and fix patterns.
- **CIS Benchmarks** — for OS/container/cloud/IaC hardening (see `iac-and-cloud.md`).
- Framework- and language-specific hardening guides — gathered per project in Stage 2.

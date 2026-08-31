<!--
SCHEMA: recon.md — output of Stage 1 (Reconnaissance & first-pass evaluation).
This is the structured picture of what the project IS and where it can be attacked. Everything
downstream (which domains to load, what to taint-trace, what to stand up in the sandbox) keys off
this file, so be concrete and cite exact paths.

WRITE-BACK TRIGGER:
- Stage 1: fill every section from the read-only survey. This is the primary deliverable of S1.
- Stage 3: if static analysis reveals a source/sink/surface the survey missed, correct it here
  and note the correction in AUDIT-LOG.md (don't silently diverge).
-->

# Reconnaissance — <project name>

## 1. Stack inventory
- **Languages / runtimes:** (with versions)
- **Frameworks / major libraries:** (with versions)
- **Package managers / lockfiles:** (paths)
- **Exact dependency versions:** (point to `sca-inventory.md`, which owns the full list)
- **Build / CI-CD / containerization / IaC:** (files: Dockerfile, CI configs, Terraform, etc.)

## 2. Entry points & exposed interfaces
List each with its file:line. Cover all that apply:
| Interface | Location | Auth required? | Notes |
|-----------|----------|----------------|-------|
| HTTP/REST route | | | |
| GraphQL / gRPC / websocket | | | |
| CLI command | | | |
| Scheduled job / cron | | | |
| Queue / event consumer / webhook | | | |
| File-upload handler | | | |
| Admin / internal surface | | | |

## 3. Data layer
- **Databases + access style:** (ORM vs raw queries — which, where)
- **Caches / object or blob storage / message brokers:**

## 4. AuthN / AuthZ surfaces
- **Session management / token issuance & validation:**
- **Credential & password handling:**
- **RBAC / ABAC / middleware / trust decisions:** (where enforcement lives)

## 5. Secrets & configuration
- **Env / config handling:**
- **Hardcoded credentials or keys observed:** (path:line — record, don't exfiltrate values)
- **Config that changes security posture:** (debug flags, CORS, TLS, feature toggles)

## 6. Trust-boundary & data-flow map (source → sink)
The core of recon. Enumerate untrusted **sources** and the sensitive **sinks** they can reach.
| # | Source (untrusted input) | Path taken | Sink (dangerous operation) | Guard present? |
|---|--------------------------|-----------|----------------------------|----------------|
| | request param/header/body, upload, external API resp, queue msg, env/config | | query exec, command exec, deserialization, file path, template render, HTTP client, auth decision | validation/encoding/parameterization/authz — or NONE |

Sources → sinks with **no adequate guard** are the priority taint flows for Stage 3.

## 7. Project classification & applicable domains
- **Classification:** (e.g. web API + Postgres; CLI tool; IaC repo; data pipeline; library)
- **Applicable security domains** (drives which `references/domains/*` to load — see
  `domains/_index.md`):
  - [ ] injection
  - [ ] access-control
  - [ ] auth-and-session
  - [ ] request-forgery-and-cors
  - [ ] data-and-deserialization
  - [ ] crypto-and-secrets
  - [ ] supply-chain
  - [ ] iac-and-cloud
  - [ ] web-and-api-surfaces
  - [ ] business-logic-and-dos
- **Explicitly out of scope for this target, and why:**

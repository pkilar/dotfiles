# Stage 1 — Reconnaissance & First-Pass Evaluation (read-only)

**Goal:** build a structured, evidence-cited picture of what the project is and where it can be
attacked, so every later stage adapts to *this* stack instead of a generic template. **Do not
modify any project file in this stage.**

Output lands in `recon.md`, seeds `threat-model.md`, and creates the initial `coverage-matrix.md`
rows. Close the stage by appending to `AUDIT-LOG.md`.

## Why this stage carries so much weight
The classification you produce here decides which domain references you load (Stage 2), which
taint flows you trace (Stage 3), and what you stand up in the sandbox (Stage 4). A shallow recon
quietly caps the quality of everything after it. Spend the effort to be concrete: name files,
routes, and functions, not categories.

## Procedure

### 1. Map the tree, then read the important parts
- Get the layout and size first (respect `.gitignore`; note vendored deps). Identify the build
  system and how the app is started — entrypoints, `main`, server bootstrap, container `CMD`.
- Read the dependency manifests and lockfiles for exact versions; hand the full dependency list
  to `sca-inventory.md` (Stage 2 owns the CVE research, but capture versions now).

### 2. Enumerate the stack
Languages, runtimes, frameworks, major libraries, package managers, lockfiles — all with
versions. Note build, CI/CD, containerization, and infrastructure-as-code files.

### 3. Enumerate entry points & exposed interfaces
Every place untrusted input can enter, with `file:line`:
HTTP/REST routes, GraphQL/gRPC/websockets, CLI commands, scheduled jobs/cron, queue/event
consumers, webhooks, file-upload handlers, admin/internal surfaces. For each, note whether auth
is required. These become rows in the coverage matrix.

### 4. Enumerate the data layer
Databases and how they're queried (ORM vs. raw SQL — and *where* raw queries live, since those
are prime injection candidates). Caches, object/blob storage, message brokers.

### 5. Enumerate AuthN/AuthZ surfaces
Session management; token issuance and validation; password/credential handling; RBAC/ABAC;
middleware; and every place a trust decision is made. Locate where enforcement actually happens
(and, by implication, where it's missing).

### 6. Enumerate secrets & configuration
Env/config handling; any hardcoded credentials or keys (record `path:line` — do **not** copy the
secret values around); key management; and config that changes security posture (debug flags,
CORS policy, TLS settings, feature toggles, permissive defaults).

### 7. Derive the trust-boundary & source→sink data-flow map
This is the analytic core. Enumerate untrusted **sources** (request params/headers/body, uploads,
external API responses, queue messages, env/config) and the sensitive **sinks** they can reach
(query execution, command execution, deserialization, file-path operations, template rendering,
outbound HTTP clients, auth decisions). For each source→sink pair, note whether an adequate guard
(validation, encoding, parameterization, authorization) sits in between. Pairs with **no adequate
guard** are the priority flows for Stage 3.

### 8. Classify the project and select applicable domains
From everything above, state the classification (e.g. "web API on Postgres with file uploads",
"CLI packaging tool", "Terraform IaC repo", "async data pipeline", "reusable library") and tick
the security domains that actually apply. Use `references/domains/_index.md` to map classification
→ domain files. Record what's explicitly out of scope and why — scoping decisions are part of the
audit trail.

## Write-back before leaving Stage 1
- `recon.md`: all sections filled.
- `threat-model.md`: seed actors, assets, trust boundaries, first-cut per-component threats.
- `coverage-matrix.md`: one row per attack surface/entry point.
- `AUDIT-LOG.md`: stamped entry — what you surveyed, the classification, and what Stage 2 should load.

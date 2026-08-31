# Sandbox Setup (Stage 4a)

The sandbox is what makes an aggressive pentest safe: it contains the blast radius so that
confirming and fixing vulnerabilities can't touch anything real. Set it up before any dynamic
testing, and hold the isolation invariants below throughout.

## Isolation invariants (non-negotiable)
- **Network isolation.** The target runs with no route to production, internal networks, real
  cloud metadata endpoints, or the public internet beyond what a mock provides. Deny egress by
  default; allow only in-sandbox service-to-service traffic. This is what guarantees that an SSRF
  or command-exec PoC can't reach a real system.
- **Synthetic data only.** Seed with fabricated users, records, and files. No production dumps, no
  real PII, no real financial data — even "anonymized" real data doesn't belong here.
- **Mock/stub every external dependency.** Payment gateways, email/SMS, third-party APIs, OAuth
  providers, object storage, and especially any cloud **metadata** service get local mocks. SSRF
  tests point at these mocks, never at real endpoints.
- **Throwaway credentials.** Generate fresh secrets/keys for the sandbox. Never load real secrets,
  API keys, or signing material into it. If the app needs a secret to boot, mint a fake one.
- **Ephemeral & reproducible.** Prefer containers so the environment is disposable and rebuildable;
  capture the exact build/seed steps so the report appendix lets anyone reproduce it.

## Standing the target up
1. Identify the run recipe from Stage 1 (Dockerfile/compose, run scripts, required services).
2. Bring up dependencies as local containers/mocks (database, cache, broker, mock external APIs).
3. Boot the target against those, with sandbox config (debug off unless a finding needs it,
   fake secrets, isolated network).
4. Smoke-test that core flows work, so a failed exploit means "not vulnerable," not "app is broken."

## Multi-privilege test accounts (needed for access-control and auth testing)
Provision and record credentials for each relevant level — this is a prerequisite for most of the
interesting findings:
- **Anonymous** (no auth).
- **Low-priv user A** and **low-priv user B** (two separate users → horizontal IDOR testing).
- **Elevated/admin** (vertical escalation testing).
- **Service/integration** principal if the app has machine-to-machine auth.
Keep these in `poc-test-catalog.md` so every PoC states which principal it used.

## If the target can't be fully instantiated
Some projects won't stand up completely (missing proprietary service, hardware dependency, cloud-
only component). Then:
- Stand up the **maximum feasible subset** and test everything that does run.
- For the rest, fall back to static reasoning and **tag any resulting finding `static-only,
  unproven`** with a clear rationale in the ledger.
- Record the instantiation limits in `AUDIT-LOG.md` and the coverage matrix so the gap is visible,
  not hidden. Partial dynamic coverage plus honest labeling beats pretending everything was tested.

## Teardown
Destroy the sandbox and its synthetic data when done (or hand over the reproducible recipe so the
user can rebuild it). Nothing from the sandbox should persist into a real environment.

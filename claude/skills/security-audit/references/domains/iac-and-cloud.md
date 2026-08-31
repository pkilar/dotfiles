# Domain: Infrastructure-as-Code & Cloud Misconfiguration

**Maps to:** OWASP A05:2021 Security Misconfiguration; CWE-16 (configuration), CWE-732 (incorrect
permission assignment). Benchmark against the relevant **CIS Benchmarks** (cloud provider,
Kubernetes, Docker, Linux).

Much of this domain is **static-only by nature** — you're auditing declarations, not a running
system — and that's a legitimate outcome to tag, provided the reasoning is concrete. Where a
sandbox can instantiate the config (e.g. `docker compose` locally, `terraform plan`/policy
evaluation), do so; never apply against real cloud accounts.

## What to look for
- **Network exposure:** security groups/firewall rules open to `0.0.0.0/0` on sensitive ports; DBs
  or admin services publicly reachable; missing network segmentation.
- **Identity & permissions:** over-broad IAM policies (`*` actions/resources); wildcard trust
  relationships; long-lived static credentials; roles a compromised workload could abuse.
- **Storage:** public object storage buckets; unencrypted volumes/buckets; missing bucket policies;
  logging/versioning disabled where it matters.
- **Encryption & transport:** encryption-at-rest disabled; TLS not enforced; weak TLS policy.
- **Kubernetes:** privileged containers, `hostNetwork`/`hostPath`, missing resource limits, over-
  permissive RBAC, secrets as plain env, no network policies, running as root.
- **Docker:** running as root, secrets baked into layers, `latest` tags, no user namespace, large
  attack surface base images.
- **Secrets in IaC:** credentials/keys hardcoded in Terraform vars, manifests, or state (also see
  `crypto-and-secrets.md`).
- **Logging/auditing:** disabled audit trails, no flow logs, drift from declared state.

## Why it's a finding *here*
Tie each misconfiguration to a concrete exposure in this deployment: "the RDS security group allows
`0.0.0.0/0:5432` and the instance is in a public subnet, so the database is internet-reachable," not
"security group is broad." Note whether it's exploitable as-declared or contingent on other config.

## How to validate (Stage 4)
- Prefer **policy-as-code / static evaluation** of the IaC (e.g. `terraform plan` output, config
  linting/policy checks) run locally against the definitions — no real infrastructure.
- Where a component can be stood up in the sandbox (containers, local clusters), instantiate and
  probe it there (e.g. confirm a container runs as root, a port is exposed).
- For anything only assertable against live cloud, keep it **static-only** with a clear rationale
  and route it to the report's out-of-scope/manual follow-ups.

## Root-cause fixes (Stage 6 direction)
- Least-privilege IAM (scoped actions + resources, no wildcards); short-lived credentials.
- Close public exposure; segment networks; put data services in private subnets.
- Enforce encryption at rest and in transit; make buckets private with explicit policies.
- Harden containers/K8s to CIS (non-root, drop capabilities, resource limits, RBAC least-privilege,
  network policies); pin image digests; keep secrets in a manager, not manifests/state.
- **Verification:** re-run the policy checks / re-instantiate and confirm the misconfiguration is
  gone; keep the policy check as a CI guard (a config regression test). Operational rollout to real
  environments is an out-of-scope follow-up to call out explicitly.

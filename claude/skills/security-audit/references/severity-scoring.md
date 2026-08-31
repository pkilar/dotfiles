# Severity Scoring (Stage 4f)

Every confirmed finding gets a **CVSS vector + numeric score + a one-line justification**, plus its
**exploitability preconditions**. The vector matters as much as the number — it shows your reasoning
and lets the reader re-judge for their own context.

## Which version
Use **CVSS v3.1** by default (most widely understood); use **v4.0** if the user/organization
standardizes on it. State which you used. Keep it consistent across the report.

## v3.1 base metrics (quick reference)
- **AV** Attack Vector: Network / Adjacent / Local / Physical.
- **AC** Attack Complexity: Low / High.
- **PR** Privileges Required: None / Low / High — this is where the finding's auth precondition
  lands; be honest (an IDOR needing a logged-in account is PR:L, not PR:N).
- **UI** User Interaction: None / Required (e.g. CSRF and many XSS need UI:R).
- **S** Scope: Unchanged / Changed (Changed when the vuln affects resources beyond its security
  scope — e.g. SSRF reaching the cloud metadata service, or a container escape).
- **C/I/A** Confidentiality / Integrity / Availability impact: None / Low / High.

## Anchoring examples (calibrate, don't copy blindly)
- **Unauth SQLi dumping the database:** `AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H` → ~9.8 Critical.
- **Authenticated IDOR reading another user's PII:** `AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N` → ~6.5.
- **Reflected XSS:** `AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N` → ~6.1 Medium.
- **CSRF changing account state:** `AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:N` → ~6.5.
- **SSRF reaching internal/metadata (scope change):** raise via S:C and the confidentiality of what
  it reaches; often High/Critical.
- **ReDoS on an unauthenticated endpoint:** `AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H` → ~7.5.

## Preconditions (record alongside the score)
The score assumes the vector; the preconditions say when that vector actually holds. Note:
- Auth level required (drives PR).
- Non-default configuration or feature flags needed.
- Whether a specific state/timing/race window is required.
- Whether it's only reachable through a particular interface.
These directly inform Stage 5 ordering: a Critical that needs an unusual precondition may rank below
a High that anyone can trigger unauthenticated.

## Chains
Score the **chain** on its combined impact (usually higher than any single member) with its own
vector and C-ID. A chain that turns a low-priv foothold into full compromise is Critical even if
each link is Medium.

## Reporting
Put the vector string next to the score everywhere it appears, so a reader who disagrees with your
environmental assumptions can re-derive their own number.

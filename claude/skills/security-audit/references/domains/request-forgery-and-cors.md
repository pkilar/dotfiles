# Domain: SSRF, CSRF, CORS & Open Redirect

**Maps to:** OWASP A10:2021 SSRF; CWE-918 (SSRF), CWE-352 (CSRF), CWE-942/CWE-346 (permissive
CORS / origin validation), CWE-601 (open redirect).

These share a theme: the server or browser is tricked into making a request *it shouldn't*, to a
destination the attacker influences. SSRF in particular is a frequent pivot in exploit chains.

## SSRF (Server-Side Request Forgery)
**Look for:** any place the server fetches a URL derived from input — webhooks, "import from URL",
link preview/unfurl, PDF/image fetchers, SSO metadata, server-side proxies, or a library that
follows redirects. **Why exploitable here:** confirm the destination is attacker-controlled and not
restricted to an allow-list, and that the response (or its side effects/timing) is observable.
**Test in sandbox:** point the fetcher at a mock internal service you stand up in the sandbox
(never a real internal or cloud endpoint) and confirm the server reaches it; try to reach a mocked
"metadata" service, alternate schemes (`file://`, `gopher://`), redirect-based bypasses, and
DNS-rebinding-style hostnames if relevant. **Fix:** allow-list destinations (scheme + host), resolve
and validate the IP (block private/link-local/loopback ranges), disable unwanted schemes, don't
follow redirects to disallowed hosts, and isolate the fetcher's network egress.

## CSRF (Cross-Site Request Forgery)
**Look for:** state-changing endpoints that rely only on ambient credentials (cookies) with no
anti-CSRF token, `SameSite` protection, or origin check — especially form posts and non-JSON
endpoints. **Why exploitable here:** confirm the action is state-changing, cookie-authenticated, and
accepts a cross-site request. **Test in sandbox:** issue a forged cross-origin request against the
running target with a valid session cookie and no token, and see if the action succeeds. **Fix:**
per-request anti-CSRF tokens (or double-submit), `SameSite=Lax/Strict` cookies, and origin/referer
validation on state-changing routes; prefer non-cookie auth for APIs.

## CORS misconfiguration
**Look for:** `Access-Control-Allow-Origin` reflecting the request Origin, `*` combined with
`Allow-Credentials: true`, trusting `null`, or sloppy suffix/prefix origin matching. **Why
exploitable here:** confirm a malicious origin would be granted credentialed cross-origin reads of
sensitive data. **Test in sandbox:** send requests with crafted `Origin` headers and inspect the
returned ACAO/ACAC headers. **Fix:** strict origin allow-list; never reflect arbitrary origins with
credentials; don't trust `null`.

## Open redirect
**Look for:** redirect targets taken from input (`?next=`, `?returnUrl=`) without validation; often
low-severity alone but a force-multiplier in chains (phishing, SSRF, OAuth token theft). **Test in
sandbox:** supply external/scheme-relative/encoded targets and see where the redirect lands.
**Fix:** allow-list relative paths or a fixed set of hosts; reject absolute/scheme-relative targets.

## Chaining note
Open redirect → SSRF → cloud-metadata credential theft, and CSRF → state change → privesc, are
classic chains. Attempt these combinations in Stage 4e; verify the sever point in Stage 6d.

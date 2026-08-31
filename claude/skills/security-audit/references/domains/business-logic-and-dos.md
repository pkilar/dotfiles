# Domain: Business-Logic Abuse, Concurrency & Denial of Service

**Maps to:** CWE-840 (business-logic errors), CWE-362/CWE-367 (race condition / TOCTOU),
CWE-770/CWE-400 (resource allocation without limits / uncontrolled resource consumption). This is
the domain scanners can't find for you — it requires understanding what the application is *for*.

## Business-logic abuse
**Look for (from the threat model's abuse cases):** workflows where steps can be skipped, reordered,
or replayed to reach a state the design forbids. Common shapes:
- **Step-skipping:** calling a "finalize"/"confirm" endpoint directly, bypassing validation,
  payment, or approval steps.
- **Replay / idempotency abuse:** replaying a signed/authorized request to double-apply an effect
  (double-spend, double-redeem, re-trigger a payout).
- **Quantity/price/parameter tampering:** negative quantities, price fields the client shouldn't
  set, coupon/discount stacking, quota manipulation.
- **State-machine violations:** transitions the UI prevents but the API allows; acting on objects in
  states that should forbid the action.
- **Time-of-use assumptions:** trusting a value computed earlier that the attacker can change before
  it's used.
**Why exploitable here:** describe the specific rule the app intends and the specific sequence that
breaks it. These findings are inherently project-specific. **Test in sandbox:** walk the workflow
with throwaway accounts and deliberately violate the intended order/values; confirm the forbidden
outcome (money moved, item granted, approval skipped). **Fix:** enforce invariants and authorization
server-side at each step; make sensitive operations idempotent with server-issued nonces; validate
all economic/state parameters server-side; verify state transitions against an explicit allowed set.

## Race conditions & TOCTOU (CWE-362/CWE-367)
**Look for:** check-then-act on shared, security-relevant state without atomicity — balance checks
before debits, "does it exist?" before create, one-time-token consume, quota/limit enforcement,
file check-then-open. **Why exploitable here:** identify the specific check and act that aren't
atomic and the state they guard. **Test in sandbox:** fire concurrent requests at the operation and
look for the invariant breaking (e.g. a coupon redeemed twice, balance going negative, two rows
where one should exist). **Fix:** make the operation atomic — DB transactions with appropriate
isolation/locking, atomic compare-and-set, unique constraints, or a single-consume primitive.
Verify by re-running the concurrent PoC and confirming the invariant now holds under contention.

## Denial of service / resource exhaustion (CWE-770/CWE-400)
**Look for (only where a realistic vector exists):** unbounded input sizes; expensive operations
reachable without limits (regex on user input → ReDoS, unbounded pagination, huge file processing,
zip/entity expansion bombs, N+1 amplification, deeply nested JSON/GraphQL); no rate limiting on
costly endpoints. **Test in sandbox:** submit oversized/pathological inputs and measure resource use
(kept within the sandbox); confirm a realistic request can degrade availability. Don't manufacture
unrealistic vectors — a DoS finding needs a plausible trigger. **Fix:** enforce input size/time/
recursion/complexity limits, safe (linear) regex or timeouts, pagination caps, streaming with
bounds, and rate limiting on expensive paths.

## Chaining note
Logic and race findings frequently combine with access-control findings (e.g. IDOR + race → mass
unauthorized state change). Attempt these in Stage 4e and confirm the sever point in Stage 6d.

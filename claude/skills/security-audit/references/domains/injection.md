# Domain: Injection

**Maps to:** OWASP A03:2021 Injection; CWE-89 (SQL), CWE-78 (OS command), CWE-90 (LDAP),
CWE-1336/CWE-94 (template/SSTI), CWE-93/CWE-113 (CRLF/header), CWE-943 (NoSQL).

The root pattern is always the same: untrusted input reaches an **interpreter** (a database, a
shell, a template engine, a directory service, an HTTP header serializer) as **code/structure**
rather than as inert data. The fix is always the same shape too: keep data as data —
parameterize, bind, or use a safe API — rather than escaping by hand.

## What to look for statically
- **SQL:** string concatenation or interpolation into query text; dynamic `ORDER BY`/`LIMIT`/table
  or column names (these can't be bound as parameters, so they need allow-lists); ORM "raw"/
  "expr"/`literal` escape hatches; stored-procedure calls built from input.
- **NoSQL:** query objects populated directly from request bodies (operator injection like
  `{"$gt": ""}` / `{"$where": ...}`); JSON that becomes a query without type/shape validation.
- **OS command:** shell invocations (`system`, `exec`, backticks, `sh -c`, `ProcessBuilder` with a
  shell) built from input; argument strings that aren't a fixed argv array.
- **LDAP:** filters built by concatenation without escaping per RFC 4515.
- **Template / SSTI:** user input rendered *as* a template (not passed as a value into a
  pre-compiled template) in engines that evaluate expressions.
- **CRLF / header / log:** input placed into response headers, redirect locations, email headers,
  or log lines without stripping `\r\n`.

## Why it's exploitable *here* (reason, don't assume)
Confirm the input is actually attacker-controlled and reaches the interpreter unescaped on a
reachable path, and that the framework isn't already neutralizing it. An ORM that always
parameterizes is safe until someone uses its raw escape hatch — find that specific call. Note the
required precondition (auth level, feature flag) for the ledger.

## How to test in the sandbox (Stage 4)
- **SQL/NoSQL:** against seeded synthetic data, send inputs that change query semantics (boolean/
  error/time-based for SQL; operator objects for NoSQL) and observe altered results, errors, or
  timing. Confirm impact (auth bypass, data disclosure, write) — a reflected error alone is weak
  evidence; a returned row that shouldn't be returned is strong.
- **Command:** supply an argument that would run a benign, observable side effect *inside the
  sandbox* (e.g. write a marker file in a temp dir, or a controlled delay) to prove execution
  without doing anything destructive.
- **SSTI:** submit a template expression whose evaluation is observable (a simple arithmetic
  expression rendering its result) to distinguish evaluation from literal echo.
- **CRLF:** attempt header/redirect splitting and observe whether an injected header/line appears.
- Then **fuzz** the parameter (see technique catalog) for unhandled states.

## Root-cause fixes (Stage 6 direction)
- **Parameterize / bind** every query; for identifiers that can't be bound, use a strict allow-list
  mapping input → known-safe column/table names.
- **NoSQL:** validate types and shapes; reject operator keys where scalars are expected; use query
  builders that separate operators from user data.
- **Command:** avoid the shell — use argv-array APIs with a fixed executable and validated args;
  better, replace shelling-out with a library call.
- **SSTI:** never compile user input as a template; pass it as data into a fixed template.
- **CRLF/headers:** use framework APIs that encode header values; strip control characters.
- Then verify with the **whole-family** tests and the **bypass battery** (re-encoding, alternate
  context, second entrance to the same sink) from Stage 6 — hand-rolled escaping is exactly what
  those bypass tests are designed to catch.

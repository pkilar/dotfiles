# Domain: Deserialization, XXE, Path Traversal, File Upload & Mass Assignment

**Maps to:** OWASP A08:2021 Software & Data Integrity Failures; CWE-502 (insecure
deserialization), CWE-611 (XXE), CWE-22/CWE-23 (path traversal / LFI), CWE-434 (unrestricted file
upload), CWE-915/CWE-​1321 (mass assignment / prototype pollution).

The shared theme: structured or external data is trusted to define objects, entities, or file
locations that the attacker can steer.

## Insecure deserialization (CWE-502)
**Look for:** deserializing untrusted bytes with formats/modes that can instantiate arbitrary types
or invoke callbacks (native object serialization, unsafe YAML loaders, pickle, and similar);
gadget-chain-prone libraries fed request/queue/cookie data. **Why exploitable here:** confirm the
bytes are attacker-controlled and the deserializer can construct dangerous types on a reachable
path. **Test in sandbox:** feed crafted serialized payloads and observe type instantiation or side
effects (kept benign and in-sandbox); **fuzz** the deserializer for crashes/unhandled states.
**Fix:** don't deserialize untrusted data into arbitrary types — use data-only formats (JSON) with
explicit schemas, safe/"safe_load" modes, allow-listed types, and integrity checks (signed
payloads) where the data must round-trip.

## XXE (CWE-611)
**Look for:** XML parsers with external-entity/DTD resolution enabled processing input (uploads,
SOAP, SVG, config, document formats). **Test in sandbox:** submit XML with an external entity that
resolves to a mocked in-sandbox resource or triggers an observable parser action; try billion-laughs
for DoS. **Fix:** disable external entities and DTDs; prefer non-XML formats where possible.

## Path traversal / LFI (CWE-22)
**Look for:** file paths built from input for read/write/include/download/template loading;
insufficient normalization; archive extraction without path checks ("zip slip"). **Why exploitable
here:** confirm input reaches a filesystem operation and can escape the intended directory.
**Test in sandbox:** `../` sequences, absolute paths, encoded/double-encoded and Unicode variants,
null bytes, and — for archives — entries with traversal paths, against a seeded synthetic file tree.
**Fix:** resolve to a canonical path and verify it stays within an allowed base dir; use safe
join/allow-list of filenames; validate archive entry paths before extraction. Canonicalization
edge cases are exactly what the Stage 6 bypass battery must re-test.

## Malicious file upload (CWE-434)
**Look for:** uploads stored in web-servable/executable locations; type trusted from
extension/`Content-Type`; no size limit; original filename used on disk. **Test in sandbox:** upload
files with dangerous extensions/content-type mismatches/polyglots/oversized payloads and see how
they're stored and served. **Fix:** validate real content type, store outside the web root with
generated names, serve with correct non-executable content-disposition, and enforce size limits.

## Mass assignment / over-posting & prototype pollution (CWE-915/CWE-1321)
**Look for:** binding request bodies straight onto models/ORM entities so a client can set fields
it shouldn't (`role`, `is_admin`, `owner_id`, `balance`); deep merges of user JSON into objects
(prototype/`__proto__`/`constructor` pollution). **Test in sandbox:** POST extra/privileged fields
and polluting keys; confirm they take effect. **Fix:** explicit allow-lists of bindable fields
(DTOs), never bind sensitive fields from input, and guard object merges against special keys.

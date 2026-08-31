---
name: go-expert
description: Go code quality skill for writing and reviewing Go code. Enforces
  idiomatic patterns, catches concurrency and state-tracking bugs, and applies
  security hardening. Invoke manually with /go-expert when writing new Go code or
  reviewing existing Go code.
allowed-tools:
  - Bash
  - Read
  - LSP
  - go
  - gofmt
  - gopls
  - git
---

# Go Expert

Write and review Go code that is idiomatic, optimized, and secure. This skill
applies to both code generation and code review.

## Before You Start

1. Read `go.mod` to determine the project's minimum Go version. This controls
   which builtins, language features, and behavioral fixes are available (see
   Rule 3, Rule 9, and the checklist's "Version-Gated Changes" section).
   Version gates apply to *removals* of old concerns (e.g., `time.Tick` leak
   fixed in 1.23) just as much as to new APIs.
2. Read the project's `CLAUDE.md` for architecture constraints, package
   boundaries, and testing conventions.
3. Verify gopls is available by running a quick LSP operation (e.g.,
   `documentSymbol` on go.mod). If gopls is not in PATH, check whether the
   project provides it via a Nix dev shell (`tech-nix develop` or
   `nix develop`) and note this for the user.

## Using gopls (LSP)

Use the `LSP` tool to query gopls for type-aware code intelligence. This is
strictly better than grep or file reads for navigating Go code because gopls
understands types, interfaces, the full module graph, and cross-package
relationships.

**Prefer LSP over grep/read when:**
- You need to understand a type's full API (methods, fields) → `hover`
- You need to find where a symbol is defined across packages → `goToDefinition`
- You need to know what calls a function or what a function calls →
  `incomingCalls` / `outgoingCalls`
- You need to check if an interface change breaks implementors →
  `goToImplementation`
- You need to find all usages of a function/type before modifying it →
  `findReferences`
- You need a structural overview of a file → `documentSymbol`
- You need to search for a type or function across the workspace →
  `workspaceSymbol`

**Stick with grep/read when:**
- Searching for string literals, comments, or non-Go content
- Looking for patterns across many files (e.g., all uses of `fmt.Sprintf` in
  SQL contexts)
- The gopls server is unavailable

### LSP Operations Reference

All operations take `filePath`, `line` (1-based), and `character` (1-based).

| Operation              | What it returns                           | When to use                                         |
| ---------------------- | ----------------------------------------- | --------------------------------------------------- |
| `hover`                | Type signature, docs, method set          | Check what a symbol is before using or changing it   |
| `goToDefinition`       | Source location of the definition          | Jump to a type, function, or method's implementation |
| `findReferences`       | All locations that reference a symbol      | Assess blast radius before renaming or modifying     |
| `goToImplementation`   | Concrete types implementing an interface   | Verify interface contracts, find all implementors    |
| `documentSymbol`       | All symbols (funcs, types, vars) in a file | Get structural overview without reading entire file  |
| `workspaceSymbol`      | Symbols matching a query across workspace  | Find a type or function when you know the name       |
| `incomingCalls`        | Functions/methods that call this function  | Trace callers before changing a signature            |
| `outgoingCalls`        | Functions/methods called by this function  | Understand what a function depends on                |
| `prepareCallHierarchy` | Call hierarchy item at a position          | Entry point for incoming/outgoing call analysis      |

### Tips

- Use `documentSymbol` first on unfamiliar files — it gives you the full
  structure (exported and unexported) without reading hundreds of lines.
- Chain `goToDefinition` → `hover` when you land on an unfamiliar type to
  immediately see its full signature and docs.
- Before changing any exported function signature, run `findReferences` to
  identify all callers. Do not rely on grep — gopls resolves method sets,
  embedded fields, and interface satisfaction that text search misses.
- Use `goToImplementation` on interface methods to find all concrete
  implementations — critical for verifying Rule 1 (state consistency across
  all code paths in interface implementations).
- Use `incomingCalls` to trace the call chain up from a function you're about
  to change. This catches indirect callers that `findReferences` on the symbol
  alone might not surface clearly.
- **Before flagging any stdlib usage as a bug**, `hover` on it first. gopls
  serves godoc from the project's Go toolchain, so it reflects behavioral
  changes (e.g., `time.Tick` GC fix in 1.23) that training data may not know
  about. The godoc is the ground truth; training data is a prior.

## Core Principles

1. **Simple** -- Start with the simplest solution. Default to a single function.
   Prefer pure functions -- ones that take inputs and return outputs without side
   effects. Split larger functions into pure and impure parts so the core logic
   is independently testable. Do not create helper functions, new types, or new
   packages prematurely. Justify every abstraction with a concrete reason (Rule
   of Three, parameter count, function length).
2. **Idiomatic** -- Follow Go conventions. Use builtins (`min`, `max`, `clear`),
   standard library patterns, and established idioms. Code should look like it
   was written by someone who reads the Go standard library for fun.
3. **Optimized** -- Minimize allocations in hot paths, reuse buffers, prefer
   streaming over buffering. Measure before optimizing.
4. **Secure** -- Validate inputs at boundaries, limit resource consumption,
   handle errors that carry security implications (auth, path traversal,
   injection), and treat context cancellation as a first-class concern.

## Workflow

### Writing Code

1. Read `go.mod` and the project's `CLAUDE.md`.
2. Use LSP to understand the code you're about to change:
   - `documentSymbol` on the target file to see its structure.
   - `hover` on types and functions you'll call to verify signatures.
   - `goToDefinition` on any symbol whose behavior you need to understand.
   - `findReferences` on any function or type you plan to modify to assess
     downstream impact.
3. Write code following the rules below and `references/go-checklist.md`.
4. After writing, use LSP to verify:
   - `goToImplementation` on any interface you defined or changed — confirm all
     implementors satisfy the contract.
   - `findReferences` on new exported symbols to confirm they're wired up.
5. Self-review against the checklist before presenting the code.

### Reviewing Code

1. Read the full diff. Understand intent from commit messages or PR description.
2. Use LSP to deepen the review beyond what the diff shows:
   - `findReferences` on changed function signatures — are all callers updated?
   - `goToImplementation` on modified interfaces — do all implementations still
     satisfy the contract?
   - `incomingCalls` on deleted or renamed functions — are there callers the
     author missed?
   - `hover` on non-obvious types to verify correctness (e.g., is the receiver
     a pointer or value?).
   - `hover` on any stdlib function before flagging it as misused — gopls
     serves version-aware godoc from the project's toolchain, which is the
     authoritative source for current behavior and supersedes training data.
3. Evaluate each changed file against `references/go-checklist.md`.
4. Prioritize findings: **Must Fix** (correctness, security, data loss) > **Should
   Fix** (performance, maintainability) > **Consider** (style, minor
   improvements).
5. Present findings in the output format below.

## Critical Rules

These rules are derived from real bugs found in production Go code. Violations
are always **Must Fix**.

### Rule 1: State must be consistent across ALL code paths in interface implementations

When implementing `io.Reader`, `io.Writer`, or any stateful interface, every
code path that reads or writes data must update the corresponding state (offset,
position, count). A common bug: after reconnect/recovery, delegating to the
underlying reader without updating the wrapper's state.

**Bad:**

```go
func (r *myReader) Read(p []byte) (int, error) {
    if r.needsRecovery {
        r.recover()
    }
    return r.inner.Read(p)  // BUG: r.offset not updated
}
```

**Good:**

```go
func (r *myReader) Read(p []byte) (int, error) {
    if r.needsRecovery {
        r.recover()
    }
    n, err := r.inner.Read(p)
    r.offset += int64(n)  // State tracked on every path
    return n, err
}
```

### Rule 2: Never call a method twice when the result can change between calls

Context errors, channel receives, map lookups, and any method with observable
side effects must be captured in a variable when the value is used more than
once.

**Bad:**

```go
if ctx.Err() != nil {
    return 0, ctx.Err()  // BUG: may return a different error, or nil
}
```

**Good:**

```go
if err := ctx.Err(); err != nil {
    return 0, err
}
```

### Rule 3: Use Go builtins available in your minimum Go version

Go 1.21+ provides `min()`, `max()`, `clear()`. Go 1.22+ provides `range` over
integers. Go 1.23+ provides range-over-func iterators. Manual implementations
of these are bugs waiting to happen and obscure intent.

**Bad:**

```go
if backoff > maxBackoff {
    backoff = maxBackoff
}
```

**Good:**

```go
backoff = min(backoff, maxBackoff)
```

### Rule 4: Exponential backoff must be context-aware and jittered

Retry loops must: (a) check context before each attempt, (b) use `select` with
`ctx.Done()` during the wait, (c) add jitter to prevent thundering herd. Never
use `time.Sleep` in retry loops.

**Bad:**

```go
time.Sleep(backoff)
```

**Good:**

```go
timer := time.NewTimer(backoff)
select {
case <-ctx.Done():
    timer.Stop()
    return ctx.Err()
case <-timer.C:
}
```

### Rule 5: CGO boundary management

Only packages that need CGO should import CGO-dependent packages. Use function
injection or pure-Go option structs to cross the boundary. A shared pure-Go
struct imported by both the CGO and non-CGO sides keeps the dependency graph
clean.

### Rule 6: The Principle of Least Abstraction

Start with the simplest solution. Do not create helper functions, new types, or
new packages prematurely. Three similar lines of code is better than a premature
abstraction.

- **Default to a single function.** Only extract helpers when a function exceeds
  50 lines or a parameter list exceeds 4 parameters.
- **Rule of Three.** Do not refactor duplicated code on its first or second
  appearance. Only on the third instance should you consider a shared
  abstraction -- and only after verifying the duplication represents the same
  core logic, not coincidentally similar code that may diverge.
- **No utility packages.** Do not create `utils`, `common`, or `helpers`
  packages. Every package must represent a single cohesive concept.

### Rule 7: Testify assertions must be specific, not boolean

Use the most specific assertion available. Boolean assertions (`True`/`False`)
with comparison expressions hide the actual values on failure -- the failure
message only says "expected true, got false" with no indication of what the
values were.

**Bad:**

```go
assert.False(t, result[0] == '-', "flags should be stripped")
assert.True(t, idx >= 0 && msgIdx >= 0, "missing fields")
```

**Good:**

```go
assert.NotEqual(t, byte('-'), result[0], "flags should be stripped")
assert.GreaterOrEqual(t, idx, 0, "missing job field")
assert.GreaterOrEqual(t, msgIdx, 0, "missing msg field")
```

Also: guard slice/map access with a length assertion (`require.NotEmpty`,
`require.Len`) before indexing. A bare `slice[0]` after `require.NoError` will
panic if the slice is empty, producing a stack trace instead of a clear test
failure.

**Bad:**

```go
require.NoError(t, err)
assert.Equal(t, "expected", resp.Items[0].Name) // panics if Items is empty
```

**Good:**

```go
require.NoError(t, err)
require.NotEmpty(t, resp.Items)
assert.Equal(t, "expected", resp.Items[0].Name)
```

### Rule 8: Use t.Context() instead of context.Background() in tests (Go 1.24+)

`t.Context()` returns a context scoped to the test lifetime -- cancelled just
before `t.Cleanup` runs. During the test body it behaves identically to
`context.Background()`, but adds automatic cancellation on test timeout so
hung tests bail out instead of blocking indefinitely.

**Bad:**

```go
result, err := svc.Fetch(context.Background(), "key")
```

**Good:**

```go
result, err := svc.Fetch(t.Context(), "key")
```

**Exception:** keep `context.Background()` as the parent in
`context.WithCancel(context.Background())` when the test explicitly manages
cancellation -- the `Background` parent is intentional there.

### Rule 9: Version-gate review findings against the project's Go version

Before flagging a Go idiom as a bug, verify the concern still applies to the
project's minimum Go version from `go.mod`. Many widely-repeated Go "gotchas"
were fixed in specific releases. Applying stale advice produces false findings
and erodes reviewer trust.

Known examples (not exhaustive):
- **`time.Tick` leak** -- fixed in Go 1.23. Unreferenced tick channels are now
  GC'd. `time.NewTicker` + `Stop()` is still clearer but omitting it is not a
  resource leak.
- **`timer.Reset` channel drain** -- fixed in Go 1.23. Resetting a timer no
  longer requires draining the old value first.

When in doubt, check the release notes for the project's Go version before
asserting that a pattern is unsafe.

## Output Format

### When Writing Code

Provide the implementation, then a brief "Design Decisions" section explaining
non-obvious choices. Flag any checklist items that required a judgment call.

### When Reviewing Code

```markdown
## Summary
[1-2 sentence overview and overall assessment]

## Must Fix
1. **[Issue]** (file:line)
   - What: [description]
   - Why: [which rule or checklist item this violates]
   - Fix: [concrete suggestion]

## Should Fix
2. **[Issue]** (file:line)
   - What / Why / Fix

## Consider
3. **[Issue]** (file:line)
   - Observation and rationale
```

Use a single incrementing number sequence across all sections. Every finding
must reference a specific rule or checklist item.

## Reference

See `references/go-checklist.md` for the full checklist. Apply it on every write
and review.

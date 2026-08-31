# Go Code Quality Checklist

Apply this checklist when writing or reviewing Go code. Every item prevents a
real class of bug or produces measurably better code. Items marked **(Critical)**
correspond to bugs previously found in production Go code. Check `go.mod` for
the project's minimum Go version before applying version-gated items.

## Function and Abstraction Design

- [ ] Functions do one thing -- describable in one sentence
- [ ] Functions do not exceed 50 lines; extract private helpers in the same file
      when they do
- [ ] Functions have at most 4 parameters; group related parameters into a
      struct when more are needed
- [ ] Functions return 1-2 values directly; use a named struct for 3+ related
      return values
- [ ] Duplicated code is not refactored until the third instance (Rule of Three)
- [ ] Before deduplicating, confirm the instances represent the same core logic
      and not coincidentally similar code that may diverge independently
- [ ] Pure functions preferred where possible -- take inputs, return outputs, no
      side effects; easier to test and reason about
- [ ] Larger functions that mix pure logic with side effects (I/O, state
      mutation) are split so the pure logic is independently testable
- [ ] Every abstraction (new function, type, or package) has a concrete
      justification -- if there is no strong reason to abstract, don't
- [ ] Use package-level conversion helpers consistently. If the package
      already has a helper like `strVal(v any) string` or `formatX(v T)
      string`, do not interleave it with inline `fmt.Sprintf("%v", v)` /
      `strconv.X` calls that do the same job. Pick the helper and use it
      everywhere. Inconsistency makes future retrofits (typed fast paths,
      string interning, allocation reduction) impossible without touching
      every call site, and `fmt.Sprintf("%v", ...)` is measurably slower
      than a typed helper for the common string case
- [ ] Don't store derived state on a struct. A field whose value is a
      function of other fields (e.g., `Total int = len(Shell)+len(Other)`)
      drifts the moment any consumer mutates the underlying state. Compute
      it via a method instead -- `func (s SubReport) Total() int { return
      len(s.Shell) + len(s.Other) }`. Go templates call zero-arg methods
      identically to fields (`{{.Total}}`), so this is a free swap.
      Caches are the exception, but only when the recompute cost is
      genuinely high; otherwise prefer methods that read from the source
      of truth
- [ ] When a JSON shape is fixed, declare it once via struct tags, not via
      a hand-built `map[string]any` literal. A literal like
      `map[string]any{"Submit User": e.SubmitUser, ...}` duplicates every
      field name, drifts from the type definition under refactor, and
      forces consumer-side type assertions on `any`. With tags
      (`SubmitUser string \`json:"Submit User"\``), `json.Marshal` produces
      the same wire format and the producer code becomes one line:
      `return s.Entries`. Same applies to YAML, BSON, etc.
- [ ] Comments describe *current* behavior, not history. Never write "Replaces
      X" / "This used to do Y" / "Before the refactor..." -- those references
      go stale the moment the PR merges. Put migration context in the commit
      message or PR description, not the code
- [ ] Comments do not reference files, types, or fields that are being deleted
      in the same change. Check for references to removed code before committing
- [ ] Taking the address of a struct field uses `&s.Field` directly, not an
      intermediate local (`x := s.Field; &x`). For Go 1.26+: `new(expr)` works
      for literals, so `new("hi")` replaces `func strPtr(s string) *string`

## Package Design

- [ ] Each package represents a single cohesive concept (e.g., `http`, `user`,
      `auth`) -- no `utils`, `common`, or `helpers` packages
- [ ] Inside a package, separate data collection, transformation, and
      presentation. A type that owns raw data, transforms it into a derived
      shape, AND renders that shape to HTML/JSON has three reasons to change.
      Split it: a collector acquires data, a restructure step produces a
      typed intermediate, and a renderer consumes the intermediate. The
      renderer must not reach back into the collector. This makes each layer
      independently testable and lets one renderer (e.g., HTML) be added
      without disturbing another (e.g., JSON)
- [ ] For HTML output, prefer `html/template` over `strings.Builder` +
      `html.EscapeString`. Contextual escaping (attribute vs. text vs. URL
      vs. JS) is correct by default in `html/template` and easy to misuse
      with manual escaping. Hand-built HTML is also harder for a security
      reviewer to audit -- a single missed `EscapeString` is a stored XSS
- [ ] No global state -- prefer constructing objects/interfaces that can be
      dependency-injected; package-level `var` is limited to sentinel errors and
      constants
- [ ] Public API surface is intentional -- exported identifiers exist because a
      consumer needs them, not by accident; unexported by default
- [ ] In `main` packages, create clean internal API boundaries between files --
      treat internal structure like a small private package graph even without
      separate packages
- [ ] Related types and functions live together in the same package
- [ ] Internal packages used to restrict visibility where appropriate

## io.Reader / io.Writer Implementations

- [ ] **(Critical)** Every code path that reads/writes data updates the
      wrapper's state (offset, count, position) -- including post-reconnect,
      post-recovery, and error paths
- [ ] `Read` returns `n > 0` with a non-nil error when partial data was consumed
      (per `io.Reader` contract)
- [ ] `Read` never returns `n > 0, io.EOF` unless the data source is genuinely
      exhausted (callers depend on this)
- [ ] `Close` closes the underlying resource even when the wrapper is in an
      error state
- [ ] Composed readers (e.g., decompressor wrapping a resumable reader wrapping
      a network body) close all layers on `Close`

## Context Handling

- [ ] **(Critical)** `ctx.Err()` is captured in a variable before branching on
      it -- never called twice in an if-return pattern
- [ ] Long-running loops check `ctx.Err()` or `select` on `ctx.Done()` at each
      iteration
- [ ] Context is the first parameter and named `ctx`
- [ ] Background work uses `context.WithCancel` or `context.WithTimeout`, never
      bare `context.Background()` in production paths
- [ ] Context cancellation is propagated to child goroutines

## Version-Gated Changes (check `go.mod` before flagging)

Before flagging a Go idiom as a bug, verify the concern is still valid for the
project's minimum Go version. Many historical Go "gotchas" were fixed in
specific releases. Applying stale advice produces false findings.

### New APIs and Builtins

- [ ] **(Critical)** `min()` / `max()` used instead of manual if-then-cap
      patterns (Go 1.21+)
- [ ] `clear()` used to zero maps and slices instead of manual loops (Go 1.21+)
- [ ] `range N` used for counting loops (Go 1.22+)
- [ ] `slices`, `maps` stdlib packages used instead of hand-rolled equivalents
      (Go 1.21+)
- [ ] `slices.Concat(a, b, c)` used to join three or more slices, not chained
      `append(append(a, b...), c...)` (Go 1.22+). Concat allocates the right
      capacity once; chained `append` may reallocate twice depending on
      cap(a)
- [ ] `errors.Join` used to combine multiple close/cleanup errors (Go 1.20+)

### Behavioral Fixes (things that stopped being bugs)

- [ ] **(Critical)** `time.Tick` is safe when the channel becomes unreachable
      (Go 1.23+). Before 1.23 the internal ticker was never GC'd; since 1.23
      timers and tickers that are no longer referenced are collected immediately
      even without `Stop()`. `time.NewTicker` + `Stop()` is still clearer for
      explicit lifecycle control but omitting it is not a leak on 1.23+. Do NOT
      flag `time.Tick` as a resource leak in projects targeting Go 1.23+.
- [ ] `timer.Reset` is safe to call without draining the channel first
      (Go 1.23+). Before 1.23 the old behavior could cause spurious fires.

## Retry and Backoff

- [ ] **(Critical)** Wait uses `select` with `ctx.Done()` and a timer -- never
      `time.Sleep`
- [ ] Backoff is exponential with a cap: `min(base * 2^attempt, maxBackoff)`
- [ ] Jitter added to prevent thundering herd (typically 25% of backoff)
- [ ] Context checked before each attempt (not just during the wait)
- [ ] Last error is wrapped in the "max retries exceeded" sentinel
- [ ] Retry is only attempted for transient/retryable errors; permanent errors
      fail immediately

## Error Handling

- [ ] Errors are wrapped with `fmt.Errorf("context: %w", err)` to preserve the
      chain
- [ ] `errors.Is` / `errors.As` used for error matching -- never string
      comparison
- [ ] Sentinel errors are package-level `var` values, not created inline
- [ ] Resource cleanup happens in `defer` even when the function returns an
      error
- [ ] Cleanup errors are combined with the primary error using `errors.Join` or
      checked after the primary
- [ ] Error messages start lowercase and do not end with punctuation (per Go
      convention)
- [ ] Type switches and if/else chains on external input have explicit
      `default`/`else` cases that return errors -- silent fallthrough in
      security-critical paths (SQL building, auth, input parsing) is a bug
- [ ] Boolean-returning functions that perform I/O (DB queries, network calls)
      distinguish "not found" from real errors -- at minimum log real errors
      rather than silently returning false for all failure modes
- [ ] Numeric-returning functions return an error when the value is unknown
      rather than a zero that callers can't distinguish from a legitimate zero.
      `func Size() (int64, error)` returning `(0, nil)` for "unknown size" is
      indistinguishable from "empty" at the call site -- return an error
      instead
- [ ] **(Critical)** A "validation failed" branch in a security-critical
      function must not return the same value as "no constraint." Returning
      an empty `map[string]string` from an authz-filter builder on malformed
      input means the next caller applies no filter at all -- the worst
      possible default. Either fail closed with a deny-all sentinel, return
      an error, or (preferably) restructure so the parse-and-validate step
      doesn't exist -- carry the data in the right shape from construction
      so there is no malformed-input branch to mishandle

## HTTP Security

- [ ] `http.MaxBytesReader` wraps request bodies before decoding
- [ ] Security headers set: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`
- [ ] Validation order: cheap checks (syntax, required fields) before expensive
      checks (network I/O, database)
- [ ] Path parameters validated against injection (no `../`, no absolute paths
      in user input)
- [ ] Tar/zip extraction skips symlinks and rejects paths containing `..` or
      absolute paths
- [ ] Panic recovery middleware returns 500 without leaking stack traces to
      clients
- [ ] Panic recovery checks `wroteHeader` before writing a second status code
- [ ] HTTP status codes use `net/http` constants (`http.StatusUnauthorized`,
      `http.StatusNotFound`, etc.) -- never raw integer literals like `401`

## Concurrency

- [ ] Design choice between channels (message passing) and shared state (mutex)
      is deliberate -- channels are easier to reason about but carry allocation
      and scheduling overhead; prefer channels for coordination between
      goroutines, mutexes for protecting simple shared data
- [ ] Every goroutine has a clear owner and termination path (context
      cancellation, channel close, or WaitGroup)
- [ ] `sync.WaitGroup.Add` called before `go func()`, never inside the
      goroutine
- [ ] Channels are typed for their purpose: signaling (`chan struct{}`), data
      (`chan T`), done (`chan error`)
- [ ] Non-blocking sends use `select` with `default` to avoid goroutine leaks
- [ ] Shared mutable state protected by `sync.Mutex` with lock scope minimized
      (no I/O under lock)
- [ ] Mutex and its protected fields are visually grouped in the struct
      definition -- separated from unprotected fields by blank lines, with a
      comment stating what the lock covers. Readers should never have to guess
      which fields require the lock
- [ ] `atomic` types used only for fields genuinely accessed outside the lock
      (e.g., fast-path checks before `TryLock`). Fields accessed exclusively
      under a mutex should be plain types, not atomics -- unnecessary atomics
      obscure the actual synchronization contract
- [ ] Worker goroutines recover from panics to prevent pool starvation

## Interface Design

- [ ] Interfaces defined at the consumer site, not the implementation site
- [ ] Interfaces named after the concept, never suffixed with `Iface` or
      `Interface` -- e.g., `Pool` not `PoolIface`, `Store` not `StoreInterface`
- [ ] Interfaces are small -- ideally 1 method, prefer 3 or fewer; more than 3
      is a yellow flag that the interface may be too broad (treat as red when
      generating code -- LLMs tend to over-abstract)
- [ ] Concrete types returned from constructors; interfaces accepted as
      parameters
- [ ] No interface pollution: if only one implementation exists and testability
      is not needed, use the concrete type
- [ ] Type assertions use the comma-ok pattern
- [ ] Resource-owning types expose a `Close()` method rather than returning a
      cleanup function from the constructor -- follows the `io.Closer` contract
      and makes lifecycle management explicit at the call site (`defer x.Close()`
      vs. an anonymous `cleanup` func that obscures what it closes)
- [ ] Compile-time interface satisfaction checks (`var _ I = (*T)(nil)`) live
      at package level, not inside a `TestFoo()` function. The assertion fires
      at compile time regardless of whether tests run, so wrapping it in a test
      function is dead code
- [ ] No parallel constructors for prod and test. When you reach for a
      `NewWithDeps` / `NewForTest` constructor alongside a production
      `New`, you've created two code paths that drift -- the test version
      diverges from the production wiring as the dependency graph grows.
      Refactor to one constructor `New(opts Opts) *T` that takes an
      options struct, plus a factory `NewWithDefaults() (*T, error)` that
      reads the environment and builds the production opts. Tests
      construct opts directly; prod calls the factory. One construction
      path, no test-only API surface
- [ ] Document ownership transfer plainly. When a constructor takes a
      dependency that its destructor will Close (e.g., `New(opts Opts)`
      where `T.Close()` calls `opts.DB.Close()`), say so in the
      constructor's godoc: passing this dependency transfers ownership to
      T. Conversely, if callers retain ownership, the destructor must not
      touch it. A doc that claims "caller owns" while the destructor
      closes the dependency is the bug -- prefer the smaller fix of
      telling the truth over restructuring to match an idiom, especially
      when the underlying Close is idempotent and the cost of an
      ownership flag exceeds the benefit

## Structured Logging (slog)

- [ ] Request-scoped or operation-scoped loggers created with
      `logger.With("key", id)` and propagated to callees
- [ ] Log levels are appropriate: `Error` for failures needing attention, `Warn`
      for recoverable issues, `Info` for state transitions, `Debug` for
      diagnostics
- [ ] Structured key-value pairs used -- no `fmt.Sprintf` in log messages
- [ ] Sensitive data (API keys, passwords, tokens) never logged
- [ ] Duration values logged with `time.Since(start).Round(time.Millisecond)`

## CGO Boundary Management

- [ ] CGO-dependent packages are never imported by pure-Go packages
- [ ] Cross-boundary communication uses pure-Go types (function injection,
      shared option structs)
- [ ] C resources freed in deterministic order in `Close()` / cleanup functions
- [ ] `defer` used for `C.free` of strings passed to C
- [ ] Pinned Go pointers follow CGO pointer-passing rules

## Test Patterns

- [ ] Table-driven tests with descriptive `name` field for subtests
- [ ] Test helpers use `t.Helper()` for correct line-number reporting
- [ ] Mock interfaces are minimal (only the methods the test exercises)
- [ ] `t.TempDir()` for temp files (auto-cleaned)
- [ ] `t.Cleanup()` for resource teardown instead of manual defers that might be
      skipped
- [ ] `t.Context()` used instead of `context.Background()` for context
      arguments (Go 1.24+) -- gives automatic cancellation on test timeout.
      Exception: keep `context.Background()` as the parent for
      `context.WithCancel` when the test explicitly manages cancellation
- [ ] Tests verify behavior, not implementation details
- [ ] No tautological tests. `assert.Equal(t, 0x1f, Constant[0])` where
      `Constant = [...]byte{0x1f, 0x8b}` has no failure mode — both sides
      trace back to the same source. Test the constant by exercising the
      function that uses it (e.g., "gzip'd data starts with these bytes"),
      not by asserting the constant equals its own literal
- [ ] Edge cases tested: empty input, zero values, context cancellation,
      concurrent access
- [ ] Fast backoff values injected for retry tests (e.g.,
      `r.minBackoff = time.Millisecond`)
- [ ] When a constructor or top-level function requires real infrastructure (OS
      files, network services, credentials), extract its pure helpers and test
      them independently -- the helpers are often where the logic bugs live

## Testify Assertions

- [ ] **(Critical)** Specific assertions used over boolean -- `NotEqual`,
      `GreaterOrEqual`, `Contains` instead of `True(x != y)`, `True(x >= y)`,
      `True(strings.Contains(...))`; boolean assertions hide actual values on
      failure
- [ ] **(Critical)** Slice/map access guarded with `require.NotEmpty` or
      `require.Len` before indexing -- bare `slice[0]` after `require.NoError`
      panics if the slice is empty, producing a stack trace instead of a clear
      failure
- [ ] Slice/byte comparisons done as a whole (`assert.Equal(t, expected,
      got[:4])`) rather than element-by-element
- [ ] `assert.Contains` used directly on interface/`any` types -- no type
      assertion or manual cast needed before checking membership. Use
      `assert.IsType` for explicit type checks when needed separately
- [ ] `assert.ElementsMatch` used for order-independent slice comparison --
      never sort + `assert.Equal`. Similarly, do not sort before
      `assert.Contains` (Contains is already order-independent)
- [ ] Manual loops searching for elements replaced with `assert.Contains` --
      if you're writing `for _, x := range slice { if x == target { found = true } }`,
      use `assert.Contains(t, slice, target)` instead
- [ ] `require.NoError(t, fn())` used when the error variable is not reused --
      no intermediate `err :=` variable for a single check
- [ ] Stdlib functions used in test helpers (`maps.Values`, `slices.Collect`)
      instead of hand-rolled equivalents

## Performance

- [ ] Buffers reused via `sync.Pool` or pre-allocated slices in hot paths
- [ ] `strings.Builder` used for string concatenation in loops (not `+`)
- [ ] `strings.Replacer` used for multiple unconditional substitutions on a
      string. Build a package-level Replacer once and call its `Replace`
      method -- single-pass scan, one allocation, and the output is never
      re-encoded by a later substitution (chained `strings.ReplaceAll`
      calls scan and allocate N times AND can re-encode their own output).
      Use chained `ReplaceAll` only when replacements are conditional or
      order-dependent in ways `Replacer` cannot express
- [ ] Result slices built in a loop use `make([]T, 0, cap)` when the upper
      bound is known -- e.g., paginated DB queries know the cap from LIMIT and
      COUNT. Avoids repeated reallocation as append grows the slice. Cap hint
      can be `min(limit, total-offset)` for short final pages
- [ ] `io.Copy` / `io.ReadAll` used instead of manual read loops where
      appropriate
- [ ] `bufio.Scanner` or `bufio.Reader` used for line-by-line file processing
- [ ] HTTP clients reused (not created per request); transport configured once
- [ ] `[]byte` / `string` conversions minimized -- work in whichever type the
      data arrives as; avoid round-tripping between `[]byte` and `string` in hot
      paths
- [ ] Connection pools sized appropriately for the workload
- [ ] `runtime.NumCPU()` used as upper bound for worker pools, with a
      configurable cap

## Cloud / Network Streaming Patterns

- [ ] ETag or version ID verified on reconnect to detect object replacement
      during streaming
- [ ] Range headers used correctly for resumable reads (`bytes=offset-`)
- [ ] Network errors classified as transient vs permanent before retry
- [ ] Context errors (`context.Canceled`, `context.DeadlineExceeded`) are never
      treated as transient

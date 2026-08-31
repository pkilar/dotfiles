# Rust Code Quality Checklist

Apply this checklist when writing or reviewing Rust code. Every item prevents a
real class of bug or produces measurably better code. Items marked **(Critical)**
correspond to bugs previously found in production Rust code. Check `Cargo.toml`
for the project's Rust edition and MSRV before applying edition-gated items.

## Error Handling

- [ ] **(Critical)** Results are never silently discarded with `let _ =` in
      production code -- errors are logged, propagated, or explicitly handled
- [ ] `?` operator used for propagation; manual `match` on `Result` only when
      the error arm needs non-trivial logic
- [ ] Errors wrapped with context: `map_err(|e| Error::Config(format!(...)))`
      or using `anyhow::Context` in application code
- [ ] `thiserror` used for library error types; `anyhow` only in application
      binaries
- [ ] Error messages start lowercase and do not end with punctuation (per Rust
      convention)
- [ ] Sentinel errors are enum variants, not string comparisons
- [ ] `unwrap()` and `expect()` never used in production code paths; only in
      tests or where the invariant is provably unreachable (with a comment
      explaining why)
- [ ] `Drop` implementations that can fail log the error rather than panicking
      or silently discarding it
- [ ] Cleanup errors combined with primary error when both matter (e.g.,
      file sync failure during write)

## File and Path Operations

- [ ] **(Critical)** Security-sensitive file loads use open-fstat-read on a
      single fd, not separate read + stat calls (TOCTOU)
- [ ] **(Critical)** Temporary files are cleaned up on all error paths between
      creation and atomic rename
- [ ] **(Critical)** User-controlled strings are validated before interpolation
      into filesystem paths -- reject `/`, `..`, empty strings, and non-ASCII
      characters in profile names, keys, or identifiers
- [ ] `umask` set before creating directories/files that need restrictive
      permissions (defense-in-depth against race between create and chmod)
- [ ] Atomic file writes use create-in-same-dir + rename pattern; never write
      directly to the target path
- [ ] `fsync` called on both file and parent directory after atomic rename for
      crash consistency
- [ ] `PathBuf::push` / `Path::join` used instead of string concatenation for
      path construction
- [ ] `canonicalize` used cautiously -- it resolves symlinks and requires the
      path to exist; prefer validating components when the path might not exist
      yet

## Unsafe Code

- [ ] **(Critical)** Every `unsafe` block has a `// SAFETY:` comment explaining
      why the invariants hold
- [ ] **(Critical)** `pre_exec` closures are async-signal-safe: no allocations,
      no locks, no panics, no `println!`, only direct syscalls with captured data
- [ ] Unsafe scope is minimized -- wrap the smallest possible expression, not
      entire functions
- [ ] Safe abstractions built around unsafe operations so callers don't need
      `unsafe`
- [ ] FFI types use `#[repr(C)]` and match the C layout exactly
- [ ] Raw pointers derived from valid references or allocations; lifetimes
      documented in the SAFETY comment
- [ ] `env::set_var` treated as unsafe (Rust 1.83+) with documented
      single-threaded invariant

## Type System

- [ ] **(Critical)** Enums used instead of `&mut bool` output parameters --
      self-documenting, exhaustively matched, can carry data
- [ ] Newtypes used for validated data (e.g., `ProfileName(String)` that
      enforces validation at construction)
- [ ] `Option<T>` used for nullable values; never sentinel values like `""`
      or `-1`
- [ ] `Result<T, E>` used for fallible operations; never return success with
      an error logged to the side
- [ ] Enums preferred over boolean parameters when the meaning is not obvious
      at the call site
- [ ] `#[non_exhaustive]` on public enums that may grow variants
- [ ] Struct fields are private by default; expose only through methods with
      validation

## Code Organization

- [ ] Types and structs defined before the functions that use them (types at
      top of module, impl blocks after)
- [ ] Public entry points (`pub fn`) placed after type definitions, before
      private impl blocks
- [ ] `#[cfg(test)] mod tests` is always the last item in the module -- no
      production code after it (clippy `items_after_test_module`)
- [ ] One `lib.rs` per library crate; re-exports via `pub use` keep the public
      API clean
- [ ] Related functionality grouped in modules; avoid single-file crates over
      ~500 lines
- [ ] Constants and sentinel values at the top of the file, after `use` statements

## Privilege and Capability Handling (Systems Code)

- [ ] **(Critical)** Errors during privilege operations (capability drop,
      setuid, setgid) are never silently swallowed -- an unexpected EPERM when
      dropping capabilities indicates a serious invariant violation
- [ ] Privilege drop sequence follows the correct order: keepcaps, setgroups,
      setgid, setuid (cannot be reversed once uid is non-root)
- [ ] `env_clear()` used on child processes that should not inherit the
      parent's environment
- [ ] `PR_SET_NO_NEW_PRIVS` set after privilege drop to prevent re-escalation
- [ ] Blacklist/denylist enforcement has redundant layers (mount overmounts +
      policy rejection) that stay in sync

## Validation and Consistency

- [ ] **(Critical)** Validation rules applied uniformly across similar profile
      types -- if exec profiles require absolute paths, validators and edit
      profiles do too
- [ ] **(Critical)** Don't re-read data already in scope -- if you have the
      bytes in a variable, compare against them directly instead of calling a
      function that reads the file again
- [ ] Config validation happens at load time, not at use time -- fail early
      with a clear error message
- [ ] Duplicated validation logic extracted into a shared function, not
      copy-pasted across profile type loops
- [ ] When adding a new method that mirrors an existing one's body (same
      transformation, different field), extract the shared logic into a helper
      *before* adding the second implementation -- don't copy-paste method bodies
- [ ] Integer parsing validates ranges, not just format (e.g., timeout must be
      positive or -1, not just a valid i64)

## Ownership and Borrowing

- [ ] `&str` preferred over `String` in function parameters when the function
      doesn't need ownership
- [ ] `&Path` preferred over `PathBuf` in function parameters
- [ ] `impl AsRef<Path>` used for public APIs that accept both `&str` and
      `&Path`
- [ ] `clone()` is explicit and justified -- if you're cloning to satisfy the
      borrow checker, restructure first
- [ ] `Cow<'_, str>` used when a function sometimes needs to allocate and
      sometimes doesn't
- [ ] Lifetimes elided where the compiler can infer them; explicit only when
      the relationship is non-obvious
- [ ] `Arc<T>` used for shared ownership across threads; `Rc<T>` only in
      single-threaded contexts

## Concurrency

- [ ] `Mutex` scope minimized -- no I/O, no function calls, no allocations
      while holding the lock
- [ ] `RwLock` used when reads vastly outnumber writes
- [ ] Atomics used for simple flags and counters instead of mutexes
- [ ] Thread spawning has a clear shutdown mechanism (join handle stored,
      signal channel, or scope)
- [ ] `crossbeam::scope` or `std::thread::scope` used when threads need to
      borrow from the parent stack
- [ ] No `Send` / `Sync` trait impls without `// SAFETY:` justification

## Testing

- [ ] Tests use descriptive names: `test_commit_edit_rejects_unchanged_candidate`
      not `test_commit_edit_3`
- [ ] `#[cfg(test)]` module at end of file, imports with `use super::*`
- [ ] Test helpers use builder patterns or factory functions, not deep parameter
      lists
- [ ] `tempfile::tempdir()` or `env::temp_dir()` for temp files (auto-cleaned)
- [ ] Tests verify behavior, not implementation -- assert on observable
      outputs, not internal state
- [ ] Edge cases tested: empty input, missing files, permission errors,
      concurrent modifications
- [ ] `assert!(matches!(...))` or `let ... else { panic!() }` for enum variant
      assertions -- not `unwrap()` on the wrong variant

## Performance

- [ ] `Vec::with_capacity` used when the final size is known or estimable
- [ ] `String::with_capacity` used when building strings of known length
- [ ] Iterator chains preferred over collecting into intermediate `Vec`s
- [ ] `extend()` used instead of repeated `push()` in loops
- [ ] `&[u8]` / `&str` comparisons preferred over `String` / `Vec<u8>` when
      ownership isn't needed
- [ ] `BTreeMap` used when ordered iteration matters; `HashMap` when it doesn't
- [ ] Release profile tuned: `lto`, `codegen-units = 1`, `strip` for binary
      size; `opt-level` for performance

## Clippy and Formatting

- [ ] `cargo clippy --workspace --all-targets -- -D warnings` passes with no
      warnings
- [ ] `cargo fmt --check` passes
- [ ] Collapsible `if` statements merged (clippy `collapsible_if`)
- [ ] `#[allow(dead_code)]` used sparingly and only on intentionally unused
      items (e.g., enum variants for future use)
- [ ] `#[allow(clippy::...)]` always has a comment explaining why the lint is
      suppressed

## Serde and Serialization

- [ ] `#[serde(default)]` on optional fields that should have zero-value
      defaults
- [ ] `#[serde(deny_unknown_fields)]` on configs where typos could silently
      create wrong behavior
- [ ] Deserialized values validated after parsing -- serde handles syntax, your
      code handles semantics
- [ ] `#[serde(rename_all = "...")]` used consistently within a crate

## Dependencies

- [ ] `Cargo.lock` committed for binaries; not committed for libraries
- [ ] Workspace dependencies (`[workspace.dependencies]`) used in multi-crate
      projects to keep versions in sync
- [ ] `nix` crate preferred over raw `libc` calls for type-safe Unix syscall
      wrappers
- [ ] Feature flags used to gate optional heavy dependencies
- [ ] `cargo audit` or `cargo deny` in CI to catch known vulnerabilities

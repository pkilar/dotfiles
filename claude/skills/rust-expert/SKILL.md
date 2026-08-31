---
name: rust-expert
description: Rust code quality skill for writing and reviewing Rust code. Enforces
  idiomatic patterns, catches unsafe/privilege bugs, and applies security hardening
  for systems code. Invoke manually with /rust-expert when writing new Rust code or
  reviewing existing Rust code.
allowed-tools:
  - Bash
  - Read
  - LSP
  - cargo
  - rustc
  - rustfmt
  - clippy
  - git
---

# Rust Expert

Write and review Rust code that is idiomatic, safe, and correct. This skill
applies to both code generation and code review, with particular emphasis on
systems-level Rust where unsafe code, privilege handling, and file operations
are common.

## Before You Start

1. Read `Cargo.toml` (workspace and crate-level) to determine the Rust edition
   and minimum supported Rust version (MSRV). Edition controls language features
   (e.g., 2024 edition changed `unsafe extern`, `gen` keyword reservation).
   Check for `rust-version` in `[package]`.
2. Read the project's `CLAUDE.md` for architecture constraints, crate
   boundaries, build system details, and testing conventions.
3. Run `cargo check --workspace` to confirm the project builds. If it fails,
   understand why before making changes.
4. Check for `clippy.toml` or workspace-level `[lints]` to understand what lint
   rules the project enforces.

## Core Principles

1. **Safe** -- Default to safe Rust. Every `unsafe` block must have a `// SAFETY:`
   comment explaining why the invariants hold. Minimize the scope of unsafe —
   wrap it in a safe abstraction as close to the call site as possible.
2. **Idiomatic** -- Follow Rust conventions. Use the type system to make illegal
   states unrepresentable. Prefer enums over booleans, `Result` over panics,
   iterators over index loops. Code should look like it was written by someone
   who reads the Rust standard library for fun.
3. **Explicit** -- Don't silently discard results. Don't silently swallow errors.
   Don't rely on implicit behavior when explicit behavior is clearer. The
   compiler is your ally — give it information, don't fight it.
4. **Minimal** -- Start with the simplest solution. No premature abstraction. A
   concrete type is better than a generic one until you need the second
   implementation. Three similar lines is better than a premature trait.

## Workflow

### Writing Code

1. Read `Cargo.toml` and the project's `CLAUDE.md`.
2. Understand the code you're about to change:
   - Read the target file and its module structure.
   - Use LSP `hover` on types and functions to verify signatures.
   - Use LSP `goToDefinition` on any symbol whose behavior you need to
     understand.
   - Use LSP `findReferences` on any function or type you plan to modify to
     assess downstream impact.
3. Write code following the rules below and `references/rust-checklist.md`.
   - Before adding a new method: check if an existing method in the same impl
     block has the same body structure. If so, extract the shared logic into a
     helper first, then call it from both the existing and new method.
4. After writing, verify:
   - `cargo check` passes.
   - `cargo clippy -- -D warnings` passes.
   - `cargo test` passes.
   - `cargo fmt --check` passes.
5. Self-review against the checklist before presenting the code.

### Reviewing Code

1. Read the full diff. Understand intent from commit messages or PR description.
2. Use LSP and grep to deepen the review beyond what the diff shows:
   - `findReferences` on changed function signatures — are all callers updated?
   - `hover` on non-obvious types to verify correctness (e.g., is this a
     `&Path` or `PathBuf`? `&str` or `String`?).
   - grep for patterns the diff might miss: remaining `let _ =`, inconsistent
     error handling, unsafe blocks without SAFETY comments.
3. Evaluate each changed file against `references/rust-checklist.md`.
4. Prioritize findings: **Must Fix** (correctness, security, unsound unsafe) >
   **Should Fix** (performance, maintainability, clippy) > **Consider** (style,
   minor improvements).
5. Present findings in the output format below.

## Critical Rules

These rules are derived from real bugs found in production Rust code. Violations
are always **Must Fix**.

### Rule 1: Never silently discard Results with `let _ =`

`let _ = expr` discards the `Result` (or any value) without inspecting it. This
hides I/O failures, cleanup failures, and logic errors. At minimum, log the
error. In `Drop` implementations where you can't propagate errors, log or
`eprintln!`. In production code, use a helper that logs on failure.

**Bad:**

```rust
let _ = fs::remove_dir_all(&work_dir);
let _ = fs::remove_file(&temp_path);
let _ = session.round_trip(AbortEdit { ticket });
```

**Good:**

```rust
if let Err(err) = fs::remove_dir_all(&work_dir)
    && err.kind() != io::ErrorKind::NotFound
{
    syslog_info(&format!("cleanup: failed to remove '{}': {err}", work_dir.display()));
}

// In a CLI context:
if let Err(err) = session.round_trip(AbortEdit { ticket }) {
    eprintln!("warning: failed to abort edit: {err}");
}
```

**Exception:** `let _ =` is acceptable in test cleanup code where the test
framework handles failures. Even there, prefer `drop()` for intentional
resource release.

### Rule 2: Eliminate TOCTOU races in security-sensitive file operations

When loading a file that must be root-owned or have specific permissions, do
NOT read the file and then stat the path separately. Between the two syscalls,
an attacker who controls the parent directory can swap the file. Open the file
once, fstat the fd, validate, then read from the same fd.

**Bad:**

```rust
let contents = fs::read_to_string(path)?;
let metadata = fs::metadata(path)?;  // TOCTOU: different file possible
validate_ownership(metadata.uid(), metadata.mode())?;
```

**Good:**

```rust
let file = File::open(path)?;
let metadata = file.metadata()?;  // fstat on the open fd
validate_ownership(metadata.uid(), metadata.mode())?;
let mut contents = String::new();
file.read_to_string(&mut contents)?;
```

### Rule 3: Clean up temporary files on all error paths

When creating a temp file that will be atomically renamed into place, ensure
every error between creation and rename removes the temp file. Use a closure,
a guard struct, or explicit cleanup on each error branch. Leaked temp files in
system directories (e.g., `/etc/ssh/.sshd_config.roam.tmp.{uuid}`) persist
indefinitely.

**Bad:**

```rust
fs::copy(&source, &temp_path)?;
chown(&temp_path, uid, gid)?;         // if this fails, temp_path leaks
fs::set_permissions(&temp_path, mode)?; // if this fails, temp_path leaks
fs::rename(&temp_path, &target)?;
```

**Good:**

```rust
fs::copy(&source, &temp_path)?;
let result = (|| {
    chown(&temp_path, uid, gid)?;
    fs::set_permissions(&temp_path, mode)?;
    Ok(())
})();
if let Err(err) = result {
    let _ = fs::remove_file(&temp_path);
    return Err(err);
}
fs::rename(&temp_path, &target)?;
```

### Rule 4: Sanitize user-controlled strings before using them in filesystem paths

Profile names, keys, or identifiers from configuration files or user input must
be validated before interpolation into filesystem paths. TOML allows quoted keys
like `"../../etc"` which can escape intended directories via path traversal.

**Bad:**

```rust
let candidate = edit_dir.join(format!("{profile_name}.{ticket}.candidate"));
// profile_name = "../../etc" → escapes edit_dir
```

**Good:**

```rust
fn validate_name(name: &str) -> Result<()> {
    if name.is_empty()
        || name.contains('/')
        || name.contains("..")
        || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err(Error::Policy(format!("invalid profile name '{name}'")));
    }
    Ok(())
}
```

### Rule 5: Use enums instead of `&mut bool` output parameters

When a function needs to communicate a secondary outcome (e.g., "did this time
out?"), use an enum return type instead of a mutable boolean reference. Enums
are self-documenting, exhaustively matched, and can carry associated data.

**Bad:**

```rust
fn wait_for_child(child: &mut Child, timeout: Duration, timed_out: &mut bool)
    -> Result<ExitStatus>
```

**Good:**

```rust
enum WaitResult {
    Exited(ExitStatus),
    TimedOut(ExitStatus),
}
fn wait_for_child(child: &mut Child, timeout: Duration) -> Result<WaitResult>
```

### Rule 6: `unsafe` blocks in `pre_exec` closures must be async-signal-safe

`Command::pre_exec` closures run between `fork()` and `exec()` in a
single-threaded context where only async-signal-safe operations are permitted.
No heap allocations, no locks, no panics, no `println!`. Only direct syscalls
with captured data.

**Bad:**

```rust
unsafe {
    command.pre_exec(move || {
        let msg = format!("switching to uid {uid}"); // allocation!
        println!("{msg}");                            // lock + I/O!
        setresuid(uid, uid, uid)?;
        Ok(())
    });
}
```

**Good:**

```rust
unsafe {
    command.pre_exec(move || {
        nix::unistd::setresuid(uid, uid, uid).map_err(io::Error::from)?;
        Ok(())
    });
}
```

### Rule 7: Set umask before creating directories and files

When creating directories or files that must have restrictive permissions,
`create_dir_all` + `set_permissions` has a race window where the directory
exists with the default (potentially permissive) umask. Set
`umask(0o077)` before creation for defense-in-depth.

### Rule 8: Validate policy/config constraints consistently across similar profiles

When multiple profile types share the same security requirements (e.g., exec
profiles require absolute paths, edit profiles have validators), ensure the
validation is applied uniformly. If exec profiles require `is_absolute()` on
the program path, edit profile validators must require the same check on their
program argument.

### Rule 9: Don't re-read data you already have in scope

When a value has already been read into a variable, don't call a function that
reads it again from disk. This wastes I/O and introduces a window where the
on-disk value could differ from the in-memory copy, creating subtle
inconsistencies.

**Bad:**

```rust
let current = fs::read(&target)?;
if current != original { return Err(conflict); }
let changed = file_changed(&target, &candidate)?; // re-reads target
```

**Good:**

```rust
let current = fs::read(&target)?;
if current != original { return Err(conflict); }
let candidate_bytes = fs::read(&candidate)?;
let changed = current != candidate_bytes;
```

### Rule 10: Use `nix` crate wrappers instead of raw `libc` calls

When `nix` provides a type-safe wrapper for a libc function, use it. Raw libc
requires `unsafe`, manual error checking (`== -1` + `last_os_error()`), and
`std::mem::zeroed()` for output structs. The `nix` crate eliminates all three.
This applies especially to terminal operations (`termios`), signal handling,
and process control where the libc API surface is error-prone.

**Bad:**

```rust
let mut saved: libc::termios = unsafe { std::mem::zeroed() };
if unsafe { libc::tcgetattr(libc::STDIN_FILENO, &mut saved) } == -1 {
    return Err(Error::last_os_error());
}
unsafe { libc::cfmakeraw(&mut raw) };
if unsafe { libc::tcsetattr(libc::STDIN_FILENO, libc::TCSADRAIN, &raw) } == -1 {
    return Err(Error::last_os_error());
}
```

**Good:**

```rust
let saved = nix::sys::termios::tcgetattr(io::stdin())?;
let mut raw = saved.clone();
nix::sys::termios::cfmakeraw(&mut raw);
nix::sys::termios::tcsetattr(io::stdin(), nix::sys::termios::SetArg::TCSADRAIN, &raw)?;
```

**Exception:** Raw libc is acceptable for operations nix doesn't wrap (e.g.,
`posix_openpt`, `ptsname`, `poll`), or in `pre_exec` closures where nix's
allocating error types would violate async-signal-safety.

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

See `references/rust-checklist.md` for the full checklist. Apply it on every
write and review.

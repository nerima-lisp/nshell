# Roadmap

nshell is converging on world-class interactive-shell parity. For the release
bar each area is measured against, see
[Release readiness](public-readiness.md).

## Near-term focus

**Shell language depth** — richer list variables and explicit semantics around
compound expansions.

Already done: quoting; parameter expansion with defaults, required checks,
substring slicing, and patterns; arithmetic `$((...))` including `**`, bitwise,
shift, and ternary operators; brace expansion; command substitution
`$(...)`/`(...)`; fd redirections `2>`, `2>&1`, `&>`; here-docs `<<`;
here-strings `<<<`; and function arguments via `$argv` / `$argv[N]`.

**Job control hardening** — `Ctrl-C` now reliably interrupts foreground
external commands (delivered through the shell's foreground-pgid forwarding,
or directly via the terminal for `fg`-driven jobs). Remaining: `Ctrl-Z`
suspension for directly-launched foreground commands, which is currently
refused deliberately — the synchronous capture wait cannot represent a
stopped job without losing its output, so the shell continues the child
instead of suspending it.

**Completion intelligence** — broader command metadata and higher-fidelity
flag and value completion.

**Distribution** — nixpkgs, Homebrew, and prebuilt release binaries.

## Released changes

See the
[GitHub Releases](https://github.com/nerima-lisp/nshell/releases).

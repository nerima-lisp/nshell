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

**Job control hardening** — robust foreground process-group handling so
`Ctrl-C` and `Ctrl-Z` reliably interrupt and suspend pipelines.

**Completion intelligence** — broader command metadata and higher-fidelity
flag and value completion.

**Distribution** — nixpkgs, Homebrew, and prebuilt release binaries.

## Released changes

See the
[CHANGELOG](https://github.com/nerima-lisp/nshell/blob/main/CHANGELOG.md).

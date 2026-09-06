# Roadmap

Release readiness tracks the areas below. For the release bar each area is
measured against, see
[Release readiness](public-readiness.md).

## Near-term focus

**Shell language audit** — audit expansion semantics beyond the implemented
structured unquoted list-variable and compound list expansion.

Already done: quoting; parameter expansion with defaults, required checks,
substring slicing, and patterns; arithmetic `$((...))` including `**`, bitwise,
shift, and ternary operators; brace expansion; command substitution
`$(...)`/`(...)`; fd redirections `2>`, `2>&1`, `&>`; here-docs `<<`;
here-strings `<<<`; and function arguments via `$argv` / `$argv[N]`.

**Job control verification** — local non-sandboxed integration now covers
foreground external commands and pipelines with `Ctrl-Z` suspension, `bg`
resumption, `fg` terminal handoff, and `Ctrl-C` interruption. Directly
launched terminal commands use a job-aware wait instead of the synchronous
capture wait that previously prevented suspension. Release evidence on
`x86_64-linux` remains outstanding.

**Command discovery** — extend help-text-driven discovery to cover more
subcommands and non-curated external tools.

**Distribution** — publish at least one installation path beyond `nix run`:
nixpkgs, Homebrew, or prebuilt release binaries.

## Released changes

See the
[GitHub Releases](https://github.com/nerima-lisp/nshell/releases).

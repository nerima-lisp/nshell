# Roadmap

For release gates and known limits, see
[Release readiness](public-readiness.md).

## Near-term focus

**Shell language audit:** review quoting and list-variable expansion against
nshell's documented scripting subset, not full POSIX/fish compatibility.

Implemented features include quoting; parameter expansion with defaults, required checks,
substring slicing, and patterns; arithmetic `$((...))` including `**`, bitwise,
shift, and ternary operators; brace expansion; command substitution
`$(...)`/`(...)`; fd redirections `2>`, `2>&1`, `&>`; here-docs `<<`;
here-strings `<<<`; and function arguments via `$argv` / `$argv[N]`.
This list does not establish that every edge case has been audited.

**Command discovery:** extend help-text-driven discovery beyond the static
command catalog to additional commands and subcommands. See the
[completion model](../guide/concepts.md#completion-is-a-knowledge-base-not-a-table).

**Distribution:** evaluate nixpkgs and Homebrew packaging. Neither channel
is published; a packaging target has not been selected. A prebuilt
`x86_64-linux` bundle is available for v0.6.1; see the
[installation instructions](../getting-started.md#prebuilt-linux-bundle).

## Release evidence

The [v0.6.1 Linux CI run](https://github.com/nerima-lisp/nshell/actions/runs/38050042888)
and [release workflow](https://github.com/nerima-lisp/nshell/actions/runs/38052885425)
validate the tagged tree. The published
[v0.6.1 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.1)
contains the x86_64-linux bundle and SHA-256 checksum. The non-sandboxed
integration suite covers foreground external commands and pipelines with
`Ctrl-Z` suspension, `bg` resumption, `fg` terminal handoff, and `Ctrl-C`
interruption. This does not establish compatibility with every terminal; see
[Release readiness](public-readiness.md).

[GitHub Releases](https://github.com/nerima-lisp/nshell/releases).

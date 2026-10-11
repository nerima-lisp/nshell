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

**Command discovery:** expand the existing command catalog and selective
help-text enrichment to additional commands and subcommands. See the
[completion model](../guide/concepts.md#completion-is-a-knowledge-base-not-a-table).

**Distribution:** evaluate nixpkgs and Homebrew packaging. Neither channel
is published; a packaging target has not been selected. A prebuilt
`x86_64-linux` bundle is available in the
[v0.6.4 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.4).
See the [installation instructions](../getting-started.md#prebuilt-linux-bundle)
for the current distribution.

## Release evidence

The [main Linux CI run](https://github.com/nerima-lisp/nshell/actions/runs/38136077742)
and [v0.6.4 release run](https://github.com/nerima-lisp/nshell/actions/runs/38136113875)
completed with success for commit `5969f455312025356905a0f8e2e104da317a0d6a`.
The published [v0.6.4 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.4)
contains the `x86_64-linux` bundle and SHA-256 checksum. Workflow success does
not establish complete dependency assertion coverage, live AI provider
behavior, or production readiness. The historical
[v0.6.2 capability matrix](public-readiness.md#historical-capability-matrix-v062)
is separate from these current workflow results.

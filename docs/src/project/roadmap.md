# Roadmap

For release gates and known limits, see
[Release readiness](public-readiness.md).

## Current surface

The default branch uses S-expressions for its command language, with bare
command lines as shorthand for ordinary commands. See [Getting started](../getting-started.md)
for the current entry syntax and [Core concepts](../guide/concepts.md) for the
language and pipeline model.

**Command discovery:** expand the existing command catalog and selective
help-text enrichment to additional commands and subcommands. See the
[completion model](../guide/concepts.md#completion-is-a-knowledge-base-not-a-table).

**Distribution:** evaluate nixpkgs and Homebrew packaging. Neither channel
is published; a packaging target has not been selected. A prebuilt
`x86_64-linux` bundle was published in the
[v0.6.4 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.4).
That release predates the current command language; see the
[installation instructions](../getting-started.md#run-with-nix) for the
default branch.

## Historical release evidence (v0.6.4)

The [main Linux CI run](https://github.com/nerima-lisp/nshell/actions/runs/38136077742)
and [v0.6.4 release run](https://github.com/nerima-lisp/nshell/actions/runs/38136113875)
completed with success for the v0.6.4 commit
`5969f455312025356905a0f8e2e104da317a0d6a`. These are historical results for
that release, not verification of the current default branch.
The published [v0.6.4 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.4)
contains the `x86_64-linux` bundle and SHA-256 checksum. Workflow success does
not establish complete dependency assertion coverage, live AI provider
behavior, or production readiness. The historical
[v0.6.2 capability matrix](public-readiness.md#historical-capability-matrix-v062)
is separate from these current workflow results.

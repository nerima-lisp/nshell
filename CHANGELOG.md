# Changelog

All notable changes to nshell are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Vi-mode char-wise visual selection (`v`) with motion, yank, delete, change,
  and count-aware editing coverage.

### Fixed
- Prompt command-duration tracking now records a non-negative millisecond value,
  including sub-millisecond commands.
- `source` command substitution scanning now preserves literal
  non-substitution `$` characters.

### Changed
- README and man page claims now align with the current 0.4.x status, test-count
  evidence, vi visual selection, here-document, and here-string support.
- README testing and contribution guidance now distinguishes hermetic Nix checks
  from full dev-shell integration coverage and links security reporting.
- CONTRIBUTING now includes a release checklist for CI gates, binary smoke
  checks, public docs, manual tag/ref consistency, tarball contents, checksums,
  and changelog hygiene.
- README CLI usage now documents script-file execution and trailing `$argv`
  arguments consistently with `nshell --help` and the man page.

## [0.4.0] - 2026-06-21

### Added
- Script file execution: `nshell SCRIPT [ARGS...]` runs a script file, with full
  support for multiline blocks (functions, if/for/while/switch/begin) via the
  block-aware reader. Any trailing arguments are exposed to the script as
  `$argv`. An `examples/greet.nsh` script demonstrates the feature.

### Fixed
- Whole-line comments (and a leading `#!` shebang) in scripts and `source`d files
  are now skipped instead of causing a parse error.

### Added
- Man page (`man nshell`): a `nshell(1)` manual page documenting options, key
  bindings (Emacs and vi), expansions, control flow, builtins, and environment
  variables. It is installed into `share/man/man1` by the Nix package.

## [0.3.2] - 2026-06-21

### Added
- `seq` builtin: print a sequence of integers (`seq LAST`, `seq FIRST LAST`,
  `seq FIRST STEP LAST`, with negative STEP for descending) — pairs with for
  loops, e.g. `for i in (seq 1 10)`. Registered for `type` and tab-completion.

## [0.3.1] - 2026-06-21

### Added
- `count` builtin (fish-style): prints the number of arguments and exits 0 when
  there is at least one, otherwise 1 — pairs naturally with `$argv`
  (`count $argv`). Registered for `type` and tab-completion.

## [0.3.0] - 2026-06-21

### Added
- Function arguments: a called user-defined function now receives its arguments
  as the fish-style list `$argv` (a bare unquoted `$argv` forwards each argument
  as a separate word) and indexed `$argv[N]` (1-based). POSIX `$1`..`$9` remain
  literal, matching fish.

## [0.2.2] - 2026-06-21

### Changed
- CI hardening: environment-dependent integration tests (PTY round-trips,
  spawning `/bin/cat` / `stty`) are now skipped inside the hermetic Nix build
  sandbox — where those facilities don't exist — and instead run in a dedicated
  non-sandboxed CI job that has them. This makes `nix flake check` reliably green
  on Linux and macOS while preserving real integration coverage. Also removed the
  shut-down `magic-nix-cache-action` from the workflows.

## [0.2.1] - 2026-06-21

### Fixed
- External commands now inherit the real process environment (including `PATH`)
  when the shell has not exported any variables yet — previously they were
  spawned with an empty environment, so commands could not be found via `PATH`
  in batch mode and in non-REPL execution paths. This also makes the
  external-command/pipeline/PTY tests pass under the hermetic Linux CI sandbox.

## [0.2.0] - 2026-06-21

### Added
- Vi key bindings (opt-in via `NSHELL_VI_MODE=1`): `ESC` enters vi normal mode,
  with motions (`h l 0 ^ $ w b e`), insert entries (`i a I A`), edits
  (`x D C s`), operators (`dd cc dw cw d$ d0` and the `c` equivalents), and
  `j` / `k` for history. The default editor remains Emacs-style.
- File-descriptor redirections: `2>file` / `2>>file` (stderr to a file),
  `2>&1` (merge stderr into stdout), and `&>file` / `&>>file` (both streams to
  a file), plus explicit `1>` / `1>>`. Works for single commands and pipeline
  stages. The default (no stderr redirect) behavior is unchanged.
- POSIX command substitution `$(command)` in addition to the existing
  fish-style `(command)`. The tokenizer now keeps `$(...)` and `$((...))`
  attached to surrounding word characters (quote/escape aware), so
  `a$((1+2))b`, `"$(cmd)"`, and `pre$(echo ")")post` all parse and expand
  correctly. This also makes `$((expr))` arithmetic work end-to-end (previously
  it was eaten by the command-substitution scanner before the arithmetic pass).
- Brace expansion: comma lists `{a,b,c}` and ranges `{1..5}` / `{a..e}`,
  including nested and adjacent (cartesian) groups. A group with no top-level
  comma or valid range is left literal, matching shell behavior.
- Arithmetic expansion `$((expression))`: integer `+ - * / %`, parentheses,
  unary `- + ! ~`, comparisons (`== != < > <= >=`), and logical `&& ||`, with
  bare names resolved from the environment (unset → 0) and division-by-zero
  reported as an error.
- POSIX parameter-expansion operators inside `${...}`: `${VAR:-default}`,
  `${VAR-default}`, `${VAR:=default}`, `${VAR:+alt}`, `${VAR+alt}`,
  `${VAR:?msg}`, length `${#VAR}`, prefix/suffix stripping `${VAR#pat}` /
  `${VAR##pat}` / `${VAR%pat}` / `${VAR%%pat}` (glob patterns), and substitution
  `${VAR/pat/rep}` / `${VAR//pat/rep}` (literal patterns). Default, alternate,
  assignment words, and patterns are themselves variable-expanded; `${VAR:=word}`
  assigns the expanded word when its fallback branch is used.
- `CONTRIBUTING.md`, `SECURITY.md`, GitHub issue templates, and a pull-request
  template.
- `LICENSE` file (MIT) at the repository root.
- GitHub Actions CI (`nix flake check` — build + full test suite + smoke tests)
  on a Linux + macOS matrix, triggered on pushes, pull requests, and tags.
- GitHub Actions release workflow that builds per-platform binaries and uploads
  tarballs with SHA-256 checksums to GitHub Releases on `v*` tags.
- `meta` attributes (license, homepage, platforms, mainProgram) on the Nix
  package, and `:homepage` / `:source-control` to the ASDF system definition.
- This `CHANGELOG.md` and a project `README.md`.

### Changed
- Double-quoted strings now follow POSIX semantics: variables are expanded but
  globbing and word-splitting are suppressed, so `"$VAR"` expands while `"*"`
  stays literal. Arguments now carry a three-way quote style
  (unquoted / `:single` / `:double`) through the tokenizer, parser, and
  expander instead of a single "is-literal" boolean.

### Fixed
- Made the `repl-clear-screen` rendering test hermetic: it now pins the prompt
  width and terminal size so the asserted rendered-line count no longer depends
  on the ambient working directory (the default prompt renders the cwd, which is
  a long path inside the build sandbox). The full suite is green (4912 checks).

## [0.1.0]

Initial development version: fish-inspired interactive shell in Common Lisp
(SBCL) with a CPS/trampoline REPL, syntax highlighting, autosuggestions,
abbreviations, completion engine, kill-ring/undo, history search, job control,
and a Nix-based reproducible build.

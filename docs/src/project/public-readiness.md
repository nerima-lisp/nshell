# Public Readiness

This document defines the release bar for presenting nshell as a serious
interactive shell. It is intentionally stricter than "the tests pass": each
area needs user-visible capability, repeatable evidence, and an explicit gap
status.

## Positioning

nshell targets daily interactive use first. The release claim is a modern
interactive shell with a tested editor, completion, history, process control,
and scripting subset.

## Capability Matrix

| Area | Release bar | Current evidence | Status |
| --- | --- | --- | --- |
| Interactive editor | Live syntax feedback, Emacs bindings, optional vi mode, multiline editing, undo/yank, predictable rendering | README highlights, man page key bindings, input-state and rendering tests | Ready locally |
| History and suggestions | Persistent history, reverse search, prefix autosuggestions, safe handling of multiline entries | history, autosuggest, and E2E editing tests | Ready locally |
| Completion | Context-aware command/path/flag completion, candidate menu, deterministic cycling and cancellation | completion domain tests, REPL completion rendering tests, path-like argument completion, hierarchical command resolution, common external command metadata, help-text metadata loader with selective runtime enrichment, README/man page claims | Improved locally; broader command discovery/cache policy and subcommand coverage remain future work |
| Shell language | Practical interactive scripting: functions, control flow, command substitution, expansions, heredocs, here-strings, redirection, pipelines | parser, expansion, source, pipeline, process-substitution, descriptor-duplication, tab-stripping-heredoc, and smoke tests, structured unquoted list-variable expansion | Improved locally; broader expansion parity audit still required |
| Process control | Foreground/background jobs, `jobs`/`fg`/`bg`/`disown`, Ctrl-C foreground recovery, PTY smoke coverage, foreground external commands (editors, SSH) run to completion instead of being killed by a default timeout; finite timeouts remain for non-interactive execution and command substitution | job-control tests, PTY integration tests, and the non-sandboxed `nix develop -c sbcl --script run-tests.lisp` gate; `docs/notes/timeout-audit.md` records the interactive exemption and bounded non-interactive paths | Needs release evidence on `x86_64-linux` |
| Reliability | Hermetic build/test gate plus non-sandboxed OS-interactive gate for PTY, terminal, process, signal, and job-control behavior | `nix flake check --print-build-logs`; dev-shell E2E/integration command in README and CONTRIBUTING; the current coverage command and its report documented in `docs/notes/coverage-analysis.md` | CI-gated; only `x86_64-linux` is declared |
| Distribution | Reproducible Nix build, installed man page, release binary smoke, checksummed artifacts | flake build, man page, CI/release workflows, release checklist | Needs nixpkgs/Homebrew/prebuilt binary publication |
| Security and operations | Private vulnerability reporting, explicit security scope, no accidental secret exposure through history/completion/diagnostics | the org security policy and [contribution guidelines](contributing.md) | Ready for 0.x scope |

## Release Gates

Before a public release can claim the capabilities listed here:

1. `nix flake check --print-build-logs` passes on `x86_64-linux` CI, the
   only declared hermetic check target.
2. The non-sandboxed integration suite passes for PTY, subprocess, terminal,
   signal, and job-control coverage on the sole CI matrix target,
   `x86_64-linux`.
3. A release binary is built on `x86_64-linux`, starts successfully, and ships
   with `README.md`, `LICENSE`, and the `nshell(1)` man page.
4. User-visible behavior changes are represented in README, man page, the
   GitHub Release notes, and completion metadata when applicable.
5. Open roadmap gaps remain explicit instead of being implied as complete.

## Verification outside CI

The current flake declares only `x86_64-linux`. On another host, the Nix
checks and dev shell require an `x86_64-linux` builder; do not treat a local
macOS result as release evidence.

- Run `nix flake check --print-build-logs` on an `x86_64-linux` builder. This is
  the authoritative completion evidence for the hermetic checks.
- Run `nix develop -c sbcl --script run-tests.lisp` on the same target for the
  non-sandboxed PTY and external-process suite.
- The integrated suite also covers the user-visible behavior added across the
  current work units: OSC 52 clipboard output, tab-stripping `<<-` heredocs,
  process substitution, ordered descriptor duplication, path-like argument
  completion, hierarchical command completion, and SGR mouse selection.

## Current Public Gaps

- Broader help-text-driven command discovery remains future work, especially for
  subcommand coverage and non-curated external tools.
- Complete the remaining expansion-semantics audit beyond structured unquoted
  list-variable and compound list expansion, plus other unimplemented edge
  cases.
- Validate mouse selection and host clipboard behavior on every supported
  terminal/platform; the editor now maps SGR coordinates through captured
  prompt geometry and falls back to OSC 52 when host clipboard integration is
  unavailable.
- Keep release evidence tied to the declared `x86_64-linux` target.
- Publish at least one low-friction installation path beyond `nix run`, such as
  nixpkgs, Homebrew, or prebuilt release binaries.
- The x86_64-linux release bundle is checked for Nix store references, its ELF
  runtime closure, required files, dependency metadata, and `--help`,
  `--version`, and `echo` smoke behavior in CI. Tarball extraction is not a
  separate CI check.
- Verify the global all-target publication gate, checksums, and GitHub artifact
  attestations in CI before describing release provenance as operational.
- Validate the process-isolated benchmark scenarios in CI and collect equivalent
  fixtures beyond the implemented minimal noninteractive literal-print case.
- Collect privileged cold-cache, interactive, completion, and end-to-end
  tail-latency evidence before making any broad performance claim.

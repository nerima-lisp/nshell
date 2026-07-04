# Public Readiness

This document defines the release bar for presenting nshell as a serious
interactive shell. It is intentionally stricter than "the tests pass": each
area needs user-visible capability, repeatable evidence, and an explicit gap
status.

## Positioning

nshell targets daily interactive use first. The release claim is not POSIX
`/bin/sh` replacement compatibility; it is a modern interactive shell with a
tested editor, completion, history, process control, and scripting subset.

## Capability Matrix

| Area | Release bar | Current evidence | Status |
| --- | --- | --- | --- |
| Interactive editor | Live syntax feedback, Emacs bindings, optional vi mode, multiline editing, undo/yank, predictable rendering | README highlights, man page key bindings, input-state and rendering tests | Ready locally |
| History and suggestions | Persistent history, reverse search, prefix autosuggestions, safe handling of multiline entries | history, autosuggest, and E2E editing tests | Ready locally |
| Completion | Context-aware command/path/flag completion, candidate menu, deterministic cycling and cancellation | completion domain tests, REPL completion rendering tests, common external command metadata, help-text metadata loader, README/man page claims | Improved locally; command discovery/cache policy remains future work |
| Shell language | Practical interactive scripting: functions, control flow, command substitution, expansions, heredocs, here-strings, redirection, pipelines | parser, expansion, source, pipeline, and smoke tests, structured unquoted list-variable expansion | Improved locally; broader expansion parity audit still required |
| Process control | Foreground/background jobs, `jobs`/`fg`/`bg`/`disown`, Ctrl-C foreground recovery, PTY smoke coverage | job-control tests, PTY integration tests, non-sandboxed E2E gate | Needs release evidence across Linux, x86_64-darwin, and aarch64-darwin |
| Reliability | Hermetic build/test gate plus non-sandboxed OS-interactive gate for PTY, terminal, process, signal, and job-control behavior | `nix flake check --print-build-logs`; dev-shell E2E/integration command in README and CONTRIBUTING | Ready locally; CI evidence required across supported platforms |
| Distribution | Reproducible Nix build, installed man page, release binary smoke, checksummed artifacts | flake build, man page, CI/release workflows, release checklist | Needs nixpkgs/Homebrew/prebuilt binary publication |
| Security and operations | Private vulnerability reporting, explicit security scope, no accidental secret exposure through history/completion/diagnostics | SECURITY.md and contribution guidelines | Ready for 0.x scope |

## Release Gates

Before a public release can claim world-level interactive-shell quality:

1. `nix flake check --print-build-logs` passes on Linux, x86_64-darwin, and aarch64-darwin CI.
2. The non-sandboxed integration suite passes for PTY, subprocess, terminal,
   signal, and job-control coverage.
3. A release binary is built on Linux, x86_64-darwin, and aarch64-darwin, starts successfully, and ships
   with `README.md`, `LICENSE`, and the `nshell(1)` man page.
4. User-visible behavior changes are represented in README, man page,
   CHANGELOG, and completion metadata when applicable.
5. Open roadmap gaps remain explicit instead of being implied as complete.

## Current Public Gaps

- Wire command-specific discovery and cache policy around the help-text
  completion metadata loader; the default external command coverage remains
  intentionally curated static metadata unless callers provide help text.
- Complete the remaining fish/POSIX expansion parity audit beyond structured
  unquoted list-variable and compound list expansion.
- Collect release evidence on every CI-supported platform, not only a local
  development machine.
- Publish at least one low-friction installation path beyond `nix run`, such as
  nixpkgs, Homebrew, or prebuilt release binaries.

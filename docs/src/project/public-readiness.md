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
| Completion | Context-aware command/path/flag completion, candidate menu, deterministic cycling and cancellation | completion domain tests, REPL completion rendering tests, common external command metadata, help-text metadata loader with selective runtime enrichment, README/man page claims | Improved locally; broader command discovery/cache policy and subcommand coverage remain future work |
| Shell language | Practical interactive scripting: functions, control flow, command substitution, expansions, heredocs, here-strings, redirection, pipelines | parser, expansion, source, pipeline, and smoke tests, structured unquoted list-variable expansion | Improved locally; broader expansion parity audit still required |
| Process control | Foreground/background jobs, `jobs`/`fg`/`bg`/`disown`, Ctrl-C foreground recovery, PTY smoke coverage, foreground external commands (editors, SSH) run to completion under a real terminal instead of being killed by the command-substitution safety timeout | job-control tests, PTY integration tests, non-sandboxed E2E gate, `docs/timeout-audit.md` (real-PTY regression test) | Needs release evidence on `x86_64-linux` |
| Reliability | Hermetic build/test gate plus non-sandboxed OS-interactive gate for PTY, terminal, process, signal, and job-control behavior | `nix flake check --print-build-logs`; dev-shell E2E/integration command in README and CONTRIBUTING; `docs/coverage-analysis.md`'s full state-2 sweep (every line in `src/` accounted for) | Ready locally; CI evidence required across supported platforms |
| Distribution | Reproducible Nix build, installed man page, release binary smoke, checksummed artifacts | flake build, man page, CI/release workflows, release checklist | Needs nixpkgs/Homebrew/prebuilt binary publication |
| Security and operations | Private vulnerability reporting, explicit security scope, no accidental secret exposure through history/completion/diagnostics | the org security policy and [contribution guidelines](contributing.md) | Ready for 0.x scope |

## Release Gates

Before a public release can claim world-level interactive-shell quality:

1. `nix flake check --print-build-logs` passes on `x86_64-linux` CI — the only
   platform `flake.nix` declares.
2. The non-sandboxed integration suite passes for PTY, subprocess, terminal,
   signal, and job-control coverage.
3. A release binary is built on `x86_64-linux` — the only platform `flake.nix`
   declares — starts successfully, and ships with `README.md`, `LICENSE`, and
   the `nshell(1)` man page.
4. User-visible behavior changes are represented in README, man page, the
   GitHub Release notes, and completion metadata when applicable.
5. Open roadmap gaps remain explicit instead of being implied as complete.

## 2026-08-03 local verification pass

What is actually checkable on a plain `aarch64-darwin` development machine
(not CI), run directly rather than assumed:

- `nix build .#checks.aarch64-darwin.docs` and
  `nix build .#checks.aarch64-darwin.formatting` both exit 0 -- the mkdocs
  `--strict` build and the treefmt gate (316 files traversed) pass on this
  platform.
- `nix build .#checks.aarch64-darwin.{build,default,smoke-test}` and
  `nix flake check` do **not** run here: see
  [[nix-build-darwin-gap]] (`cl-prolog` ships no darwin package at the
  pinned tag), the same gap this repository's own `docs/notes/`
  acknowledges. This is a platform gap in the check runner, not a defect in
  `flake.nix` -- `x86_64-linux` is what `flake.nix`'s own comments name as
  the platform CI gates.
- The equivalent SBCL-level verification -- what `checks.default` runs
  under the hood -- was run directly instead, repeatedly across this
  session's commits: `nshell/test` at 1327/1327 passing against a
  from-scratch fasl cache (ruling out a warm-cache-masked load-order bug),
  most recently after this session's `flake.lock` dependency bumps and
  `package.lisp` file split.

## Current Public Gaps

- Broader help-text-driven command discovery remains future work, especially for
  subcommand coverage and non-curated external tools.
- Complete the remaining expansion-semantics audit beyond structured unquoted
  list-variable and compound list expansion, including general `n>&m`
  file-descriptor duplication and other unimplemented edge cases.
- Validate mouse selection and host clipboard behavior on every supported
  terminal/platform; the editor now maps SGR coordinates through captured
  prompt geometry and falls back to OSC 52 when host clipboard integration is
  unavailable.
- Collect release evidence on every CI-supported platform, not only a local
  development machine.
- Publish at least one low-friction installation path beyond `nix run`, such as
  nixpkgs, Homebrew, or prebuilt release binaries.
- Obtain native x86_64-linux CI evidence for the implemented bundle derivation:
  build it, validate it, and smoke-test it after tar extraction. Darwin has
  already passed the equivalent checks; published v0.4.0 artifacts remain
  non-portable.
- Verify the global all-target publication gate, checksums, and GitHub artifact
  attestations in CI before describing release provenance as operational.
- Validate the process-isolated benchmark scenarios in CI and collect equivalent
  fixtures beyond the implemented minimal noninteractive literal-print case.
- Collect privileged cold-cache, interactive, completion, and end-to-end
  tail-latency evidence before making any broad "world-fastest" performance claim.

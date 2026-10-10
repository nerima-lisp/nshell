# Public Readiness

This document records the release gates, evidence, and known limits for
nshell's interactive features.

## Positioning

nshell targets daily interactive use first. v0.6.1 is a development preview,
not a POSIX/fish-compatible script interpreter.

## Capability Matrix

| Area | Release bar | Current evidence | Status |
| --- | --- | --- | --- |
| Interactive editor | Live syntax feedback, Emacs bindings, optional vi mode, multiline editing, undo/yank, predictable rendering | input-state, rendering, and PTY integration tests | CI-verified on `x86_64-linux` |
| History and suggestions | Persistent history, reverse search, prefix autosuggestions, handling of multiline entries | history, autosuggest, and E2E editing tests | CI-verified on `x86_64-linux` |
| Completion | Context-aware command/path/flag completion, candidate menu, deterministic cycling and cancellation | completion domain and REPL rendering tests, hierarchical command resolution, curated external command metadata and selective help-text enrichment | Broader command discovery/cache policy and subcommand coverage remain future work |
| Shell language | Functions, control flow, command substitution, expansions, heredocs, here-strings, redirection, pipelines | parser, expansion, source, pipeline, process-substitution, descriptor-duplication, tab-stripping-heredoc, and smoke tests | Tested subset; full POSIX/fish parity is not claimed |
| Process control | Foreground/background jobs, `jobs`/`fg`/`bg`/`disown`, Ctrl-C recovery, terminal restoration; external commands attached to the interactive terminal have no default timeout, while redirected execution and command substitution remain bounded | job-control and non-sandboxed PTY integration tests | CI-verified on `x86_64-linux` |
| Distribution | Reproducible Nix build, installed man page, release binary smoke, checksummed artifacts | flake build, man page, CI/release workflows, [v0.6.1 release assets](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.1) | Prebuilt `x86_64-linux` binary and SHA-256 checksum published; nixpkgs/Homebrew remain future work |
| Security and operations | Private vulnerability reporting, explicit security scope, validation of secret handling in history/completion/diagnostics | [repository security policy](https://github.com/nerima-lisp/nshell/blob/v0.6.1/SECURITY.md) and [contribution guidelines](contributing.md) | Reporting policy exists; it does not establish a security audit of runtime behavior |

The [v0.6.1 CI run](https://github.com/nerima-lisp/nshell/actions/runs/38050042888)
and [release workflow](https://github.com/nerima-lisp/nshell/actions/runs/38052885425)
validate the tagged tree. The published
[v0.6.1 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.1)
contains the x86_64-linux bundle and SHA-256 checksum. The non-sandboxed
integration job runs the PTY and external-process cases skipped by the Nix
sandbox.

## Release Gates

These are the existing nshell gates, not a production-readiness verdict.
They do not close the dependency-suite and license-packaging gaps below.

Before a public release can claim the capabilities listed here:

1. `nix flake check --print-build-logs` passes on `x86_64-linux` CI, the
   only declared hermetic check target.
2. The non-sandboxed integration suite passes for PTY, subprocess, terminal,
   signal, and job-control coverage on the sole CI matrix target,
   `x86_64-linux`, without skipping those cases.
3. A release binary is built on `x86_64-linux`, starts, and ships
   with `README.md`, `LICENSE`, and the `nshell(1)` man page.
4. User-visible behavior changes are represented in README, man page, the
   GitHub Release notes, and completion metadata when applicable.
5. Open roadmap gaps remain explicit instead of being implied as complete.

The [release workflow](https://github.com/nerima-lisp/nshell/blob/v0.6.1/.github/workflows/release.yml)
runs hermetic checks and a non-sandboxed integration job against the same
resolved tagged commit, and only then builds the published release assets.

## Verification outside CI

The current flake declares only `x86_64-linux`. On another host, the Nix
checks require an `x86_64-linux` builder. Running the dev shell or PTY suite
also requires an `x86_64-linux` execution environment; a remote builder alone
does not supply that runtime coverage.

- Run `nix flake check --print-build-logs` on an `x86_64-linux` builder.
- Run `NSHELL_TEST_PTY=1 nix develop -c sbcl --script run-tests.lisp` on the
  same target for the non-sandboxed PTY and external-process suite.
  Confirm nonempty test discovery and no skipped PTY or external-process cases
  in the test report; an exit status of zero alone does not establish coverage.
- The integrated suite covers OSC 52 clipboard output, tab-stripping `<<-` heredocs,
  process substitution, ordered descriptor duplication, path-like argument
  completion, hierarchical command completion, and SGR mouse selection.

## Known Limits and Future Work

- Broader help-text-driven command discovery remains future work, especially for
  subcommand coverage and non-curated external tools.
- Full POSIX/fish expansion compatibility is outside the documented scripting
  subset; scripts for those shells must not be assumed compatible.
- Mouse selection and clipboard behavior depend on the terminal. No exhaustive
  terminal matrix is claimed; the editor maps SGR coordinates through captured
  prompt geometry and falls back to OSC 52 when host clipboard integration is
  unavailable.
- The x86_64-linux release bundle is checked for Nix store references, its ELF
  runtime closure, required files listed in
  [`scripts/verify-release-bundle.pl`](https://github.com/nerima-lisp/nshell/blob/v0.6.1/scripts/verify-release-bundle.pl),
  and `--help`, `--version`, and `echo` smoke behavior in CI via
  `perl scripts/verify-release-bundle.pl result`. This checks the Nix build
  output, not an extracted tarball. It does not run the full integration suite
  against the bundled executable.
- The bundle verifier checks the Nix output directory, not a re-extracted
  tarball. Tar extraction, checksum verification, and execution of the
  extracted bundle remain release-consumer checks; the bundled executable is
  smoke-tested in the Nix output during CI.
- CI runs nshell's test suites, not the dependency libraries' own suites.
  Loading those libraries or their test helpers does not establish that their
  suites pass.
- Release assets include a SHA-256 checksum. GitHub artifact attestations are
  not configured; the checksum alone is not a provenance attestation.
- Validate the process-isolated benchmark scenarios in CI and collect equivalent
  fixtures beyond the implemented minimal noninteractive literal-print case.
- Collect privileged cold-cache, interactive, completion, and end-to-end
  tail-latency evidence before making any broad performance claim. See
  [Performance evidence](../guide/recipes.md#performance-evidence).

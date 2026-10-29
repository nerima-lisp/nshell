# Public Readiness

## Positioning

nshell targets interactive use. The 0.6 series is a development preview,
not a POSIX/fish-compatible script interpreter.

## Historical release evidence (v0.6.4)

The published [v0.6.4 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.4)
contains the `x86_64-linux` bundle and SHA-256 checksum. The
[main CI run](https://github.com/nerima-lisp/nshell/actions/runs/38136077742)
and [v0.6.4 release run](https://github.com/nerima-lisp/nshell/actions/runs/38136113875)
completed with success for commit `5969f455312025356905a0f8e2e104da317a0d6a`.
These workflow results do not establish production readiness, complete
dependency assertion coverage, or successful live AI provider requests.

## Local verification for v0.6.5

The macOS arm64 source-loaded suite passed with PTY cases enabled and no
skipped cases. The pinned dependency suites and private history storage
regressions also passed. The dependency gate rejects zero-assertion runs of
three selected history properties and tests the pinned process library's
native spawn helper separately from its Lisp suite.

A locally built executable was tested in a real PTY with Claude Code 2.1.295.
The probe checked that a proposed `touch` command did not run before approval,
Enter executed it once, cancellation left no file, a subsequent request could
execute a fresh proposal, and exit reaped the provider processes. These are
bounded checks with one provider on one platform, not an exhaustive provider
or terminal compatibility claim. They are not part of the linked CI runs.

## Historical capability matrix (v0.6.2)

The evidence and statuses below describe the published `v0.6.2` tree. They are
historical evidence, not results from the v0.6.4 workflows above.

| Area | Capability or policy | Published evidence | Status |
| --- | --- | --- | --- |
| Interactive editor | Live syntax feedback, Emacs bindings, optional vi mode, multiline editing, undo/yank, predictable rendering | input-state, rendering, and PTY integration tests | CI-verified on `x86_64-linux` |
| History and suggestions | Persistent history, reverse search, prefix autosuggestions, handling of multiline entries | history, autosuggest, and E2E editing tests | CI-verified on `x86_64-linux` |
| Completion | Context-aware command/path/flag completion, candidate menu, deterministic cycling and cancellation | completion domain and REPL rendering tests, hierarchical command resolution, curated external command metadata and selective help-text enrichment | Broader command discovery/cache policy and subcommand coverage remain future work |
| Shell language | Functions, control flow, command substitution, expansions, heredocs, here-strings, redirection, pipelines | parser, expansion, source, pipeline, process-substitution, descriptor-duplication, tab-stripping-heredoc, and smoke tests | Tested subset; full POSIX/fish parity is not claimed |
| Process control | Foreground/background jobs, `jobs`/`fg`/`bg`/`disown`, Ctrl-C recovery, terminal restoration; foreground external commands whose standard output is a terminal have no default timeout, while file/pipe output defaults to 3600 seconds and command substitution to 300 seconds | job-control and non-sandboxed PTY integration tests | CI-verified on `x86_64-linux` |
| Distribution | Nix-pinned build, installed man page, release binary smoke, checksummed artifacts | flake build, man page, CI/release workflows, [v0.6.2 release assets](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.2) | Prebuilt `x86_64-linux` binary and SHA-256 checksum published; nixpkgs/Homebrew remain future work |
| Security and operations | Private vulnerability reporting and explicit security scope | [repository security policy](https://github.com/nerima-lisp/nshell/blob/v0.6.2/SECURITY.md) and [contribution guidelines](contributing.md) | Reporting policy exists; it does not establish a security audit of runtime behavior |

The [v0.6.2 CI run](https://github.com/nerima-lisp/nshell/actions/runs/38120933504)
and [release workflow](https://github.com/nerima-lisp/nshell/actions/runs/38120952046)
validate the tagged tree. The non-sandboxed
integration job runs the PTY and external-process cases skipped by the Nix
sandbox.

## Release Gates

These are the existing nshell gates, not a production-readiness verdict.
The historical v0.6.2 release run includes dependency-suite and extracted-artifact
checks, including the extracted executable's real-PTY gate.

Before a public release can claim the capabilities listed here:

1. `nix flake check --print-build-logs` passes on `x86_64-linux` CI, the
   only declared hermetic check target.
2. The non-sandboxed integration suite passes for PTY, subprocess, terminal,
   signal, and job-control coverage on the sole CI matrix target,
   `x86_64-linux`, without skipping those cases.
3. The pinned dependency suites execute directly, with nonempty discovery,
   matching selected/executed counts, and no skipped cases. Suite-level pass
   counts alone do not establish assertion coverage. The private history
   storage regressions pass.
4. An `x86_64-linux` release archive passes checksum verification before
   extraction. The extracted bundle passes required-file, dependency-closure,
   license-file, and runtime smoke checks. Its executable passes the real-PTY gate for editing,
   signals, job control, history restart, and terminal restoration, and ships
   with `README.md`, `LICENSE`, dependency licenses, and `nshell(1)`.
5. User-visible behavior changes are represented in README, man page, the
   GitHub Release notes, and completion metadata when applicable.
6. Open roadmap gaps remain explicit instead of being implied as complete.

The [v0.6.2 release workflow](https://github.com/nerima-lisp/nshell/blob/v0.6.2/.github/workflows/release.yml)
runs hermetic checks and a non-sandboxed integration job against the same
resolved tagged commit, and only then builds the release assets in a draft.
A maintainer reviews the assets and release notes before publishing the draft.

## Verification outside CI

Run these checks from the checkout being verified. To reproduce the historical
release evidence above, use the `v0.6.2` tag. The flake declares only
`x86_64-linux`. On another host, the Nix
checks require an `x86_64-linux` builder. Running these Nix-based commands
also requires an `x86_64-linux` execution environment; a remote builder alone
does not supply that runtime coverage.

- Run `nix flake check --print-build-logs` on an `x86_64-linux` builder.
- Run the non-sandboxed suites on the same target with a temporary home and
  XDG directories, as the integration jobs do. Tests can access history and
  configuration through the normal runtime APIs; do not use personal data.
  Run this block from the repository root:

  ```sh
  (
    verification_dir=$(mktemp -d)
    mkdir -p "$verification_dir/home" "$verification_dir/cache" \
      "$verification_dir/config" "$verification_dir/state"
    export HOME="$verification_dir/home"
    export XDG_CACHE_HOME="$verification_dir/cache"
    export XDG_CONFIG_HOME="$verification_dir/config"
    export XDG_STATE_HOME="$verification_dir/state"
    export NSHELL_AI_COMMAND=/nonexistent NSHELL_TEST_PTY=1
    nix develop -c sbcl --script run-tests.lisp &&
      nix develop -c bash scripts/test-dependencies.sh &&
      nix develop -c sbcl --script scripts/test-history-storage.lisp
  )
  ```

  Confirm nonempty test discovery and no skipped PTY or external-process cases
  in the test report; an exit status of zero alone does not establish coverage.
- The integrated suite covers OSC 52 clipboard output, tab-stripping `<<-` heredocs,
  process substitution, ordered descriptor duplication, path-like argument
  completion, hierarchical command completion, and SGR mouse selection.
- The dependency runner executes the pinned libraries' own suites; the history
  script checks private persistence. A successful library load is not a test
  result.
- Verify the release archive against its SHA-256 checksum before extraction.
  Extract it and run
  `perl scripts/verify-release-bundle.pl <extracted-bundle>` followed by
  `perl scripts/test-release-pty.pl <extracted-bundle>` on `x86_64-linux`.

## Known Limits and Future Work

- The local
  v0.6.5 probe above covers explicit approval, cancellation, and subsequent
  requests with one provider; other providers and failure modes remain unverified.
- Broader help-text-driven command discovery remains future work, especially for
  subcommand coverage and non-curated external tools.
- Mouse selection and clipboard behavior depend on the terminal. No exhaustive
  terminal matrix is claimed; the editor maps SGR coordinates through captured
  prompt geometry and falls back to OSC 52 when host clipboard integration is
  unavailable.
- The extracted executable's PTY scenarios are a separate bounded gate, not
  the entire source-loaded integration suite. Passing them does not establish
  every integration case against the portable executable.
- Release assets include a SHA-256 checksum. GitHub artifact attestations are
  not configured; the checksum alone is not a provenance attestation.
- Validate the process-isolated benchmark scenarios in CI and collect equivalent
  fixtures beyond the implemented minimal noninteractive literal-print case.
- Collect privileged cold-cache, interactive, completion, and end-to-end
  tail-latency evidence before making any broad performance claim. See
  [Performance evidence](../guide/recipes.md#performance-evidence).

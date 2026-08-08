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
| Interactive editor | Live syntax feedback, Emacs bindings, optional vi mode, multiline editing, undo/yank, external `Alt-E` editing, predictable rendering | README highlights, man page key bindings, input-state, editor, and rendering tests | Ready locally |
| History and suggestions | Persistent history, reverse search, prefix autosuggestions, history expansion, safe handling of multiline entries | history expansion, history, autosuggest, and E2E editing tests | Ready locally |
| Completion | Context-aware command/path/flag completion, candidate menu, deterministic cycling and cancellation | completion domain tests, REPL completion rendering tests, runtime alias/function candidates at command position, one compiled rulebase and one request-scoped description index per request, prefix/deduplication before candidate construction, and a TTL/stamp-validated bounded PATH cache with per-key single-flight loading and generation-safe invalidation | Improved locally; broader command discovery and subcommand coverage remain future work |
| Shell language | Practical interactive scripting: functions, control flow, command substitution, expansions, heredocs (including tab-stripping `<<-`), here-strings, redirection, pipelines | parser, expansion, source, pipeline, process, and smoke tests, structured unquoted list-variable expansion, and `<<-` integration coverage | Improved locally; broader expansion parity audit still required |
| Process control | Foreground/background jobs, `jobs`/`fg`/`bg`/`disown`, Ctrl-C foreground recovery, PTY smoke coverage, and foreground external commands or pipelines (editors, SSH) run to completion under a real terminal instead of being killed by the command-substitution safety timeout; redirected or captured execution retains that safety timeout | job-control tests, PTY integration tests, non-sandboxed E2E gate, `docs/timeout-audit.md` (real-PTY command and pipeline regression tests) | Needs release evidence across x86_64-linux and aarch64-darwin |
| Reliability | Hermetic build/test gate plus non-sandboxed OS-interactive gate for PTY, terminal, process, signal, and job-control behavior | `nix flake check --print-build-logs`; source-built cl-prolog and cl-weave avoid unavailable upstream aarch64-darwin package attributes; dev-shell E2E/integration command in README and CONTRIBUTING | Ready locally; CI evidence required across supported platforms |
| Distribution | Reproducible Nix build, installed man page, release binary smoke, checksummed and portable artifacts with provenance | flake build, man page, bundle validator, Darwin extracted-tar `env -i` smoke test and `otool` inspection; x86_64-linux derivation evaluation | Bundle implementation exists and Darwin is verified locally; native x86_64-linux evidence, a global all-target publication gate, and published attestations still require CI verification. Published v0.4.0 artifacts remain non-portable; no portable release has been published |
| Security and operations | Private vulnerability reporting, explicit security scope, and a documented history-data limitation | The repository [security policy](https://github.com/nerima-lisp/nshell/blob/main/SECURITY.md), [contribution guidelines](contributing.md), and the warning below | Ready for 0.x scope |

Command history is stored as plain text in `~/.nshell_history`. Do not enter
passwords, access tokens, or other secrets in nshell commands.

## Performance Evidence

The implemented completion benchmark emits JSON Lines containing raw batch
samples, percentiles, runtime metadata, allocation measurements, and
correctness checksums. `scripts/verify-benchmark-jsonl.pl` rejects empty,
malformed, unknown-schema, non-finite, count-inconsistent, or statistically
incoherent evidence. Its self-test is a required `nix flake check` derivation;
the gate deliberately has no machine-dependent latency threshold. The current
implemented baseline measures synthetic, warm, in-process completion API calls.

The benchmark suite also implements process-isolated startup and command
execution scenarios, so its scope is no longer limited to in-process calls.
These `fresh-process-warm-fs` samples start a new process for every measurement
without clearing OS filesystem or executable caches. They set `comparable` and
`ranking_eligible` to `false` and include the comparison exclusion reason in
each JSON record. They are diagnostic evidence, not a controlled competitor
comparison or proof of end-to-end interactive parity; CI evidence must still
be collected before treating the new coverage as release evidence.

The separate `scripts/benchmark-competitors.pl` harness accepts only immutable
Nix store executables resolved from the flake's locked inputs. Schema version 3
records the exact argv, an allowlisted environment, a caller-assigned run ID,
the per-candidate repetition ID, raw samples, and an explicit failure reason.
The verifier rejects store-path, environment, count, or provenance-shape
violations. For the narrowly defined `common-echo-literal-v1` fixture, every
candidate receives identical arguments to a builtin available in all three
shells and must return the exact expected
stdout, empty stderr, and exit status zero in preflight, every sample, and
postflight probes. Only a complete group with at least two candidates and two
repetitions is mechanically marked and verified as `ranking_eligible=true`.
Failures, partial groups, and semantic mismatches remain false.

No broad "world-fastest" claim is supportable from this minimal fixture alone.
Such a claim requires representative ranking-eligible fixtures together with
cold, warm, interactive, completion, and end-to-end tail latencies.

## Release Gates

Before a public release can claim world-level interactive-shell quality:

1. `nix flake check --print-build-logs` passes in x86_64-linux CI, and build/start
   smoke tests pass in x86_64-linux and aarch64-darwin CI.
2. The non-sandboxed integration suite passes for PTY, subprocess, terminal,
   signal, and job-control coverage.
3. Release artifacts for x86_64-linux and aarch64-darwin ship with
   `README.md`, `LICENSE`, and the `nshell(1)` man page, and pass the portable
   bundle validator without runtime `/nix/store` references.
4. Publication is a single global gate: neither platform is published until
   both native build, validation, and extracted-bundle smoke jobs pass. Each
   archive is published with a SHA-256 checksum and GitHub artifact attestation
   tied to the repository and release workflow. Release evidence is operational
   only after the published archive, checksum, and provenance attestation can be
   fetched and verified for every target.
5. User-visible behavior changes are represented in README, man page,
   CHANGELOG, and completion metadata when applicable.
6. Benchmark JSONL passes the schema verifier. Competitive ranking additionally
   requires `ranking_eligible=true` evidence from equivalent fixtures and
   candidate semantics under a controlled environment. Schema version 3 permits
   this only for complete, repeated groups that meet those constraints; the
   minimal fixture alone does not establish a broad "world-fastest" claim.
7. Open roadmap gaps remain explicit instead of being implied as complete.

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

# Coverage analysis: measured source coverage and the 100% target

The repository keeps the 100% target visible without claiming that it has been
reached. `scripts/coverage.lisp` runs the complete test system, generates an
`sb-cover` report, and publishes a machine-readable summary. The enforced
release gate is the configured minimum; the 100% value is an explicit target
that remains a warning until the report reaches it.

The production scope is the executable source under `src/`. Package
declarations are excluded from the denominator because loading a package is a
build prerequisite rather than shell behaviour. Static tables, macro
expansion forms, custom-constructor defaults, and foreign/PTY boundaries are
reported by `sb-cover` according to how SBCL instruments them; they are not
silently removed from the report.

## Reproduce

```sh
NSHELL_COVERAGE_DIR=/tmp/nshell-coverage \
  nix develop 'path:.' --command sbcl --script scripts/coverage.lisp
```

The command is release evidence only when the selected test count is non-zero,
the test and error counts are zero, the generated report exists, and both the
minimum and target fields have been inspected. A passing minimum with
`target-reached=false` is a warning, not a 100% coverage claim.

## What the suite verifies

- Unit and integration tests cover parsing, expansion, completion, environment,
  process, timeout, redirection, command dispatch, and job management.
- The weave suite exercises the completion knowledge base through property
  cases, fixtures, benchmarks, direct Prolog queries, and the `cl-prolog-kit/weave`
  bridge.
- PTY, terminal, and external-binary paths are verified by the PTY-capable
  runner. The Nix sandbox may skip those environment-dependent cases, so the
  local macOS and packaged Nix results must be reported separately.

## Remaining coverage categories

When a report still contains uncovered forms, classify them before adding a
test:

1. Reachable application or domain logic is a genuine test gap and should be
   covered with a value-level or boundary-injected test.
2. Load-time declarations and static data are structural forms; exercising a
   second load does not model shell behaviour.
3. A slot default made unreachable by an explicit BOA constructor is a
   constructor-design property, not an omitted runtime branch.
4. OS-specific syscall, signal, PTY, and interactive-terminal paths need the
   corresponding host boundary. Their tests must run against a real control
   object or a known-good injected boundary, never against state dirtied by the
   coverage probe itself.

The target can be raised to an enforced threshold only after the remaining
forms have been classified and the metric is stable across the declared
platforms. Until then, keep the raw report, the selected-test assertion, and
the minimum/target fields together in release verification.

## Latest local measurement

The current aarch64-darwin development environment selected 1573 tests and
passed all of them. The report covered 29590 of 32228 executable expressions
in 151 source files (91.81%); the configured 85% minimum passed, while the
100% target remained unmet. Reproduce it with:

```sh
coverage_dir=$(mktemp -d /tmp/nshell-coverage.XXXXXX) && \
  NSHELL_COVERAGE_DIR="$coverage_dir" \
  nix develop --command bash -lc \
  'perl -e '\''$SIG{ALRM}=sub { exit 124 }; alarm 900; exec @ARGV'\'' \
  sbcl --script scripts/coverage.lisp'
```

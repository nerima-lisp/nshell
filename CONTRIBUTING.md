# Contributing to nshell

Thanks for your interest in improving nshell! This document explains how to set
up your environment, the expectations for changes, and how to get a pull
request merged.

## Development environment

nshell is built with [SBCL](http://www.sbcl.org/) and ASDF, and the supported,
reproducible toolchain is [Nix](https://nixos.org/download) with flakes enabled.

```sh
git clone https://github.com/takeokunn/nshell
cd nshell
nix develop          # SBCL + FiveAM dev shell
nix build            # build ./result/bin/nshell
nix flake check --print-build-logs
```

Inside `nix develop` you can iterate in a REPL:

```lisp
(asdf:load-system :nshell)        ; load the shell
(asdf:test-system :nshell/test)   ; run the test suite
(nshell:main)                     ; start the shell
```

## Architecture

nshell follows a layered, domain-driven design (see the README for the diagram).
Please keep dependencies pointing inward:

- `domain/` is pure shell logic with **no I/O**. New parsing, expansion,
  completion, or history logic belongs here and should be unit-testable without
  a terminal.
- `infrastructure/` isolates all OS/SBCL-specific code (syscalls, PTY, signals,
  terminal). Guard implementation-specific code with `#+sbcl` where relevant.
- `application/` holds use cases (builtins, pipeline execution, job management).
- `presentation/` is the REPL, line editor, and rendering.

## Making changes

1. **Branch** off `main`.
2. **Add tests.** Every behavior change should come with FiveAM tests under
   `tests/` (unit, integration, property-based, or e2e as appropriate). Prefer
   testing pure domain logic directly.
3. **Keep tests hermetic.** Tests must not depend on the ambient working
   directory, terminal size, or environment. Use the provided fixtures (e.g.
   `with-stable-repl-prompt`, `with-fixed-terminal-size`) for rendering tests.
4. **Prefer the intended nshell semantics.** If a change intentionally diverges
   from POSIX, bash, zsh, fish, or nushell behavior, document the reason in the
   pull request and add regression coverage for the chosen semantics.
5. **Run `nix flake check`** locally — CI runs that hermetic gate on Linux and
   macOS, and a green check is required to merge. For PTY, subprocess,
   terminal, signal, or job-control changes, also run the non-sandboxed
   integration suite from the test-selection section.
6. **Update `CHANGELOG.md`** under `[Unreleased]`.
7. **Match the surrounding style** — naming, comment density, and idiom.

## Test selection

Use the narrowest test that can fail for your change while iterating, then run
the full suite before review:

```sh
nix develop -c sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(push (truename "./") asdf:*central-registry*)' \
  --eval '(asdf:test-system :nshell/test)'
```

For coverage-oriented validation, run:

```sh
nix develop -c sbcl --script scripts/coverage.lisp
```

For parser, expansion, execution, or builtin changes, include focused unit tests
and at least one integration or REPL/source test when behavior crosses layer
boundaries. For terminal, job-control, or process changes, state which operating
systems were verified.

## Quality expectations

- Parser and expansion behavior must be deterministic and covered by negative
  tests for ambiguous or invalid input.
- Builtins should return structured status and messages instead of terminating
  the process.
- Domain code must not perform I/O or depend on terminal state.
- Error messages should name the failing construct and avoid leaking secrets
  from environment values, command history, or paths beyond what the user typed.
- Documentation, man page text, and completion metadata should be updated with
  user-visible behavior changes.

## Commit & PR conventions

- Write focused commits with clear messages (imperative mood).
- Open a pull request describing the motivation and the user-visible effect.
- Link any related issue.

## Release checklist

Before tagging a release, verify the public artifacts from a clean checkout:

- `nix flake check --print-build-logs` passes on Linux and macOS.
- The non-sandboxed integration suite passes for PTY, subprocess, terminal,
  signal, and job-control coverage:

  ```sh
  nix develop --command sbcl --non-interactive \
    --eval '(require :asdf)' \
    --eval '(push (truename "./") asdf:*central-registry*)' \
    --eval '(asdf:test-system :nshell/test)'
  ```

- `nix build --print-build-logs` produces `./result/bin/nshell`.
- `./result/bin/nshell --version` reports the intended version.
- `./result/bin/nshell --help` and `man ./man/nshell.1` match the README and
  shipped behavior.
- If using a manual release workflow, the requested tag is used consistently
  for checkout, artifact naming, and the GitHub Release target; do not build a
  branch ref while publishing a tag release.
- Release tarballs contain `nshell`, `README.md`, and `LICENSE`, and each
  checksum verifies with `shasum -a 256 -c`.
- `CHANGELOG.md` has a non-empty entry for the release and no stale
  `[Unreleased]` claims about already-shipped behavior.

## Reporting bugs & requesting features

Please use GitHub Issues. For bugs, include:

- nshell version (`nshell --version`) or commit SHA.
- OS, architecture, terminal emulator, and whether you are inside tmux/screen.
- The smallest command sequence that reproduces the problem.
- Expected output, actual output, exit status, and any diagnostics.
- Whether the same input behaves differently in another shell.

For feature requests, describe the workflow you are trying to support and cite
the behavior you want nshell to own.

By contributing, you agree that your contributions are licensed under the
project's [MIT License](./LICENSE).

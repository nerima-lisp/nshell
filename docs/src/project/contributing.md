# Contributing to nshell

The process — branching, pull requests, commit conventions, and the org-wide
rules a review checks — lives in the
[nerima-lisp contributing guide](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md).
This page covers only what is specific to nshell.

## Keep dependencies pointing inward

nshell follows a layered, domain-driven design (see
[Architecture](../reference/architecture.md)). The layer rules are the ones a
review will actually push back on:

- **`domain/` performs no I/O.** New parsing, expansion, completion, or history
  logic belongs here and must be unit-testable without a terminal.
- **`infrastructure/` isolates all OS- and SBCL-specific code** — syscalls, PTY,
  signals, terminal handling, persistence. Guard implementation-specific code
  with `#+sbcl` where relevant.
- **`application/` holds use cases** — builtins, pipeline execution, job
  management.
- **`presentation/` is the REPL, line editor, and rendering.**

## Choose the narrowest test that can fail

Iterate with the smallest relevant suite, then run the full gate before review.

| Change | Run |
|---|---|
| Anything | `nix flake check --print-build-logs` before review |
| Domain logic, builtins, parser, expansion | `nix run .#test` |
| Completion engine or cl-prolog knowledge base | `sbcl --script scripts/weave.lisp` |
| PTY, subprocess, terminal, signal, job control | the non-sandboxed run below |
| Coverage-oriented validation | `nix develop -c sbcl --script scripts/coverage.lisp` |

The non-sandboxed integration run, for changes the Nix sandbox cannot exercise:

```sh
nix develop -c sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(push (truename "./") asdf:*central-registry*)' \
  --eval '(asdf:test-system :nshell/test)'
```

Tests live in `t/` and must be hermetic: no dependence on the ambient working
directory, terminal size, or environment. Use the provided fixtures — for
example `with-stable-repl-prompt` and `with-fixed-terminal-size` — for
rendering tests.

For parser, expansion, execution, or builtin changes, include focused unit
tests plus at least one integration or REPL/source test when behaviour crosses
a layer boundary. For terminal, job-control, or process changes, state which
operating systems were verified.

## Quality expectations

- Parser and expansion behaviour must be deterministic, and covered by negative
  tests for ambiguous or invalid input.
- Builtins return a structured status and message instead of terminating the
  process.
- Domain code performs no I/O and does not depend on terminal state.
- Error messages name the failing construct, and must not leak secrets from
  environment values, command history, or paths beyond what the user typed.
- Documentation, man page text, and completion metadata are updated alongside
  user-visible behaviour changes.

## Diverging from other shells deliberately

If a change intentionally diverges from POSIX, bash, zsh, fish, or nushell
behaviour, document the reason in the pull request and add regression coverage
pinning the chosen semantics. An undocumented divergence reads as a bug to the
next person.

## Reporting bugs

Use GitHub Issues, and include:

- nshell version (`nshell --version`) or commit SHA.
- OS, architecture, terminal emulator, and whether you are inside tmux or
  screen.
- The smallest command sequence that reproduces the problem.
- Expected output, actual output, exit status, and any diagnostics.
- Whether the same input behaves differently in another shell.

For feature requests, describe the workflow you are trying to support and the
behaviour you want nshell to own.

## Reporting a vulnerability

Report privately through the org
[security policy](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md),
never as a public issue. Redact environment values and command history unless
they are required to reproduce.

In scope for nshell specifically:

- Command injection or unintended command execution caused by parsing,
  expansion, completion, or source-file handling.
- Secret disclosure through history, diagnostics, completion candidates, or
  crash output.
- Unsafe filesystem access caused by redirection, path handling, or builtin
  behaviour.
- Terminal escape handling that can mislead the user or corrupt visible output.
- Process, signal, or job-control behaviour that breaks expected user
  isolation.

Usually out of scope: vulnerabilities in the host OS, terminal emulator, SBCL,
or third-party tools unless nshell makes them directly exploitable;
denial-of-service cases requiring intentionally unbounded local resource
consumption without crossing a security boundary; and reports without a
plausible nshell impact.

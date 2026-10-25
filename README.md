# nshell

[![CI](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/nshell/)

nshell is an interactive shell written in Common Lisp for SBCL. Its command
language uses S-expressions, with ordinary command lines as shorthand. In a
parenthesized form, a head that resolves to a Common Lisp form is evaluated as
Lisp; otherwise the form names a shell command. Inside a command form, `$NAME`
passes a shell variable's value and `,EXPR` evaluates an expression for an
argument.

> **Status: development preview.** CI runs the Nix test suite on
> `x86_64-linux` and `aarch64-darwin`; real-PTY integration runs on
> `x86_64-linux`. Bare command lines are entry syntax, not a promise of POSIX
> or fish script compatibility. The `-c` option delegates to `/bin/sh`.

Documentation source lives in [docs/src/](docs/src/).

## Quick Start

With [Nix](https://nixos.org/download) and flakes enabled, run the current
default branch:

```sh
nix --extra-experimental-features 'nix-command flakes' \
  run github:nerima-lisp/nshell
```

At the prompt, enter an S-expression that calls a command and evaluates an
arithmetic form:

```
~/src/nshell main ❯ (echo ,(+ 2 3))
5
```

Bare command lines remain available for commands that do not need Lisp values:

```
~/src/nshell main ❯ echo hello
hello
```

On bare interactive command lines, history expansion supports `!!`, `!$`,
`!-N`, `!?text?`, and `!prefix`; exclamation marks inside single quotes or
preceded by a backslash remain literal. S-expression input does not expand
these history designators. Press `Alt-E` to edit the current command in the
configured editor, then press Enter in nshell to execute the edited line. See
[History expansion](docs/src/guide/concepts.md#history-expansion-is-explicit)
for the expansion forms.

History is stored at `$XDG_DATA_HOME/nshell/history` when `XDG_DATA_HOME` is
an absolute path, or at `~/.local/share/nshell/history` otherwise.
`--no-history` disables history reads and writes, including in-session
recording. In an interactive session, `--private` keeps existing history
available without saving that session's commands. It also suppresses local
assistant transcript, snapshot, and audit persistence.

The interactive startup file is `$XDG_CONFIG_HOME/nshell/init.lisp` when
`XDG_CONFIG_HOME` is absolute, or `~/.config/nshell/init.lisp` otherwise.
Use `--config PATH` to select another file or `--no-config` to skip loading
the startup file. When the default path is used, the legacy `~/.nshellrc` is
ignored with a one-line notice.

The interactive `agent` builtin proposes commands for review. Every proposal,
including one classified as safe, requires Enter before execution; blocked
commands cannot be approved. The assistant refuses to start unless it has no
tools or only `StructuredOutput`, and no MCP servers. See
[Use the assistant](docs/src/guide/recipes.md#use-the-assistant) for controls
and session settings.

## Install

```sh
nix profile install github:nerima-lisp/nshell
```

The current documentation describes the default branch. The `v0.6.6` release
predates this S-expression command language.

## Documentation

- [Getting started](https://nerima-lisp.github.io/nshell/getting-started/)
- [Core concepts](https://nerima-lisp.github.io/nshell/guide/concepts/)
- [Built-in commands](https://nerima-lisp.github.io/nshell/reference/builtins/)
- [Architecture](https://nerima-lisp.github.io/nshell/reference/architecture/)

## Development

Start an interactive development shell with:

```sh
nix develop
```

The command examples below use Bash or zsh syntax. If `nix develop` opens fish,
start Bash inside that shell before running them. Run individual checks from
the development shell or another Bash or zsh shell with Nix and flakes enabled:

```sh
perl -e 'alarm 300; exec @ARGV' nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').default --no-link  # run the test suite
perl -e 'alarm 300; exec @ARGV' nix flake check      # time-limited local hermetic check
nix fmt              # format Nix sources (treefmt)
nix build            # produces ./result/bin/nshell
nix build .#releaseBundle
perl scripts/verify-release-bundle.pl result
perl scripts/test-release-pty.pl result
```

The Perl wrappers send `SIGALRM` to each local check after five minutes.
This is not the full CI gate's time limit; see
[Recipes](docs/src/guide/recipes.md#run-the-test-suite) for that command.
The bundle checks run on Linux and require Perl, Python 3, `readelf`, and
standard POSIX tools.

Run source-loaded integration, dependency, and history checks with the
[isolated HOME and XDG procedure](docs/src/project/public-readiness.md#verification-outside-ci)
to avoid reading or modifying personal history and configuration.

To measure executable-source coverage, keep the report outside the checkout
and use the isolated HOME and XDG procedure above with this command:

```sh
NSHELL_COVERAGE_DIR="$(mktemp -d)" \
  nix develop -c sbcl --script scripts/coverage.lisp
```

The command writes `coverage-summary.json` and `coverage-files.json` to the
selected directory. These reports cover executable source under `src/`,
excluding declarative data and package-definition files. The default minimum
is 85% (`NSHELL_COVERAGE_MIN`); the target is 100%
(`NSHELL_COVERAGE_TARGET`).

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave).
Cases needing a real PTY, `stty`, or external binaries cannot run in the Nix
sandbox and are covered by CI's separate `integration` job; run them locally
with the command in
[Recipes](https://nerima-lisp.github.io/nshell/guide/recipes/).

Benchmark commands and evidence boundaries are documented in
[Performance evidence](https://nerima-lisp.github.io/nshell/guide/recipes/#performance-evidence).

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).
Report vulnerabilities privately per this repository's
[security policy](SECURITY.md) rather than a public issue.

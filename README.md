# nshell

[![CI](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/nshell/)

nshell is a fish-inspired interactive shell written in Common Lisp for SBCL.
It provides syntax highlighting, history-aware autosuggestions, abbreviations,
and context-aware completion.

> **Status: development preview (0.6.x).** CI tests the interactive editor and
> pipeline execution on `x86_64-linux`. The shell language implements a subset
> of POSIX/fish semantics; it is not a script-compatible `/bin/sh` replacement.

Documentation source lives in [docs/src/](docs/src/).

## Quick Start

The release and Nix flake support `x86_64-linux` only. With
[Nix](https://nixos.org/download) and flakes enabled:

```sh
nix run github:nerima-lisp/nshell/v0.6.1
```

Then type as you would in any shell. Commands and paths colorize live, and a
dimmed completion of the most recent matching history entry trails the cursor;
press `→` or `Ctrl-F` to accept it:

```
~/src/nshell main ❯ string upper hello
HELLO
```

After running that command, type `string up` to see `per hello` suggested
from history.

Colors come from a theme; run `theme list` to see the built-in presets and
`theme use dracula` (or any other name from that list) to switch, live, with
no restart needed.

Interactive history expansion supports `!!`, `!$`, `!-N`, `!?text?`, and
`!prefix`; exclamation marks inside single quotes or preceded by a backslash
remain literal. Press `Alt-E` to edit the current command in the editor named
by `NSHELL_EDITOR`, `VISUAL`, or `EDITOR` (falling back to `vi`), then return
the edited line to nshell.

History is stored in `~/.nshell_history` with owner-only permissions. Symlinks,
hard links, and files owned by another user are rejected. A malformed tail is
reported without discarding existing bytes; further appends are refused until
the file is moved aside. `--no-history` disables persistence.

## Install

```sh
nix profile install github:nerima-lisp/nshell/v0.6.1
```

Pin a release tag rather than following the default branch.

The `x86_64-linux` release bundle removes Nix store references, carries its
ELF runtime library closure, and is checked for required files and dependency
metadata. CI checks an extracted archive and exercises its executable with a
real PTY, including editing, signals, job control, history restart, and terminal
restoration. See [Getting
started](https://nerima-lisp.github.io/nshell/getting-started/) for the bundle
verification and installation procedure.

## Documentation

- [Getting started](https://nerima-lisp.github.io/nshell/getting-started/)
- [Core concepts](https://nerima-lisp.github.io/nshell/guide/concepts/)
- [Built-in commands](https://nerima-lisp.github.io/nshell/reference/builtins/)
- [Architecture](https://nerima-lisp.github.io/nshell/reference/architecture/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set (x86_64-linux)
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 300; exec @ARGV' nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').default --no-link  # run the test suite
perl -e '$SIG{ALRM}=sub { exit 124 }; alarm 300; exec @ARGV' nix flake check      # time-limited local hermetic check
nix fmt              # format Nix sources (treefmt)
nix build            # produces ./result/bin/nshell
nix build .#releaseBundle
perl scripts/verify-release-bundle.pl result
perl scripts/test-release-pty.pl result
```

The Perl wrappers limit each local check to five minutes and return exit code
124 if that limit expires. This is not the full CI gate's time limit; see
[Recipes](docs/src/guide/recipes.md#run-the-test-suite) for that command.
The bundle checks run on Linux and require Perl, Python 3, `readelf`, and
standard POSIX tools.

Run source-loaded integration, dependency, and history checks with the
[isolated HOME and XDG procedure](docs/src/project/public-readiness.md#verification-outside-ci)
to avoid reading or modifying personal history and configuration.

To measure executable-source coverage, keep the report outside the checkout
and run the same hermetic test loader used by CI:

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

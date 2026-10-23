# nshell

[![CI](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/nshell/)

nshell is a fish-inspired interactive shell written in Common Lisp for SBCL.
It provides syntax highlighting, history-aware autosuggestions, abbreviations,
and context-aware completion.

> **Status: development preview (0.6.x).** CI runs the Nix test suite on
> `x86_64-linux` and `aarch64-darwin`; real-PTY integration runs on
> `x86_64-linux`. The shell language implements a subset of POSIX/fish
> semantics; it is not a script-compatible `/bin/sh` replacement.

Documentation source lives in [docs/src/](docs/src/).

## Quick Start

`nix run` builds from the flake on `x86_64-linux` and `aarch64-darwin`;
downloadable release bundles target `x86_64-linux` only. With
[Nix](https://nixos.org/download) installed, run this command. It enables the
required Nix features for this invocation:

```sh
nix --extra-experimental-features 'nix-command flakes' \
  run github:nerima-lisp/nshell/v0.6.6
```

At the prompt, enter `string upper hello`. Commands and paths colorize live, and a
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
the edited line to nshell. Save and quit the editor, then press Enter in nshell
to execute it. See [History expansion](docs/src/guide/concepts.md#history-expansion-is-explicit)
for the expansion forms.

History is stored in `$XDG_DATA_HOME/nshell/history` when `XDG_DATA_HOME` is an
absolute path, or `~/.local/share/nshell/history` otherwise. If that file does
not exist, nshell imports legacy records from `~/.nshell_history` and leaves
the source file unchanged. Imported command text is deduplicated, and later
starts read the new file instead of importing again. History files have
owner-only permissions. Symlinks, hard links, nonregular files, and files
owned by another user are rejected. Malformed or truncated records are
reported. The reader keeps valid records before damaged data and resumes at
the next valid record frame when it finds one. On the next successful append,
nshell repairs the file with valid unique records, adds the command if it is
not already present, and discards damaged bytes.

The interactive startup file is `$XDG_CONFIG_HOME/nshell/init.lisp` when
`XDG_CONFIG_HOME` is an absolute path, or `~/.config/nshell/init.lisp`
otherwise. `--config PATH` selects another file, and `--no-config` skips it.
When using the default path, the legacy `~/.nshellrc` is ignored with a
one-line notice.

Use `--no-history` to disable history reads and writes, including in-session
history recording. In an interactive session with history reads enabled,
`--private` keeps existing history available but does not save that session's
commands. It also suppresses local assistant transcript, snapshot, and audit
persistence.

The interactive `agent` builtin proposes commands for review. Every proposal,
including one classified as safe, requires Enter before execution; blocked
commands cannot be approved. Its configuration sidecar must report only the
`StructuredOutput` tool (or no tools) and no MCP servers, or the assistant
refuses to start. See
[Use the assistant](docs/src/guide/recipes.md#use-the-assistant) for controls
and session settings.

## Install

```sh
nix profile install github:nerima-lisp/nshell/v0.6.6
```

Pin a release tag rather than following the default branch.

To install without Nix, use the `x86_64-linux` release bundle. It removes Nix store references, carries its
ELF runtime library closure, and is checked for required files and dependency
metadata. CI checks an extracted archive and exercises its executable with a
real PTY, including multiline editing and paste, completion with spaces,
signals, job control, resize, history restart, and terminal restoration. See [Getting
started](https://nerima-lisp.github.io/nshell/getting-started/) for the bundle
verification and installation procedure.

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

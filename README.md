# nshell

[![CI](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/nshell/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/nshell/)

nshell is a modern, fish-inspired interactive shell written in Common Lisp for
SBCL. It puts the *interactive* experience first — real-time syntax
highlighting, history-aware autosuggestions, fish-style abbreviations, and a
context-aware completion engine driven by a logic knowledge base — on top of a
domain-driven core whose line editor is a pure reducer over an immutable input
state, and a reproducible Nix build that ships as a single dumped SBCL image.

> **Status: development preview (0.4.x).** The interactive editor and core
> pipeline execution are solid and heavily tested. The shell *language* is a
> growing subset of POSIX/fish semantics. nshell is usable as a daily
> interactive shell for common workflows; it is not a script-compatible
> `/bin/sh` replacement.

Full documentation is published at <https://nerima-lisp.github.io/nshell/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

```sh
nix run github:nerima-lisp/nshell/v0.4.0
```

Then type as you would in any shell. Commands and paths colorize live, and a
dimmed completion of the most recent matching history entry trails the cursor —
press `→` or `Ctrl-F` to accept it:

```
~/src/nshell> git com                    # "mit -m " suggested from history
~/src/nshell> string upper hello
HELLO
```

Interactive history expansion supports `!!`, `!$`, `!-N`, `!?text?`, and
`!prefix`; exclamation marks inside single quotes or preceded by a backslash
remain literal. Press `Alt-E` to edit the current command in the editor named
by `NSHELL_EDITOR`, `VISUAL`, or `EDITOR` (falling back to `vi`), then return
the edited line to nshell.

## Install

```sh
nix profile install github:nerima-lisp/nshell/v0.4.0
```

```nix
# flake.nix
inputs.nshell = {
  url = "github:nerima-lisp/nshell/v0.4.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Pin a release tag rather than following the default branch. The supported
platforms are `x86_64-linux` and `aarch64-darwin`; other systems are currently
outside the tested support boundary.

> **Release artifact warning:** the tarballs attached to `v0.4.0` are not
> portable and can retain Nix store dependencies. No portable binary release
> has been published yet. Use the pinned Nix commands above until a later
> release explicitly identifies its bundles as portable. See
> [Getting started](https://nerima-lisp.github.io/nshell/getting-started/)
> for the future bundle verification and installation procedure.

## Documentation

- [Getting started](https://nerima-lisp.github.io/nshell/getting-started/)
- [Core concepts](https://nerima-lisp.github.io/nshell/guide/concepts/)
- [Built-in commands](https://nerima-lisp.github.io/nshell/reference/builtins/)
- [Architecture](https://nerima-lisp.github.io/nshell/reference/architecture/)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').default --no-link  # run the test suite
nix flake check      # full hermetic gate on x86_64-linux CI
nix fmt              # format Nix sources (treefmt)
nix build            # produces ./result/bin/nshell
nix build .#releaseBundle
perl scripts/verify-release-bundle.pl result
```

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave), the org's test framework.
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

## License

MIT. See [LICENSE](LICENSE).

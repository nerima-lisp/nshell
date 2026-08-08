# Getting started

## Run without installing

With [Nix](https://nixos.org/download) (flakes enabled):

```sh
nix run github:nerima-lisp/nshell/v0.4.0
```

## Install

```sh
nix profile install github:nerima-lisp/nshell/v0.4.0
nshell
man nshell   # the manual page is installed alongside the binary
```

Consumers inside the nerima-lisp org pin a release tag rather than following
the default branch:

```nix
# flake.nix
inputs.nshell = {
  url = "github:nerima-lisp/nshell/v0.4.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Supported platforms

| Platform | Support boundary |
| --- | --- |
| `x86_64-linux` | Supported target; release evidence must come from native Linux CI. |
| `aarch64-darwin` | Supported target; release evidence must come from native macOS CI. |

`aarch64-linux`, `x86_64-darwin`, other operating systems, and other CPU
architectures are not currently supported release targets. Source builds may
work elsewhere, but they are not covered by the project's release guarantees.

!!! warning "The v0.4.0 tarballs are not portable"

    The artifacts already attached to `v0.4.0` can retain Nix store runtime
    dependencies. They are not portable binary distributions and are not being
    replaced retroactively. No portable binary release has been published yet;
    use the pinned Nix installation above.

### Installing a future portable bundle

Use this procedure only for a future release whose notes explicitly call its
bundle portable. Replace `vX.Y.Z` and the target with values from that release:

```sh
TAG=vX.Y.Z
TARGET=x86_64-linux             # or aarch64-darwin
ARCHIVE="nshell-${TAG}-${TARGET}.tar.gz"

gh release download "$TAG" --repo nerima-lisp/nshell \
  --pattern "$ARCHIVE" --pattern "$ARCHIVE.sha256"
shasum -a 256 -c "$ARCHIVE.sha256"
gh attestation verify "$ARCHIVE" --repo nerima-lisp/nshell

tar -xzf "$ARCHIVE"
mkdir -p "$HOME/.local/opt/nshell-${TAG}" "$HOME/.local/bin"
cp -R "nshell-${TAG}-${TARGET}/." "$HOME/.local/opt/nshell-${TAG}/"
ln -sfn "$HOME/.local/opt/nshell-${TAG}/bin/nshell" \
  "$HOME/.local/bin/nshell"
```

Keep the extracted bundle directory intact. The launcher supports this
symlinked installation and resolves its runtime files from the bundle that
contains the real executable.

The checksum detects a corrupted download. `gh attestation verify` separately
checks the GitHub artifact attestation and its repository identity; do not skip
either check. The attestation command is expected to succeed only when that
future release publishes provenance for the archive. Ensure
`$HOME/.local/bin` is on `PATH`, then run `nshell --version`.

## First commands

Start nshell and type as you would in any shell. The distinguishing behaviour
shows up while typing: commands and paths colorize live, and a dimmed
completion of the most recent matching history entry trails the cursor. Press
`→` or `Ctrl-F` to accept it.

### One-off command

```sh
nshell -c 'echo hello | string upper'
```

### Run a script

```sh
nshell examples/greet.nsh World
```

Script files support multiline blocks (functions, `if`/`for`/`while`/`switch`),
comments, and a `#!` shebang; arguments after the script name are available as
`$argv`. See
[`examples/`](https://github.com/nerima-lisp/nshell/tree/main/examples) for a
runnable sample.

### Command line

```
Usage: nshell [--help] [--version] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]

Without arguments, nshell starts an interactive shell when stdin is a terminal
and reads batch input from stdin otherwise.
With -c/--command, nshell executes COMMAND once in batch mode; trailing ARGS
are available as $argv.
With SCRIPT, nshell runs the script file; trailing ARGS are available as $argv.
```

## Build from source

nshell builds with [SBCL](http://www.sbcl.org/) and ASDF. The supported and
tested path is Nix:

```sh
git clone https://github.com/nerima-lisp/nshell
cd nshell
nix build            # produces ./result/bin/nshell
nix flake check      # tests + formatting + docs, the same gate CI uses
nix develop          # dev shell with SBCL + cl-weave
```

Inside `nix develop`, load the system into a REPL:

```lisp
(asdf:load-system "nshell")
(nshell:main)
```

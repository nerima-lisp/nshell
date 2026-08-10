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

The release workflow currently publishes an `x86_64-linux` tarball and SHA-256
checksum. Check the [GitHub releases](https://github.com/nerima-lisp/nshell/releases)
page before downloading: the `v0.4.0` artifacts are not portable and may retain
Nix store dependencies. For reproducible installation, use the pinned Nix
commands above.

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
nix flake check      # full hermetic gate on x86_64-linux CI
nix develop          # dev shell with SBCL + cl-weave
```

`flake.nix` declares `x86_64-linux` and `aarch64-darwin`. The full hermetic
flake and release-binary gate runs on `x86_64-linux`; `aarch64-darwin` is the
development and non-sandboxed integration target, and some build checks can be
unavailable there when a pinned upstream package has no Darwin build.

Inside `nix develop`, load the system into a REPL:

```lisp
(asdf:load-system "nshell")
(nshell:main)
```

# Getting started

The release and Nix flake support `x86_64-linux` only. Other systems are
outside the tested support boundary.

## Run without installing

Install [Nix](https://nixos.org/download) and enable its `nix-command` and
`flakes` experimental features before running:

```sh
nix run github:nerima-lisp/nshell/v0.6.2
```

## Install

```sh
nix profile install github:nerima-lisp/nshell/v0.6.2
man nshell   # the manual page is installed alongside the binary
nshell
```

Pin a release tag rather than following the default branch. Type `exit` to
leave the interactive shell.

### Prebuilt Linux bundle

Without Nix, download both assets from the
[v0.6.2 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.2),
verify the checksum, and extract the bundle. On `x86_64-linux`, with `curl`,
`sha256sum`, and `tar` available, run these commands in an empty directory:

```sh
curl --fail --location --remote-name https://github.com/nerima-lisp/nshell/releases/download/v0.6.2/nshell-v0.6.2-x86_64-linux.tar.gz
curl --fail --location --remote-name https://github.com/nerima-lisp/nshell/releases/download/v0.6.2/nshell-v0.6.2-x86_64-linux.tar.gz.sha256
sha256sum --check nshell-v0.6.2-x86_64-linux.tar.gz.sha256
```

Proceed only if the checksum command exits successfully and prints
`nshell-v0.6.2-x86_64-linux.tar.gz: OK`:

```sh
tar -xzf nshell-v0.6.2-x86_64-linux.tar.gz
./nshell-v0.6.2-x86_64-linux/bin/nshell --version
man ./nshell-v0.6.2-x86_64-linux/share/man/man1/nshell.1
./nshell-v0.6.2-x86_64-linux/bin/nshell
```

Keep the extracted directory intact: the launcher resolves libraries and
helpers relative to itself. The version output must identify `v0.6.2`.
Type `exit` to return to your existing shell. To use `nshell` by name in
the examples below, add the extracted `bin` directory to that shell's
`PATH`. For Bash or Zsh, from the download directory:

```sh
export PATH="$PWD/nshell-v0.6.2-x86_64-linux/bin:$PATH"
```

This changes only the current terminal session. Alternatively, replace
`nshell` in the examples with the full path to the extracted launcher.

The release bundle removes Nix store references, carries its ELF runtime
library closure, and is checked for required files and dependency metadata. CI
also runs `--help`, `--version`, and an `echo` smoke test on the bundle. The
checksum detects a mismatch with the published asset; it is not a provenance
attestation.

## First commands

Start nshell with `nshell`. The prompt shows the
working directory, the git branch (with `*` when the tree is dirty), and a
`❯` that turns red after a failing command. The right prompt shows a failing
exit code, the duration of commands that took at least one second, and the
current time when the prompt is rendered. The distinguishing
behaviour shows up while typing: commands colorize live (an unknown command
turns red before you run it), existing paths are underlined, and a dimmed
completion of the most recent matching history entry trails the cursor. Press
`→` or `Ctrl-F` to accept it. A mistyped command gets a `did you mean`
suggestion, `FOO=bar printenv FOO` prints `bar` without keeping `FOO` in the
shell environment, and `theme list`
shows the color presets. The prompt layout, the colors, and the key
bindings are all configurable; see [Customization](guide/customization.md).

Set `NSHELL_GREETING` to replace the startup banner with your own line, or to
the empty string to start silently. If you want to make this persistent,
create the optional `~/.nshellrc` startup file and add
`set -x NSHELL_GREETING ""`.

### One-off command

```sh
nshell -c 'string upper hello'
```

### Run a script

```sh
curl --fail --location --output greet.nsh https://raw.githubusercontent.com/nerima-lisp/nshell/v0.6.2/examples/greet.nsh
nshell greet.nsh World
```

Script files support multiline blocks (functions, `if`/`for`/`while`/`switch`),
comments, and a `#!` shebang; arguments after the script name are available as
`$argv`. See
[`examples/`](https://github.com/nerima-lisp/nshell/tree/v0.6.2/examples) for a
runnable sample.

### Command line

```
Usage: nshell [OPTIONS] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]

Without arguments, nshell starts an interactive shell when stdin is a terminal
and reads batch input from stdin otherwise.
With -c/--command, nshell executes COMMAND once in batch mode; trailing ARGS
are available as $argv.
With SCRIPT, nshell runs the script file; trailing ARGS are available as $argv.

Options:
  -i, --interactive  Force the interactive line editor.
      --no-config    Do not load the interactive startup file.
      --config PATH  Load PATH instead of ~/.nshellrc.
      --no-history   Do not read or write interactive history.
  -h, --help          Show usage and exit.
  -V, --version       Show version and exit.
```

## Build from source

The Nix build supplies [SBCL](http://www.sbcl.org/), ASDF, and the dependencies.
On `x86_64-linux`, with Git and flake-enabled Nix installed:

```sh
git clone --branch v0.6.2 https://github.com/nerima-lisp/nshell
cd nshell
nix build
./result/bin/nshell
```

For the development shell and test commands, see
[Recipes](guide/recipes.md#run-the-test-suite).

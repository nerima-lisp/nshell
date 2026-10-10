# Getting started

The release and Nix flake support `x86_64-linux` only. Other systems are
outside the tested support boundary.

## Run without installing

With [Nix](https://nixos.org/download) (flakes enabled):

```sh
nix run github:nerima-lisp/nshell/v0.6.1
```

## Install

```sh
nix profile install github:nerima-lisp/nshell/v0.6.1
nshell
man nshell   # the manual page is installed alongside the binary
```

Pin a release tag rather than following the default branch.

### Prebuilt Linux bundle

Without Nix, download both assets from the
[v0.6.1 release](https://github.com/nerima-lisp/nshell/releases/tag/v0.6.1),
verify the checksum, and extract the bundle. On `x86_64-linux`, with `curl`,
`sha256sum`, and `tar` available, run these commands in an empty directory:

```sh
curl --fail --location --remote-name https://github.com/nerima-lisp/nshell/releases/download/v0.6.1/nshell-v0.6.1-x86_64-linux.tar.gz
curl --fail --location --remote-name https://github.com/nerima-lisp/nshell/releases/download/v0.6.1/nshell-v0.6.1-x86_64-linux.tar.gz.sha256
sha256sum --check nshell-v0.6.1-x86_64-linux.tar.gz.sha256
```

Proceed only if the checksum command succeeds:

```sh
tar -xzf nshell-v0.6.1-x86_64-linux.tar.gz
./nshell-v0.6.1-x86_64-linux/bin/nshell --version
./nshell-v0.6.1-x86_64-linux/bin/nshell
man ./nshell-v0.6.1-x86_64-linux/share/man/man1/nshell.1
```

Keep the extracted directory intact: the launcher resolves libraries and
helpers relative to itself. To invoke `nshell` by name, add its `bin`
directory to your existing shell's `PATH`.

The release workflow publishes an `x86_64-linux` tarball and SHA-256 checksum.
The release bundle removes Nix store references, carries its ELF runtime
library closure, and is checked for required files and dependency metadata. CI
also runs `--help`, `--version`, and an `echo` smoke test on the bundle. The
checksum detects a mismatch with the published asset; it is not a provenance
attestation.

## First commands

Start nshell and type as you would in any shell. The prompt shows the
working directory, the git branch (with `*` when the tree is dirty), and a
`❯` that turns red after a failing command; the last exit code and any
command that took a second or more appear on the right. The distinguishing
behaviour shows up while typing: commands colorize live (an unknown command
turns red before you run it), existing paths are underlined, and a dimmed
completion of the most recent matching history entry trails the cursor. Press
`→` or `Ctrl-F` to accept it. A mistyped command gets a `did you mean`
suggestion, `FOO=bar cmd` exports `FOO` for that one command, and `theme list`
shows the color presets. The prompt layout, the colors, and the key
bindings are all configurable; see [Customization](guide/customization.md).

Set `NSHELL_GREETING` to replace the startup banner with your own line, or to
the empty string to start silently. It is read after `~/.nshellrc` runs, so
`set -x NSHELL_GREETING ""` in that file works.

### One-off command

```sh
nshell -c 'string upper hello'
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

nshell builds with [SBCL](http://www.sbcl.org/) and ASDF. The supported and
tested path is Nix:

```sh
git clone https://github.com/nerima-lisp/nshell
cd nshell
nix build            # produces ./result/bin/nshell
nix flake check      # full hermetic gate on x86_64-linux CI
nix develop          # dev shell with SBCL + cl-weave
```

`flake.nix` declares `x86_64-linux` only. The full hermetic flake gate, the
release-binary gate, and the non-sandboxed integration suite run in CI on that
target. A remote `x86_64-linux` builder can build the artifacts from another
host, but running the dev shell or the non-sandboxed PTY suite requires an
`x86_64-linux` execution environment.

Inside `nix develop`, load the system into a REPL:

```lisp
(asdf:load-system "nshell")
(nshell:main)
```

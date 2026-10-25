# Getting started

The current documentation describes the default branch. The `v0.6.6` release
predates the S-expression command language described here.

## Run with Nix

The flake builds on Apple Silicon macOS (`aarch64-darwin`) and x86-64 Linux
(`x86_64-linux`). It does not declare an Intel macOS target. The latest
published `v0.6.6` bundle is for x86-64 Linux and predates the S-expression
language described here; use the Nix commands below to build the current
default branch.

Install [Nix](https://nixos.org/download) with the `nix-command` and `flakes`
features enabled, then run the default branch:

```sh
nix --extra-experimental-features 'nix-command flakes' run github:nerima-lisp/nshell
```

To install it in your user profile instead, run:

```sh
nix --extra-experimental-features 'nix-command flakes' profile install github:nerima-lisp/nshell
```

Type `exit` to return to your existing shell.

## Enter an expression or a command

At the prompt, an input beginning with `(` is read as an S-expression. A form
whose head names a Common Lisp form is evaluated as Lisp. Otherwise, the form
is a shell command. Use `$NAME` to pass a shell variable's value and `,EXPR`
to evaluate an expression for a command argument.

```text
nshell> (echo ,(+ 2 3))
5
nshell> echo hello
hello
```

Bare command lines keep the usual shape for simple commands and support
redirection and byte-stream pipelines. See [Core concepts](guide/concepts.md)
for the S-expression and pipeline rules.

The editor highlights command names and paths as you type. It also suggests
history entries; press `→` or `Ctrl-F` to accept a suggestion. Run
`theme use nord` to select the Nord theme.
See [Customization](guide/customization.md) for prompt, theme, and editing-key
settings.

History expansion is available on bare interactive command lines. `!!`, `!$`,
`!-N`, `!?text?`, and `!prefix` refer to recent commands. S-expression input
does not expand these designators. See
[History expansion](guide/concepts.md#history-expansion-is-explicit).

## Run one command

`--command` sends one command to nshell, where bare command-line sugar is
accepted. `-c` and `--shell-command` instead delegate to `/bin/sh`; use them
when a caller expects shell-command behavior.

## Configure the interactive session

The interactive startup file is `$XDG_CONFIG_HOME/nshell/init.lisp` when
`XDG_CONFIG_HOME` is an absolute path, or `~/.config/nshell/init.lisp`
otherwise. Use `--config PATH` to select another file or `--no-config` to skip
it. The file can contain nshell commands, including theme selection and hook
registration. When the default path is used, the legacy `~/.nshellrc` is
ignored with a one-line notice. If the startup file has a syntax error, nshell
reports it and continues to the prompt.

Use `--no-history` to disable history reads and writes. `--private` keeps
existing history available in an interactive session without saving that
session's commands. It also suppresses local assistant transcript, snapshot,
and audit persistence.

## Build from source

The flake supplies SBCL, ASDF, and the project's dependencies. Clone the
repository and run the binary produced by Nix:

```sh
git clone https://github.com/nerima-lisp/nshell
cd nshell
nix build
./result/bin/nshell
```

For development commands and verification procedures, see
[Recipes](guide/recipes.md).

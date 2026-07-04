# nshell

**A modern, fish-inspired interactive shell written in Common Lisp.**

[![CI](https://github.com/takeokunn/nshell/actions/workflows/ci.yml/badge.svg)](https://github.com/takeokunn/nshell/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Built with Nix](https://img.shields.io/badge/built%20with-nix-5277C3.svg?logo=nixos&logoColor=white)](https://nixos.org)

nshell is an interactive shell that puts the *interactive* experience first:
real-time syntax highlighting, history-aware autosuggestions, fish-style
abbreviations, and a fast, context-aware completion engine — all built on a
clean, test-driven Common Lisp core (5,800+ checks) and a reproducible Nix
build.

> **Status: early development (0.4.x).** The interactive editor and core
> pipeline execution are solid and heavily tested. The shell *language* is a
> growing subset of POSIX/fish semantics — see [Roadmap](#roadmap) for what is
> and isn't supported yet. nshell is usable as a daily interactive shell for
> common workflows; it is not yet a drop-in `/bin/sh` replacement for scripts.

---

## Highlights

- **Syntax highlighting** as you type — commands, strings, operators, and paths
  are colorized live.
- **Autosuggestions** from your history, fish-style, accepted with `→` / `Ctrl-F`.
- **Abbreviations** (`abbr`) that expand inline as you type — keep your muscle
  memory, type less.
- **Context-aware completion** — a knowledge base of commands/flags plus
  filesystem completion, with common-prefix `Tab` extension and a candidate menu.
- **Rich line editing** — Emacs keybindings, kill-ring & yank, multi-level
  undo/redo, multiline editing, and incremental history search (`Ctrl-R`).
  Optional **vi key bindings** (`NSHELL_VI_MODE=1`): normal-mode motions,
  counts, operators (`dd`, `cw`, …), visual selection, and insert/append.
- **Configurable prompt** — hostname, working directory, git branch/dirty
  status, command duration, and exit code, with theming.
- **Job control** — background jobs (`&`), `jobs`, `fg`, `bg`, `disown`.
- **Pipelines & redirection** — `|`, `>`, `>>`, `<`, `<<`, `<<<`, logical
  `&&` / `||`, and command sequencing.
- **Control flow & functions** — `if`, `for`, `while`, `switch`, `begin`/`end`,
  and user-defined `function`s.
- **Reproducible build** — a single statically-dumped SBCL image via Nix;
  `nix run` and you're in.

## Quick start

With [Nix](https://nixos.org/download) (flakes enabled), run nshell without
installing anything:

```sh
nix run github:takeokunn/nshell
```

Or build a binary into your profile:

```sh
nix profile install github:takeokunn/nshell
nshell
man nshell   # the manual page is installed alongside the binary
```

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
`$argv`. See [`examples/`](./examples) for a runnable sample.

### CLI

```
Usage: nshell [--help] [--version] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]

Without arguments, nshell starts an interactive shell when stdin is a terminal
and reads batch input from stdin otherwise.
With -c/--command, nshell executes COMMAND once in batch mode; trailing ARGS are available as $argv.
With SCRIPT, nshell runs the script file; trailing ARGS are available as $argv.
```

## Building from source

nshell builds with [SBCL](http://www.sbcl.org/) and ASDF. The supported and
tested path is Nix:

```sh
git clone https://github.com/takeokunn/nshell
cd nshell
nix build            # produces ./result/bin/nshell
nix flake check --print-build-logs
nix develop          # dev shell with SBCL + FiveAM
```

Inside `nix develop`, you can load the system into a REPL:

```lisp
(asdf:load-system :nshell)
(nshell:main)
```

## Built-in commands

`alias`, `abbr`, `bg`, `cd`, `complete`, `contains`, `count`, `disown`, `echo`,
`exec`, `exit`, `export`, `false`, `fg`, `function`, `help`, `history`, `jobs`,
`ls`, `not`, `pwd`, `read`, `seq`, `set`, `source`, `string`, `test`, `true`,
`type`, `which`.

Run `help` inside nshell for details.

## Architecture

nshell follows a domain-driven, layered design. Each layer depends only on the
layers beneath it:

```
src/
├── domain/          Pure shell logic: parsing, expansion, completion,
│                    history, prompting, job-control — no I/O.
├── application/     Use cases: builtins, pipeline execution, job management.
├── infrastructure/  ACLs over the OS: syscalls, PTY, signals, terminal I/O,
│                    persistence. SBCL-specific code is isolated here.
└── presentation/    The REPL, line editor (input-state reducer), rendering,
                     highlighting, autosuggestions, completion UI.
```

The REPL is structured as a **continuation-passing / trampoline loop**: each
keystroke runs a pure reducer over an immutable `input-state`, and rendering is
derived from that state. This keeps the interactive core deterministic and
unit-testable without a terminal.

## Testing

The suite uses [FiveAM](https://github.com/lispci/fiveam) and is exposed through
Nix checks.

Run the same hermetic Linux/macOS gate used by CI:

```sh
nix flake check --print-build-logs
```

Run only the current platform's test derivation:

```sh
nix build .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).test
```

Run the full non-sandboxed integration suite when changing PTY, subprocess,
terminal, or job-control behavior. This covers the real-PTY interactive smoke,
Ctrl-C recovery, and job-control lifecycle checks that are intentionally skipped
inside hermetic Nix builds:

```sh
nix develop -c sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(push (truename "./") asdf:*central-registry*)' \
  --eval '(asdf:test-system :nshell/test)'
```

Unit, integration, property-based, and end-to-end tests live under `tests/`.
New shell-language, expansion, completion, job-control, and input-state changes
should include focused regression tests plus the relevant property or PTY
coverage when behavior crosses process, terminal, or parser boundaries. See
`CONTRIBUTING.md` for test-selection expectations.

## Roadmap

nshell is converging on world-class interactive-shell parity. Near-term focus:

- **Shell language depth** — richer list variables and stricter compatibility
  around compound expansions.
  (Quoting, parameter expansion incl. patterns, arithmetic `$((...))`, brace
  expansion, command substitution `$(...)`/`(...)`, fd redirections
  `2>`/`2>&1`/`&>`, here-docs `<<`, here-strings `<<<`, and function arguments via
  `$argv`/`$argv[N]` are done.)
- **Job control hardening** — robust foreground process-group handling so
  `Ctrl-C` / `Ctrl-Z` reliably interrupt and suspend pipelines.
- **Completion intelligence** — broader command metadata and higher-fidelity
  flag/value completion.
- **Distribution** — nixpkgs, Homebrew, and prebuilt release binaries.

See [CHANGELOG.md](./CHANGELOG.md) for released changes.

For release qualification, see [PUBLIC_READINESS.md](./PUBLIC_READINESS.md).

## Contributing

Contributions are welcome. Please run `nix flake check --print-build-logs`
before opening a pull request; CI runs that hermetic gate on Linux and macOS
and also runs the full non-sandboxed integration suite on Linux. See
`CONTRIBUTING.md` for style, test, compatibility, and issue-reporting
expectations.

## Security

Please report vulnerabilities privately instead of opening a public issue. See
`SECURITY.md` for the supported scope, report contents, and disclosure process.

## License

[MIT](./LICENSE) © the nshell authors.

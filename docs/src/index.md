# nshell

A modern, fish-inspired interactive shell written in Common Lisp.

nshell is an interactive shell that puts the *interactive* experience first:
real-time syntax highlighting, history-aware autosuggestions, fish-style
abbreviations, and a fast, context-aware completion engine — all built on a
clean, test-driven Common Lisp core and a reproducible Nix build.

!!! note "Status: early development (0.4.x)"

    The interactive editor and core pipeline execution are solid and heavily
    tested. The shell *language* is a growing subset of POSIX/fish semantics —
    see the [roadmap](project/roadmap.md) for what is and isn't supported yet.
    nshell is usable as a daily interactive shell for common workflows; it is
    not a script-compatible `/bin/sh` replacement.

## Highlights

- **Syntax highlighting** as you type — commands, strings, operators, and paths
  are colorized live.
- **Autosuggestions** from your history, fish-style, accepted with `→` /
  `Ctrl-F`.
- **Abbreviations** (`abbr`) that expand inline as you type — keep your muscle
  memory, type less.
- **Context-aware completion** — a knowledge base of commands and flags plus
  filesystem completion, with common-prefix `Tab` extension and a candidate
  menu.
- **Rich line editing** — Emacs keybindings, kill-ring and yank, multi-level
  undo/redo, multiline editing, and incremental history search (`Ctrl-R`).
  Optional **vi key bindings** (`NSHELL_VI_MODE=1`): normal-mode motions,
  counts, operators (`dd`, `cw`, …), visual selection, and insert/append.
- **Configurable prompt** — hostname, working directory, git branch and dirty
  status, command duration, and exit code, with theming.
- **Job control** — background jobs (`&`), `jobs`, `fg`, `bg`, `disown`.
- **Pipelines and redirection** — `|`, `>`, `>>`, `<`, `<<`, `<<<`, logical
  `&&` / `||`, and command sequencing.
- **Control flow and functions** — `if`, `for`, `while`, `switch`,
  `begin`/`end`, and user-defined `function`s.
- **Reproducible build** — a single statically-dumped SBCL image via Nix;
  `nix run` and you're in.

## Where to go next

- [Getting started](getting-started.md) — install nshell and run your first
  command.
- [Core concepts](guide/concepts.md) — how the interactive layer is put
  together.
- [Recipes](guide/recipes.md) — scripting, pipeline diagrams, and the test
  workflow.
- [Built-in commands](reference/builtins.md) — the shell's own command set.
- [Architecture](reference/architecture.md) — the layered design and the
  toolkit family it builds on.

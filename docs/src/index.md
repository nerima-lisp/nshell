# nshell

A fish-inspired interactive shell written in Common Lisp.

nshell provides real-time syntax highlighting, history-aware autosuggestions,
fish-style abbreviations, and context-aware completion. It is built with Nix.

!!! note "Status: development preview (0.6.x)"

    The shell implements a tested subset of shell syntax, not full POSIX/fish
    compatibility. For supported features and known limits,
    see the [roadmap](project/roadmap.md).
    It is not a script-compatible `/bin/sh` replacement.

## Highlights

- **Syntax highlighting** as you type: a command that would fail with
  `command not found` is red before you run it, existing paths are underlined,
  and strings, variables, keywords, and operators each get their own color.
- **Autosuggestions** from your history, fish-style, accepted with `→` /
  `Ctrl-F`.
- **Abbreviations** (`abbr`) expand inline as you type.
- **Context-aware completion**: a knowledge base of commands and flags plus
  filesystem completion, git branches, environment variables, and
  directory-only completion for `cd`, in a colored candidate menu with
  common-prefix `Tab` extension.
- **Line editing**: Emacs keybindings, kill-ring and yank, multi-level
  undo/redo, multiline editing, and a `Ctrl-R` history picker that lists
  matches under the prompt.
- **Vi key bindings** (optional, `NSHELL_VI_MODE=1`): normal-mode motions,
  counts, operators (`dd`, `cw`, …), visual selection, and insert/append.
- **Themes**: one named palette drives the prompt, the highlighter, and the
  completion menu; ten presets ship with the shell, `theme use` switches live,
  and colors downsample to 256- or 16-color terminals.
- **Prompt status**: working directory, git branch and dirty marker,
  a prompt character that turns red after a failure, and, on the right, the
  failing exit code plus the duration of anything slower than a second.
- **Job control**: background jobs (`&`), `jobs`, `fg`, `bg`, `disown`.
- **Pipelines and redirection**: `|`, `>`, `>>`, `<`, `<<`, `<<<`, logical
  `&&` / `||`, and command sequencing.
- **Control flow and functions**: `if`, `for`, `while`, `switch`,
  `begin`/`end`, and user-defined `function`s.
- **History expansion**: `!!`, `!$`, `!-N`, `!?text?`, and `!prefix`, with
  single-quoted and backslash-escaped exclamation marks kept literal.
- **External editing**: `Alt-E` opens the current line with the configured
  editor and returns the edited buffer to the prompt.
- **Nix build**: a dumped SBCL image and its process-launch helper;
  start the shell with `nix run`.

## Where to go next

- [Getting started](getting-started.md): install nshell and run your first
  command.
- [Core concepts](guide/concepts.md): how the interactive layer is put
  together.
- [Recipes](guide/recipes.md): scripting, pipeline diagrams, and the test
  workflow.
- [Built-in commands](reference/builtins.md): the shell's own command set.
- [Architecture](reference/architecture.md): the layered design and the
  toolkit family it builds on.

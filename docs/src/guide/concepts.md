# Core concepts

## The input state is a value

Every keystroke runs a pure reducer over an immutable `input-state` value, and
what appears on screen is derived from that value. Nothing about the current
line lives in a terminal buffer or a mutable global.

This is the single decision most of nshell's interactive behaviour follows
from. Because a keystroke is a function from state to state, the line editor
can be tested exhaustively without a terminal: a test feeds a key sequence and
asserts on the resulting buffer, cursor, kill ring, or undo stack. Multi-level
undo is a stack of prior values rather than a replay log, and rendering can be
recomputed from scratch whenever it is cheaper than diffing.

The REPL that drives the reducer is a continuation-passing trampoline loop,
which keeps the interactive core deterministic and unit-testable.

## Color is a theme, not a pile of escape codes

Every colored thing nshell draws (the prompt, the command line as you type, the
completion menu) reads its style from one theme: a mapping from a named role to
a fish-style style spec such as `5fafff --bold` or `gray --italics`. Nothing in
the rendering code carries a hardcoded escape sequence, so switching the whole
shell to another palette is one `theme use` away, and a role you dislike is one
`theme set` away. Colors are written once in truecolor and downsampled at the
terminal boundary, so the same theme renders on a 256-color or 16-color
terminal and disappears entirely under `NO_COLOR`. See
[Customization](customization.md).

## Highlighting answers a question before you press Enter

The syntax highlighter is not a lexer painting tokens by shape. It resolves the
command word against the same sources the executor will use: shell keywords,
the builtin registry, functions, aliases, abbreviations, then PATH. A command
that will fail with `command not found` is therefore red while you are still
typing it, an existing path is underlined, and a variable reference is colored
as one. When a command does fail that way, nshell proposes the names one edit
away from what you typed.

## Completion is a knowledge base, not a table

Completion candidates come from a logic knowledge base compiled into a
[cl-prolog-kit](https://github.com/nerima-lisp/cl-prolog-kit) rulebase, queried through
predicates such as `completes`, `describes`, `has-flag`, `command-is`,
`suggests-dir`, and `suggests-file`.

Expressing completion as facts and rules rather than a lookup table means new
command metadata is data, and the ranking and filtering logic stays in one
place. Filesystem completion composes with the same query path, so a candidate
menu can mix a flag, a subcommand, and a path without special-casing any of
them.

## Autosuggestions come from history

As you type, nshell searches command history for the most recent entry with the
current line as a prefix and shows the remainder dimmed after the cursor.
Accepting it with `→` or `Ctrl-F` inserts the rest. This is the fish-style
behaviour: it costs nothing when you ignore it, and it is faster than reverse
search when the command is recent.

`Ctrl-R` opens incremental reverse search for the cases where a prefix is not
what you remember. It draws the matching history entries under the prompt with
the matched text highlighted; `Ctrl-R` and `Ctrl-S` (or the arrow keys) move
the selection, Enter runs the selected entry, and Escape puts back the line you
were typing.

## History expansion is explicit

Interactive lines can refer to recent history with `!!`, `!$`, `!-N`,
`!?text?`, and `!prefix`. Expansion happens before parsing, so a failed
designator is reported without executing or recording the invalid line.
Exclamation marks in single quotes and backslash-escaped exclamation marks
remain literal.

## Abbreviations expand in place

An abbreviation registered with `abbr` expands inline as you type, so what ends
up in history is the expanded command. This differs from an alias, which stays
unexpanded and hides what actually ran. Abbreviations keep muscle memory short
while leaving history honest and greppable.

## External editing preserves the prompt state

`Alt-E` writes the current buffer to a private temporary file and opens it with
the first non-empty value among `NSHELL_EDITOR`, `VISUAL`, and `EDITOR`, or
`vi`. After a successful exit, the edited file replaces the current buffer;
the command is not executed until the normal submit key is pressed.

## The prompt states what the last command did

The left prompt carries the working directory (shortened fish-style when the
terminal is narrow) and the git branch with a `*` when the tree is dirty. The
prompt character is green after a success and red after a failure, so the last
result is visible without reading anything. The right prompt adds the failing
exit code, the wall-clock duration of any command that took a second or more,
and the time it finished. Everything on the right is omitted when it has
nothing to say, which keeps a fast, successful command on a quiet line.

## Layers, and what is allowed to do I/O

nshell follows a domain-driven, layered design where each layer depends only on
the layers beneath it. The rule that matters day to day is that `domain/`
performs no I/O: parsing, expansion, completion, history, prompting, and
job-control logic are pure functions over values. Everything that touches the
operating system — syscalls, PTY, signals, terminal I/O, persistence — is
isolated in `infrastructure/`, behind explicit boundaries that tests can swap.

That separation is why the prompt and command timing are deterministic under
test: hostname, working directory, and the clock are injected boundaries rather
than ambient calls. See [Architecture](../reference/architecture.md) for the
full layer map.

## Vi mode

Setting `NSHELL_VI_MODE=1` switches the line editor to vi key bindings:
normal-mode motions, counts, operators (`dd`, `cw`, …), char-wise visual
selection with yank/delete/change, and insert/append. It is the same reducer
with a different key dispatch table, so undo, kill-ring, and completion behave
identically in both modes.

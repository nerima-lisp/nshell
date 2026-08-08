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

## Completion is a knowledge base, not a table

Completion candidates come from a logic knowledge base compiled into a
[cl-prolog](https://github.com/nerima-lisp/cl-prolog) rulebase, queried through
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
what you remember.

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

# Core concepts

## The input state is a value

The reducer returns a new `input-state` value. The REPL stores the current
value in `*input-state*` and derives rendering from it.

Reducer tests feed key sequences and assert on the resulting buffer, cursor,
kill ring, or undo stack without a terminal. PTY tests check terminal
integration separately. Multi-level undo stores prior values rather than a
replay log, and rendering can be recomputed from the current state.

The REPL drives the reducer through a continuation-passing trampoline loop.

## Color is a theme, not a pile of escape codes

The prompt, command line, and completion menu read styles from a shared theme:
a mapping from a named role to a fish-style spec such as `5fafff --bold` or
`gray --italics`. `theme use` selects a palette; `theme set` changes a role.
Theme roles control colors and text styles. Cursor movement and other terminal
controls use separate escape sequences. Colors are downsampled for 256-color
or 16-color terminals; a nonempty `NO_COLOR` disables color output. See
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

Command metadata is expressed as facts and rules. Filesystem completion joins
the candidate query path, so a menu can mix flags, subcommands, and paths.
Candidate sources still use command-specific rules and routing priorities.

## Autosuggestions come from history

As you type, nshell searches command history for the most recent entry with the
current line as a prefix and shows the remainder dimmed after the cursor.
Accepting it with `→` or `Ctrl-F` inserts the rest. You can continue typing
without accepting the suggestion.

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

An abbreviation registered with `abbr` expands inline as you type, so history
records the expanded command. An alias is resolved during execution; history
retains the entered alias name.

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
and the current time when the prompt is rendered. The default clock remains
visible after fast, successful commands too.

## Layers, and what is allowed to do I/O

The domain layer models parsing, expansion, completion, history, prompting,
and job-control policy as values. Infrastructure adapters provide syscalls,
PTYs, signals, terminal I/O, and persistence. The runtime targets SBCL and
also uses its facilities outside infrastructure.

That separation is why the prompt and command timing are deterministic under
test: hostname, working directory, and the clock are injected boundaries rather
than ambient calls. See [Architecture](../reference/architecture.md) for the
full layer map.

## Vi mode

Set `NSHELL_VI_MODE=1` to start with vi key bindings. At an interactive prompt,
`set -o vi` enables them and `set +o vi` disables them for the current session.
Normal mode supports motions, character finds, counts, operators, text objects,
character-wise visual selection, and insert/append. `j` and `k` navigate
history. These bindings edit the input buffer; they do not change how nshell
parses or executes commands.

## A function call gets its own variable scope

Calling a function pushes an empty scope onto the environment and pops it
when the call returns, so a plain `set NAME VALUE` inside a function creates a
variable that disappears at the end of the call, unless `NAME` was already
visible in an enclosing scope, in which case it updates that binding in place
instead. `set -l` forces a new local variable even when an outer one of the
same name exists; `set -g` always reaches past every local scope to the
outermost one. Reading a name walks the scope chain from innermost outward,
so a local variable shadows a global of the same name for the rest of that
call. The environment stores scopes as an ordered list.

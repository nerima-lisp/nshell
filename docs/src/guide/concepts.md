# Core concepts

## S-expressions and bare command lines

An input whose first non-whitespace character is `(` is read as an
S-expression. A list whose head resolves to a Common Lisp form uses Lisp
evaluation; otherwise, the list is a shell command form. This rule also applies
to nested lists. Inputs that do not start with `(` remain bare command lines.

Inside a command form, `$NAME` passes a shell variable's value and `,EXPR`
evaluates an expression and passes its value to the command:

```lisp
(set o02_value "preserved")
(echo $o02_value ,(+ 2 3))
```

The command prints `preserved` and `5`. The first argument is a shell value;
the second comes from the Common Lisp addition form `(+ 2 3)`.

## Byte pipelines and value pipelines

`|` connects byte streams between commands. `->` passes values through
transformations such as `where` and `select`. Use the value pipeline when
commands return records that should be filtered or projected without parsing
text:

```lisp
(echo ,(length
         (-> '((:state "stopped" :id 7 :command "demo")
               (:state "running" :id 8 :command "other"))
             (where (= :state "stopped"))
             (select :id :command))))
```

This expression prints `1`, the number of records whose state is `stopped`.

## Control forms and functions

Common Lisp forms provide conditionals, loops, and function definitions. A
command can appear in a form's body:

```lisp
(if (= 1 1) (echo O04_IF_OK) (echo O04_IF_WRONG))
(defun o05_greet (name) (echo $name))
(o05_greet "O05_TOPLEVEL_OK")
(when t (defun o05_nested (name) (echo $name)))
(o05_nested "O05_NESTED_OK")
```

The first form prints `O04_IF_OK`; the function calls print
`O05_TOPLEVEL_OK` and `O05_NESTED_OK`. `let`
creates lexical bindings, while `set` assigns a shell variable that remains
available to later forms:

```lisp
(set o03_shared "outer")
(let ((o03_local "inner")) (echo $o03_local))
(echo $o03_shared)
```

The forms print `inner` and `outer`. See [Recipes](recipes.md) for JSON, TSV,
and regular expression examples.

## Command failures and restarts

At the interactive top level, a failed command updates the shell status and
returns to the prompt. When a command failure escapes from a function, nshell
offers restart choices at the point of failure. One choice ignores the failure
and continues with the remaining forms in the function. Failures in a test position,
such as an `if` condition, are treated as a boolean result.

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
a mapping from a named role to a style such as `5fafff --bold` or
`gray --italics`. `theme use` selects a palette; `theme set` changes a role.
Theme roles control colors and text styles. Cursor movement and other terminal
controls use separate escape sequences. Colors are downsampled for 256-color
or 16-color terminals; a nonempty `NO_COLOR` disables color output. See
[Customization](customization.md).

## Highlighting answers a question before you press Enter

The syntax highlighter resolves the command word against the same sources the
executor will use: shell keywords, the builtin registry, functions, aliases,
then PATH. A command that will fail with `command not found` is therefore red
while you are still typing it, an existing path is underlined, and a variable
reference is colored as one.

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

Bare interactive command lines can refer to recent history with `!!`, `!$`,
`!-N`, `!?text?`, and `!prefix`. Expansion happens before parsing, so a failed
designator is reported without executing or recording the invalid line.
Exclamation marks in single quotes and backslash-escaped exclamation marks
remain literal. S-expression input does not use history expansion.

## External editing preserves the prompt state

`Alt-E` writes the current buffer to a private temporary file and opens it with
the first non-empty value among `NSHELL_EDITOR`, `VISUAL`, and `EDITOR`, or
`vi`. After a successful exit, the edited file replaces the current buffer;
the command is not executed until the normal submit key is pressed.

## Prompt fields report command state

The prompt can include the previous command's status, exit code, duration, and
background-job count. The left and right prompt formats can be set separately;
see [Customization](customization.md).

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
The terminal cursor shape changes with the editing mode. Vi mode changes how
editing keys act; it does not change how nshell parses or executes commands.

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

# Built-in commands

Run `help` inside nshell for per-command detail, and `type NAME` to check
whether a name resolves to a builtin, a function, or an external program.

`.`, `[`, `agent`, `ai`, `alias`, `abbr`, `and`, `bg`, `bind`, `break`, `builtin`, `cd`, `command`,
`complete`, `contains`, `continue`, `count`, `dirs`, `disown`, `echo`, `eval`,
`exec`, `exit`, `export`, `false`, `fg`, `function`, `functions`, `help`,
`history`, `jobs`, `kill`, `math`, `nextd`, `not`, `or`, `pipeline-graph`,
`popd`, `prevd`, `printf`, `prompt`, `pushd`, `pwd`, `read`, `seq`, `set`,
`source`, `string`, `test`, `theme`, `true`, `type`, `unset`, `wait`, `which`.

## Notes on a few of them

**`abbr`** registers an abbreviation that expands inline as you type, so
history records the expanded command. Prefer it to `alias` when you want the
short form only while typing.

**`ai`** controls the assistant session. `ai status` shows sidecar state and
usage, `ai reset` clears the conversation, `ai log [N]` shows recent audit
entries, and `ai set KEY VALUE` changes `effort`, `model`, `max-steps`, or
`budget`.

**`agent`** starts an interactive assistant task. It requires a terminal, and
proposed commands require confirmation before execution.

**`pipeline-graph`** renders a typed pipeline as a Graphviz DOT graph, or a
Mermaid flowchart with `--mermaid`, without executing it. Quote the pipeline so
the shell passes it as one argument; see
[Recipes](../guide/recipes.md#draw-a-pipeline-without-running-it).

**`bind`** lists, sets, erases, or resets key bindings: `bind` alone lists
every binding, `bind KEY` shows one, `bind KEY ACTION` rebinds a key, `bind -e
KEY` erases a binding (the key then does nothing), and `bind --reset` restores
every default. See
[Customizing key bindings](../guide/customization.md#customizing-key-bindings).

**`theme`** picks or tunes the color theme: `theme list` shows the presets,
`theme use NAME` switches to one, `theme set ROLE SPEC` overrides a single
role, and `theme show` prints the active theme. See
[Customizing colors](../guide/customization.md#customizing-colors).

**`prompt`** picks the prompt's layout: `prompt show` prints the active left
and right format strings, `prompt left FORMAT`/`prompt right FORMAT` install
one, `prompt preview FORMAT` renders a format without installing it, and
`prompt reset` restores the defaults. See
[Customizing the prompt](../guide/customization.md#customizing-the-prompt).

**`string`** provides subcommands such as `string upper`, `string split`, and
`string match`. Each subcommand rejects a leading option it does not define
instead of treating it as data; `--` ends option parsing and a lone `-` is a
literal argument. `string split` supports `-m`/`--max N` (split at most N
times; left splitting leaves the remainder in the last field) and
`-r`/`--right` (split from the right, leaving the remainder in the first
field); `string trim` supports `-l`/`--left`, `-r`/`--right`, and
`-c`/`--chars CHARS`. `string match -r` matches with regular expressions and
supports `-i`/`--ignore-case`; `string replace -r` is unsupported and reports
an error.

**`complete -C LINE`** prints the completion candidates for `LINE`, one per
line.

**`dirs`**, **`pushd`**, **`popd`** manage a directory stack: `pushd DIR`
remembers the current directory and switches to `DIR`; `popd` returns to the
most recently remembered one; `dirs` lists the stack, current directory
first, `~`-shortened. `pushd` with no argument swaps the current directory
with the top of the stack. **`prevd`** / **`nextd`** walk a separate,
append-only history of every directory visited via `cd`, `pushd`, or `popd`.

**`builtin NAME`** runs a builtin directly, bypassing any function or alias
of the same name.

**`set`** manages shell variables: bare `set` lists visible variables,
`set -x NAME VALUE...` exports, `set -e NAME` erases, and `set -q NAME` tests
whether a name is defined. `-l`/`--local` and `-g`/`--global` select a scope
and combine with `-x` (`-lx`, `-gx`). `-U`/`--universal` is rejected.

**`disown`** removes a job from the shell's job table so it survives exit,
complementing `jobs`, `fg`, and `bg`. With no argument it acts on the
current job, the same convention `fg` and `bg` use.

**`test`** (and `[`) supports file tests (`-e -f -d`), string tests
(`-n -z = !=`), and numeric comparisons (`-eq -ne -lt -le -gt -ge`). An
unrecognized operator or a non-integer operand to a numeric comparison is a
diagnosed usage error (exit 2), distinct from a false result (exit 1).

## S-expression input

An unparenthesized line remains shell-command syntax. A parenthesized list with
a simple symbol head is a Common Lisp form when the head resolves to a host
form; otherwise, it is a command island whose head names a command. Arguments
in a command island are quoted as command values by default. Use `$NAME` to
pass a shell variable's value, and `,EXPR` to evaluate an expression and pass
its value. String literals remain literal; value escapes do not interpolate
text into them.

```lisp
(set example "preserved")
(echo $example ,(+ 2 3))
```

Forms use value, stream, or test position. Value position returns a Lisp value.
Stream position reads or writes bytes. A direct command in test position uses
its exit status as a boolean. A direct command used as an operand to Common Lisp
`=` supplies its exit status as an integer.

In bare-line input, `|` connects byte streams. In an S-expression pipeline,
`(| ...)` connects byte streams and `->` passes structured values between
internal commands and transformations. The example filters records by their
`:state` field and selects two fields:

```lisp
(-> '((:state "stopped" :id 7 :command "demo")
      (:state "running" :id 8 :command "other"))
    (where (= :state "stopped"))
    (select :id :command))
```

The value library provides `to-json` and `from-json`,
`to-tsv` and `from-tsv`, and `to-lines` and `from-lines` for JSON, TSV,
and line-text conversion. It also provides `regex-match-p`, `regex-find`,
and `regex-replace`. The `string match -r` builtin matches regular
expressions.

## S-expression functions and command failures

Define shell functions with `defun`. A definition can appear inside a control
form. When a function call requests a name that has not been loaded, nshell
checks `$XDG_CONFIG_HOME/nshell/functions/NAME.nsh` if
`XDG_CONFIG_HOME` is absolute. Otherwise it checks
`~/.config/nshell/functions/NAME.nsh`. The file defines the requested
function with `defun`.

A command failure in a function can signal `command-failed`; `handler-case`
can handle it. At an interactive prompt, a failed function call offers the
`Ignore and continue` restart, which skips the failed command and continues the
remaining forms in the function. Press Ctrl-C to return to the prompt.

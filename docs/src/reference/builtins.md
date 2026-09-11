# Built-in commands

Run `help` inside nshell for per-command detail, and `type NAME` to check
whether a name resolves to a builtin, a function, or an external program.

`agent`, `ai`, `alias`, `abbr`, `and`, `bg`, `bind`, `break`, `builtin`, `cd`, `command`,
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
the shell passes it as one argument — see
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

**`string`** is the fish-style string toolkit (`string upper`, `string split`,
and friends) rather than a single-purpose command.

**`complete`** registers completion metadata for a command, feeding the same
knowledge base the built-in command catalog uses. `complete -C LINE` is the
scriptable entry point: it prints the completions for `LINE`, one per line,
without registering anything.

**`and` / `or`** run their command based on `$status`, the previous command's
exit code: `and` only if it was `0`, `or` only if it was nonzero. Otherwise
they leave `$status` unchanged. `not` (see above) already exists for
inverting a status; `and`/`or` chain on it the way `&&`/`||` chain commands
within one line.

**`math`** is fish's calculator: `math '1 + 2 * 3'`, parentheses, unary
minus, and decimals. Division renders as a decimal (`math '10 / 4'` is
`2.5`), trimmed to at most 6 fraction digits. Division by zero exits 1;
a malformed expression exits 2.

**`dirs`**, **`pushd`**, **`popd`** manage a directory stack: `pushd DIR`
remembers the current directory and switches to `DIR`; `popd` returns to the
most recently remembered one; `dirs` lists the stack, current directory
first, `~`-shortened. `pushd` with no argument swaps the current directory
with the top of the stack. **`prevd`** / **`nextd`** walk a separate,
append-only history of every directory visited via `cd`, `pushd`, or `popd`.

**`functions`** lists defined function names (one per line); `functions
NAME` prints its reconstructed definition, noting the source file when the
function came from one; `functions -e NAME` erases it. **`builtin` NAME**
runs a builtin directly, bypassing any function or alias of the same name.

**`disown`** removes a job from the shell's job table so it survives exit,
complementing `jobs`, `fg`, and `bg`. With no argument it acts on the
current job, the same convention `fg` and `bg` use.

**`test`** (and `[`) supports file tests (`-e -f -d`), string tests
(`-n -z = !=`), and numeric comparisons (`-eq -ne -lt -le -gt -ge`). An
unrecognized operator or a non-integer operand to a numeric comparison is a
diagnosed usage error (exit 2), distinct from a false result (exit 1).

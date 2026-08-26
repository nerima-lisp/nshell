# Built-in commands

Run `help` inside nshell for per-command detail, and `type NAME` to check
whether a name resolves to a builtin, a function, or an external program.

`alias`, `abbr`, `bg`, `break`, `cd`, `command`, `complete`, `contains`,
`continue`, `count`, `disown`, `echo`, `eval`, `exec`, `exit`, `export`,
`false`, `fg`, `function`, `help`, `history`, `jobs`, `kill`, `not`,
`pipeline-graph`, `printf`, `pwd`, `read`, `seq`, `set`, `source`, `string`,
`test`, `true`, `type`, `unset`, `wait`, `which`.

## Notes on a few of them

**`abbr`** registers an abbreviation that expands inline as you type, so
history records the expanded command. Prefer it to `alias` when you want the
short form only while typing.

**`pipeline-graph`** renders a typed pipeline as a Graphviz DOT graph, or a
Mermaid flowchart with `--mermaid`, without executing it. Quote the pipeline so
the shell passes it as one argument — see
[Recipes](../guide/recipes.md#draw-a-pipeline-without-running-it).

**`string`** is the fish-style string toolkit (`string upper`, `string split`,
and friends) rather than a single-purpose command.

**`complete`** registers completion metadata for a command, feeding the same
knowledge base the built-in command catalog uses.

**`disown`** removes a job from the shell's job table so it survives exit,
complementing `jobs`, `fg`, and `bg`. With no argument it acts on the
current job, the same convention `fg` and `bg` use.

**`test`** (and `[`) supports file tests (`-e -f -d`), string tests
(`-n -z = !=`), and numeric comparisons (`-eq -ne -lt -le -gt -ge`). An
unrecognized operator or a non-integer operand to a numeric comparison is a
diagnosed usage error (exit 2), distinct from a false result (exit 1).

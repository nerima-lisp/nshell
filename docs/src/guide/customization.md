# Customization

nshell colors the prompt, syntax highlighting, and completion menu from a
single **theme**: a mapping from named roles (`command`, `prompt-path`,
`completion-file`, and so on) to a style. The `theme` builtin lets you switch
between built-in presets or override individual roles. The interactive startup
file is `$XDG_CONFIG_HOME/nshell/init.lisp` when `XDG_CONFIG_HOME` is an
absolute path, or `~/.config/nshell/init.lisp` otherwise. It runs plain nshell
commands at startup. `--no-config` skips it, and `--config PATH` selects another
file. Batch and script runs do not load it. With default path selection,
`~/.nshellrc` is ignored and nshell prints a one-line notice.

## Shell hooks

Register hooks from `init.lisp` with `nshell.application:register-shell-hook`.
Hooks run in registration order. `nshell.application:remove-shell-hook` removes
one callback, and `nshell.application:clear-shell-hooks` clears all callbacks
or one hook's callbacks.

| Hook | Boundary | Arguments |
|---|---|---|
| `:preexec` | Before an interactive command runs | Command text |
| `:postexec` | After an interactive command finishes | Command text, exit status, duration in milliseconds |
| `:prompt` | Before the initial prompt and each prompt after Enter | Current directory, previous exit status |
| `:cd` | After `cd` changes the directory | Previous directory, current directory |
| `:command-not-found` | When interactive command lookup cannot find an executable | Command name |

For example, append a line to a trace file before each command:

```lisp
(nshell.application:register-shell-hook
 :preexec
 (lambda (command)
   (with-open-file (stream "/tmp/nshell-commands.log"
                           :direction :output
                           :if-exists :append
                           :if-does-not-exist :create)
     (write-line command stream))))
```

If a hook signals an error, nshell reports it on standard error and continues
with the remaining hooks and the shell session.

## East Asian ambiguous character width

Some Unicode characters, such as `·`, `…`, and `○`, have an East Asian
ambiguous width. Set `NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH` to `auto` (the
default), `narrow`, or `wide` in the startup file or the environment:

```
set -x NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH wide
```

With `auto`, an interactive TTY is probed using a cursor-position report. If
the terminal does not answer promptly, nshell uses `LC_ALL`, then `LC_CTYPE`,
then `LANG`: `ja`, `zh`, and `ko` locales select `wide`, and other locales
select `narrow`. Batch commands and `-c` never perform the probe. The selected
width is used consistently for prompts, input wrapping, cursor movement,
completion columns, transient panels, and history search.

## Customizing colors

### The `theme` builtin

`theme` (or `theme show`) prints the active theme's name and the style of
every role, with a live sample when standard output is a terminal:

```
$ theme show
nshell
  argument               normal
  autosuggestion         6c6c6c
  command                5fafff --bold
  ...
```

`theme list` prints every preset name, marking the active one:

```
$ theme list
* nshell
  ansi
  dracula
  nord
  ...
```

`theme use NAME` switches to a preset by name (case-insensitive):

```
$ theme use tokyo-night
```

`theme set ROLE SPEC...` overrides one role in the active theme. `SPEC` is the
rest of the line, so no quoting is needed:

```
$ theme set prompt-path 5fafff --bold --underline
```

`theme reset` restores the default preset.

An unknown preset name, an unknown role, or a spec that fails to parse exits
with status 2 and an error naming the problem; `theme` with anything else
prints a usage line and exits 1.

### Style-spec grammar

A style spec is the fish `set_color` vocabulary in one string: an optional
color, followed by zero or more flags, separated by spaces.

A color is one of:

- A hex color, 6-digit (`5fafff`) or 3-digit (`5af`), with or without a
  leading `#`.
- One of the 16 fish color names: `black`, `red`, `green`, `yellow`, `blue`,
  `magenta` (or `purple`), `cyan`, `white`, and their `br`-prefixed bright
  variants (`brblack`, `brred`, … `brwhite`); `grey`/`gray` is an alias for
  `brblack`.
- `normal`, meaning the terminal's default foreground.

Flags: `--bold`, `--dim`, `--italics`, `--underline`, `--reverse`, and
`--background=COLOR` to set the background using the same color grammar.
Omitting a color and giving only flags is valid, and colors the text with the
terminal's default foreground plus those flags.

### Color depth and `NO_COLOR`

nshell detects the terminal's color depth (truecolor, 256-color, or the
16-color ANSI palette) and downsamples every hex color automatically: to the
nearest 256-color entry, or on a 16-color terminal to the palette slot with
the same hue (low-saturation colors become the grays). Setting `NO_COLOR` to a
nonempty value disables color output entirely, regardless of the active theme.

### Presets

`nshell` (the default), `ansi`, `mono`, `dracula`, `nord`, `gruvbox`,
`solarized-dark`, `solarized-light`, `catppuccin-mocha`, and `tokyo-night`.
`mono` and `ansi` are useful over a connection that cannot render truecolor;
`mono` drops color entirely and relies on bold/dim/italic/underline for
emphasis.

### Roles

Roles fall into three groups:

**Syntax highlighting**, applied to the command line as you type:
`normal`, `command`, `builtin`, `function`, `keyword`, `option`, `argument`,
`param`, `quote`, `variable`, `path`, `operator`, `redirection`, `comment`,
`error`, `autosuggestion`, `search-match`, `selection`.

**Prompt**, applied to prompt segments: `prompt-host`, `prompt-path`,
`prompt-git`, `prompt-git-dirty`, `prompt-ok`, `prompt-error`, `prompt-time`,
`prompt-duration`, `prompt-assistant`, `prompt-continuation`.

**Completion menu**: `completion-command`, `completion-directory`,
`completion-file`, `completion-option`, `completion-variable`,
`completion-description`, `completion-selected`, `completion-more`.

## Customizing the prompt

The prompt's layout, not just its colors, is a format string: literal text
plus `{segment}` placeholders. `{{` and `}}` stand for a literal brace. The
segments are `path`, `git` (branch plus `*` when dirty, empty outside a
repository), `host`, `user`, `status` (the `❯` character, styled by the last
exit code), `exit` (`[N]` after a failed command, else empty), `duration`,
`time`, `jobs` (the background job count, empty when there are none), and
`ai` (the assistant usage indicator, empty until a turn has run). An unknown
`{name}` is an error naming it. When a segment renders empty, one adjacent
run of spaces is dropped too, so `{path} {git} {status}` never leaves a
double space outside a repository.

nshell has two prompts: the left one, and a right prompt that floats at the
far edge of the terminal. The default left format is shown first, followed by
the right format:

```
{path} {git} {status} 
{exit} {duration} {time} {ai}
```

`prompt` (or `prompt show`) prints both active format strings, quoted, so a
trailing space is visible and the line can be pasted back. `prompt left FORMAT`
and `prompt right FORMAT` install a new one. `FORMAT` is the remaining
arguments joined with single spaces, so quote it when the exact spacing
matters, as it does for the trailing space the default format ends with:

```
$ prompt left '{user}@{host} {path}{git} $ '
```

Setting `NSHELL_PROMPT` and `NSHELL_RIGHT_PROMPT` in the environment supplies
the corresponding format at session start; a `prompt left`/`prompt right`
line in the startup file overrides the variable, since the file runs later.
`prompt preview FORMAT` renders `FORMAT` once against the current state,
without installing it. `prompt reset` removes both session overrides, then
uses those environment variables or the built-in defaults when they are empty
or unset. An invalid format exits with status 2 and names the unknown segment;
`prompt` with anything else prints a usage line and exits 1.

## Customizing key bindings

The line editor's Emacs-style key bindings (`Ctrl-A` to the line start,
`Ctrl-R` to search history, `Tab` to cycle completions, and so on) are data,
not hardcoded: the `bind` builtin lists, rebinds, erases, and resets them.

### The `bind` builtin

`bind` with no arguments lists every binding, one per line, sorted by key
name and padded to the widest key so the action column lines up:

```
$ bind
...
ctrl-r                start-history-search
ctrl-s                start-history-search
...
```

`bind KEY` prints one binding:

```
$ bind ctrl-r
ctrl-r  start-history-search
```

`bind KEY ACTION` rebinds a key to a different action:

```
$ bind ctrl-t clear-input
```

`bind -e KEY` erases a binding, so the key does nothing until it is rebound
or the table is reset:

```
$ bind -e ctrl-t
```

`bind --reset` restores every key to its default action.

An unknown key name or action name exits with status 2 and lists the valid
names; `bind` with anything else prints a usage line and exits 1. A key name
is spelled the way it is typed, in lowercase and hyphen-separated (`ctrl-r`,
`alt-e`, `right`, `shift-tab`). Put `bind` lines in the startup file to apply
custom bindings at interactive startup, the same way `theme` lines do.

### Structural editing

These default bindings move through S-expressions on the current input line,
delete an expression at the cursor, or move a list boundary around an adjacent
expression. They edit the input buffer without evaluating it. `up-list` moves
the cursor out of the surrounding list, and `down-list` enters the next child
list. Slurp pulls the neighboring expression into the list; barf pushes the
first or last expression out. Deletion puts the removed text in the kill ring,
which `Ctrl-Y` yanks back. Structural actions leave an incomplete or invalid
input line unchanged.

| Key | Action |
| --- | --- |
| `alt-ctrl-f` | `forward-sexp` |
| `alt-ctrl-b` | `backward-sexp` |
| `alt-ctrl-u` | `up-list` |
| `alt-ctrl-d` | `down-list` |
| `alt-ctrl-k` | `delete-forward-sexp` |
| `alt-ctrl-delete` | `delete-backward-sexp` |
| `alt-ctrl-right` | `slurp-forward` |
| `alt-ctrl-left` | `slurp-backward` |
| `shift-alt-ctrl-right` | `barf-forward` |
| `shift-alt-ctrl-left` | `barf-backward` |

For example, rebind forward motion with `bind alt-ctrl-f backward-sexp` or
remove its default with `bind -e alt-ctrl-f`.

### Capturing the previous command's output

After a command has finished, press `Ctrl-X` to request a captured rerun. nshell
shows the complete command, its safety classification (`safe`, `confirm`, or
`block`), and the reason. `block` commands and terminal-dependent commands such
as `vim`, `less`, and `ssh` are rejected; `safe` and `confirm` commands require
a second `Ctrl-X` to run. The confirmation lists the keys currently bound to
`rerun-last-command`. Long lines wrap without omitting text. If the complete
confirmation cannot fit in the terminal or contains non-displayable control
characters, nshell refuses the rerun. Any other key or a terminal resize
cancels the pending confirmation.

Use this to capture fresh output before asking `?` to explain a command. It
reruns the command rather than replaying old output.

### Vi-mode cursor shape

When `NSHELL_VI_MODE` is enabled, or after `set -o vi` enables vi mode during an
interactive session, the cursor shape follows the editor mode: a steady block
in normal mode and a steady bar while inserting. `set +o vi` restores the
terminal's default cursor shape. These changes require no extra configuration
and apply only in an interactive terminal.

## The startup file

Put a `theme` command there to select your preset:

```sh
theme use tokyo-night
theme set prompt-git-dirty yellow --bold
```

See [examples/init.lisp.example](https://github.com/nerima-lisp/nshell/blob/main/examples/init.lisp.example)
for a complete starting point.

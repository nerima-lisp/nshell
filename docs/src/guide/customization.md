# Customization

nshell colors the prompt, syntax highlighting, and completion menu from a
single **theme**: a mapping from named roles (`command`, `prompt-path`,
`completion-file`, and so on) to a style. The `theme` builtin lets you switch
between built-in presets or override individual roles, and `~/.nshellrc` runs
plain nshell commands at startup, so a `theme` line there applies on every
launch.

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
the same hue (low-saturation colors become the grays). A preset written for
truecolor still renders sensibly over a plain ANSI connection. Setting `NO_COLOR` to any value
disables color output entirely, regardless of the active theme.

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
far edge of the terminal. They default to exactly today's layout:

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

`prompt preview FORMAT` renders `FORMAT` once against the current state,
without installing it, so you can check a format before committing to it.
`prompt reset` restores both defaults. An invalid format exits with status 2
and names the unknown segment; `prompt` with anything else prints a usage
line and exits 1.

Setting `NSHELL_PROMPT` and `NSHELL_RIGHT_PROMPT` in the environment supplies
the corresponding format at session start; a `prompt left`/`prompt right`
line in `~/.nshellrc` overrides the variable, since the rc file runs later.

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
`alt-e`, `right`, `shift-tab`). Put `bind` lines in `~/.nshellrc` to apply
custom bindings on every launch, the same way `theme` lines do.

### Vi-mode cursor shape

When `NSHELL_VI_MODE` is enabled (see the man page's KEY BINDINGS section),
the cursor shape follows the vi mode: a steady block in normal mode, a
steady bar while inserting. This needs no configuration and does nothing
when vi mode is off or the terminal is not interactive.

## In `~/.nshellrc`

`.nshellrc` is not a separate configuration format: it is a file of plain
nshell commands, sourced once at startup before the first prompt. Put a
`theme` command there to start every session with your preset:

```sh
theme use tokyo-night
theme set prompt-git-dirty yellow --bold
```

See [examples/nshellrc.example](https://github.com/nerima-lisp/nshell/blob/main/examples/nshellrc.example)
for a complete starting point.

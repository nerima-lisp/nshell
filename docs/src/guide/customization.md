# Customizing colors

nshell colors the prompt, syntax highlighting, and completion menu from a
single **theme**: a mapping from named roles (`command`, `prompt-path`,
`completion-file`, and so on) to a style. The `theme` builtin lets you switch
between built-in presets or override individual roles, and `~/.nshellrc` runs
plain nshell commands at startup, so a `theme` line there applies on every
launch.

## The `theme` builtin

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

## Style-spec grammar

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

## Color depth and `NO_COLOR`

nshell detects the terminal's color depth (truecolor, 256-color, or the
16-color ANSI palette) and downsamples every hex color automatically: to the
nearest 256-color entry, or on a 16-color terminal to the palette slot with
the same hue (low-saturation colors become the grays). A preset written for
truecolor still renders sensibly over a plain ANSI connection. Setting `NO_COLOR` to any value
disables color output entirely, regardless of the active theme.

## Presets

`nshell` (the default), `ansi`, `mono`, `dracula`, `nord`, `gruvbox`,
`solarized-dark`, `solarized-light`, `catppuccin-mocha`, and `tokyo-night`.
`mono` and `ansi` are useful over a connection that cannot render truecolor;
`mono` drops color entirely and relies on bold/dim/italic/underline for
emphasis.

## Roles

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

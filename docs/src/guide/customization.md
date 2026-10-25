# Customization

The interactive startup file is `$XDG_CONFIG_HOME/nshell/init.lisp` when
`XDG_CONFIG_HOME` is an absolute path, or `~/.config/nshell/init.lisp`
otherwise. It can contain nshell commands and hook registrations. Use
`--no-config` to skip the file, or `--config PATH` to select another file.
Batch commands do not load the interactive startup file. When the default path
is used, nshell ignores a legacy `~/.nshellrc` with a one-line notice. If the
startup file has a syntax error, nshell reports it and continues to the prompt.

## Shell hooks

Register hooks from the startup file with
`nshell.application:register-shell-hook`. Use uppercase keyword names in
S-expression source. Hooks run in registration order, and duplicate callback
registrations are ignored. `nshell.application:remove-shell-hook` removes one
callback; `nshell.application:clear-shell-hooks` clears all callbacks or one
hook's callbacks.

| Hook | Boundary | Arguments |
|---|---|---|
| `:PREEXEC` | Before an interactive command runs | Command text |
| `:POSTEXEC` | After an interactive command finishes | Command text, exit status, duration in milliseconds |
| `:PROMPT` | Before the initial prompt and after a command finishes | Current directory, previous exit status |
| `:CD` | When `cd` changes the working directory | Previous directory, current directory |
| `:COMMAND-NOT-FOUND` | When interactive command lookup cannot find an executable | Command name |

For a missing command, hooks run in this order: `:PREEXEC`,
`:COMMAND-NOT-FOUND`, `:POSTEXEC`, then `:PROMPT`. When a command changes the
directory, `:CD` runs between `:PREEXEC` and `:POSTEXEC`. If a callback signals
an error, nshell reports it and continues with later hooks and the shell
session.

```lisp
(nshell.application:register-shell-hook
 :PREEXEC
 (lambda (text)
   (format t "Running: ~a~%" text)))
```

## East Asian character width

Set `NSHELL_EAST_ASIAN_AMBIGUOUS_WIDTH` to `auto` (the default), `narrow`, or
`wide` before starting nshell. With `auto`, an interactive terminal is probed
for its width setting. If it does not answer promptly, nshell checks `LC_ALL`,
then `LC_CTYPE`, then `LANG`: `ja`, `zh`, and `ko` locales select `wide`; other
locales select `narrow`. Batch commands do not probe the terminal. The selected
width affects prompt layout, input wrapping, cursor movement, completion
columns, transient panels, and history search.

## Customizing colors

`theme list` prints the available presets, `theme use NAME` selects one, and
`theme show` prints the active theme. Use `theme set ROLE SPEC` to override a
role or `theme reset` to restore the default preset. A style spec has an
optional foreground color followed by zero or more flags, separated by spaces.
Colors can be 3- or 6-digit hex values, one of the 16 ANSI color names, or
`normal`. Flags include `--bold`, `--dim`, `--italics`, `--underline`,
`--reverse`, and `--background=COLOR`.

nshell emits styling for 16-color, 256-color, and truecolor terminals. Set
`NO_COLOR` to a nonempty value to suppress styling.

## Customizing the prompt

Set the left and right prompt formats independently with `prompt left FORMAT`
and `prompt right FORMAT`. Each command changes the corresponding prompt for
the current session. A format is literal text with `{segment}` placeholders;
`{{` and `}}` insert literal braces. Available segments are `path`, `git`,
`host`, `user`, `status`, `exit`, `duration`, `time`, `jobs`, and `ai`. Empty
segments also remove one adjacent run of spaces.

`prompt show` prints both active formats, and `prompt preview FORMAT` renders a
format without installing it. `prompt reset` restores the environment formats
or the built-in defaults. Set `NSHELL_PROMPT` and `NSHELL_RIGHT_PROMPT` before
starting nshell to provide formats through the environment.

```text
prompt left '{user}@{host} {path}{git} $ '
```

## Customizing key bindings

`bind` lists key bindings, `bind KEY` shows one, `bind KEY ACTION` assigns an
action, `bind -e KEY` erases a binding, and `bind --reset` restores the
defaults. For example, `bind ctrl-k clear-input` makes Ctrl-K clear the input
line.

`Alt` is also called `Meta`. On macOS, configure the terminal's Option key to
send Meta or an Escape prefix if Alt bindings do not register.

### Structural editing

Structural editing moves through S-expressions, deletes a form at the cursor,
or moves a list boundary around a neighboring form. It edits the input buffer
without evaluating it. `up-list` leaves the surrounding list, and `down-list`
enters a child list. Slurp pulls a neighboring form into a list; barf moves a
form out. Deleted text can be restored with `Ctrl-Y`.

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

### Capturing the last command's output

Press `Ctrl-X` after a command to request a captured rerun. nshell shows the
command, its safety classification (`safe`, `confirm`, or `block`), and the
reason. A blocked command or one that requires a live terminal cannot run
through the capture runner. Press the displayed confirmation binding again to
run an eligible command. Any other key or a terminal resize cancels the
confirmation. The command runs again; nshell does not replay saved output.

### Vi mode

Set `NSHELL_VI_MODE=1` before starting nshell to use Vi key bindings. You can
also run `set -o vi` or `set +o vi` during an interactive session. The terminal
cursor is a block in normal mode and a bar while inserting; disabling Vi mode
restores the terminal's default cursor shape.

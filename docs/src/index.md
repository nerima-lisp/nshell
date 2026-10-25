# nshell

nshell is an interactive shell written in Common Lisp. Its command language
uses S-expressions, with bare command lines as shorthand for ordinary shell
commands. A parenthesized form is evaluated as Common Lisp when its head
resolves to a Lisp form; otherwise, the form names a shell command.

!!! note "Development preview"

    The command language implements a tested subset of shell behavior. Bare
    command lines are not a claim of POSIX or fish script compatibility. The
    `-c` option delegates commands to `/bin/sh`.

## Highlights

- **S-expression command language**: use forms such as `(echo ,(+ 2 3))` to
  pass a computed value to a command. `$NAME` passes a shell variable's value;
  `,EXPR` evaluates an expression for an argument.
- **Bare command-line sugar**: enter commands such as `echo hello` without
  wrapping them in parentheses.
- **Byte and value pipelines**: `|` connects byte streams, while `->` passes
  records through transformations such as `where` and `select`.
- **Syntax highlighting and diagnostics**: commands, paths, and strings are
  highlighted as you type; malformed S-expressions show a diagnostic and
  leave the input available for correction.
- **Completion knowledge base**: command and option facts describe candidates,
  including command names, flags, subcommands, and filesystem paths.
- **History-based editing**: suggestions use command history, `Ctrl-R` opens
  reverse search, and history expansion is available on bare interactive
  command lines.
- **Structural editing**: move through S-expressions, delete expressions, and
  slurp or barf list elements with editor key bindings.
- **Interactive controls**: themes, left and right prompts, key bindings,
  Emacs-style editing, and optional Vi mode.
- **Pipelines and control**: bare commands support byte pipelines, redirects,
  command sequencing, logical operators, and background jobs.
- **Lisp functions and control forms**: define functions with `defun`, bind
  local values with `let`, and use forms such as `if`, `when`, `cond`, and
  `dotimes`.

## Where to go next

- [Getting started](getting-started.md): run nshell and enter your first forms
  and commands.
- [Core concepts](guide/concepts.md): learn how forms, embedded values, and
  pipelines work.
- [Customization](guide/customization.md): configure hooks, themes, prompts,
  and editing keys.
- [Recipes](guide/recipes.md): work with structured pipelines and data
  conversions.
- [Built-in commands](reference/builtins.md): inspect the shell's command set.
- [Architecture](reference/architecture.md): read about the layered design and
  toolkit family.

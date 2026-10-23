# B04: Git shell integrations

Prerequisite: create a disposable Git repository and set its local `core.editor` and `core.pager` to nshell-compatible commands.

1. Add a local `!` alias that prints `B04_ALIAS_OK`, then invoke it.
2. Run an empty commit with the configured editor and save a commit message.
3. Run a command such as `git log` through the configured pager and quit the pager.

Pass when the alias output is clean, the commit succeeds with the entered message, and the pager returns control to Git.

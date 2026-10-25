# P09: Hook order and arguments

## Procedure

1. Set `NSHELL_READER=sexp` and start nshell with a temporary home and an isolated configuration directory.
2. Add one `register-shell-hook` call for each hook in the temporary `home/.config/nshell/init.lisp`. Have each callback print its name and arguments with `format`.
3. Confirm the initial `:prompt` event. Run a successful command, change to another temporary directory with `cd`, and run a command that does not exist.
4. Compare the trace with the signatures in `docs/src/guide/customization.md`. The order for a missing command is `:preexec`, `:command-not-found`, `:postexec`, then `:prompt`. For a successful directory change, `:cd` occurs between `:preexec` and `:postexec`.
5. Confirm that the shell returns to a usable prompt after each event.

## Pass condition

Each hook runs at its documented boundary, in the documented order, and receives its documented arguments. The missing-command hook runs for the failed lookup. A hook error is reported without stopping later hooks or the shell session.

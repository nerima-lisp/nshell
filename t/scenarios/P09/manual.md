# P09: Hook order and arguments

## Procedure

1. Start nshell with a temporary home and an isolated configuration directory.
2. Check `docs/src/guide/customization.md`, the pages under `docs/src/reference/`, and the exported symbols in `src/package-infrastructure.lisp` for registration APIs or public symbols for `preexec`, `postexec`, `prompt`, `cd`, and `command-not-found`. If a hook, its registration API, or its order and arguments are not documented, record that as a failure; do not infer its contract from private implementation code.
3. For each hook with a documented registration API and contract, register it to append its name and received arguments to a trace file. Run one successful command, change to a second temporary directory, and run a command that does not exist. Record missing hooks or unusable contracts as failures without guessing how to register them.
4. Compare the trace with the documented event order and signatures. Check the terminal after each command.

## Pass condition

Each hook runs at its documented boundary, in the documented order, and receives its documented arguments. The missing-command hook runs for the failed lookup. The shell returns to a usable prompt after all events.

# Q03: Continue after heap exhaustion

## Available coverage

The interactive shell does not expose a Common Lisp form evaluator. `nshell -c` and the `eval` builtin parse nshell command text, while startup configuration files contain nshell commands. The S-expression reader is a parser prototype that is not connected to the REPL.

The existing `storage-conditions-are-reported-and-the-repl-recovers` test injects a synthetic `storage-condition`. It checks the diagnostic, the absence of `Backtrace` and `#S(`, and execution of a later command. It does not assert the diagnostic line count or trigger a real SBCL heap exhaustion.

## Manual status

A PTY scenario that evaluates `(make-array (expt 10 12))` cannot use a current nshell entry point. Keep the real allocation check open until the shell provides a user-facing Lisp evaluation path.

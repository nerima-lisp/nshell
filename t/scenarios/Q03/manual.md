# Q03: Continue after heap exhaustion

## Available coverage

With `NSHELL_READER=sexp`, the interactive REPL evaluates Common Lisp forms. The existing `storage-conditions-are-reported-and-the-repl-recovers` test injects a synthetic `storage-condition`; it checks the diagnostic, the absence of `Backtrace` and `#S(`, and execution of a later command.

The proposed probe `(make-array (expt 10 12))` did not raise a `storage-condition` in an SBCL process with a 128 MiB dynamic space. A 64 MiB dynamic space was too small for SBCL to start. The current runner also rejects `ulimit -v`, so this work package has no reliable per-process memory cap for a safe PTY exhaustion test.

## Manual status

Closed for WP-L04. Reopen the real exhaustion scenario when WP-R07 provides a bounded per-process memory limit. The synthetic condition test does not establish behavior under actual heap exhaustion.

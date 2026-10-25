# Q03: Continue after heap exhaustion

## Available coverage

With `NSHELL_READER=sexp`, the interactive REPL evaluates Common Lisp forms. The `storage-conditions-are-reported-and-the-repl-recovers` unit test injects a synthetic `storage-condition`; it checks the diagnostic, the absence of `Backtrace` and `#S(`, and execution of a later command. This unit test is not an executable Q03 scenario and does not verify actual heap exhaustion.

The proposed heap-exhaustion probe `(make-array (expt 10 12))` did not raise a `storage-condition` in an SBCL process with a 128 MiB dynamic space (SBCL's allocation space). A 64 MiB dynamic space was too small for SBCL to start. The scenario runner, `scripts/run-scenarios.py`, rejects `ulimit -v`, so there is no reliable mechanism to impose a bounded memory limit on the test process for a safe PTY exhaustion test.

## Manual status

For WP-L04, Q03 is closed without a real-exhaustion acceptance result. A reliable mechanism to impose a bounded memory limit on the test process is required before the real exhaustion scenario can run. The coverage index counts this manual record; that count does not mean Q03 passed.

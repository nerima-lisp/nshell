# Command-execution timeout audit

Every place `src/` spawns, waits on, or reads from an external OS process,
and whether it is bounded — "適切に" (appropriately), not "always killed
after N seconds regardless of context."

## The real bug this audit found and fixed

`run-external` (`infrastructure/acl/syscall-process.lisp`) — the path for
every plain foreground external command typed at the interactive prompt —
applied `*external-command-timeout*` (30s default) unconditionally. That is
the *opposite* failure mode from a missing timeout: typing `vim file.txt`,
`ssh host`, or `top` at the prompt got the process SIGTERM'd, then SIGKILL'd,
30 seconds in, mid-edit, with no exemption for a foreground program a human
is actively driving.

Fixed with `%foreground-external-command-timeout`: the timeout applies only
when `*standard-output*` is **not** `interactive-stream-p` at the moment the
command runs. `*standard-output*` already reflects any active per-command
redirect (`redirect-output` rebinds it), so this one predicate correctly
covers all three cases:

| context | `*standard-output*` | timeout applied |
|---|---|---|
| `vim file` at an interactive prompt | real terminal | no — matches real-shell `exec`/foreground semantics; only the user (Ctrl-C) or the command itself ends it |
| `long_cmd > out.txt`, even mid interactive session | file stream | yes — nothing is watching, so an unbounded wait is a real hang risk |
| `nshell -c "..."` / scripts / piped stdout | non-interactive | yes |

Verified empirically, not just by inspection: `interactive-stream-p` returns
`T` for SBCL's real `*standard-output*` under `script(1)` (a genuine PTY) and
`NIL` under a plain pipe — confirmed by direct `sbcl --eval` runs before
writing the fix. A new end-to-end test,
`e2e-main-interactive-pty-foreground-pipeline-ignores-external-command-timeout`
(`t/e2e/test-smoke.lisp`), spawns real `nshell` under a real PTY with
`*external-command-timeout*` overridden to `0.5`, runs `sleep 2; echo
pty-outlived-timeout`, and asserts the echo occurs and no timeout message
appears — a command that would be killed twenty times over under the old
code now completes because the terminal is real. The four existing
non-interactive timeout tests (`run-external-times-out-and-returns`,
`run-external-capture-times-out-and-returns`, and their capture-path
counterparts) are untouched and still pass: SBCL's `*standard-output*`
under the `--non-interactive` batch test runner is never
`interactive-stream-p`, so this change is invisible to every prior test.

## Confirmed sound, no change needed

- **`run-external-capture`** (command substitution, `$(...)`) — delegates to
  `cl-process-kit`'s `run` with `:timeout *external-command-timeout*
  :on-timeout :return`; single choke point, no bypass. Correctly unconditional
  — command substitution has no terminal of its own to be interactive with.
- **`spawn-pipeline` / `%wait-pipeline-with-output`** — foreground OS-pipe
  pipelines bound by the same `*external-command-timeout*` via
  `%wait-pipeline-exit-with-timeout`. `spawn-pipeline-async` (background `cmd
  &`) intentionally has no wait/timeout at spawn time — correct, it is
  job-control-managed from there.
- **`%execute-external-pipeline-stage`** — calls `sb-ext:run-program`
  directly but reuses the same `*external-command-timeout*` special and the
  ACL layer's `%wait-process-with-copiers`, not a hand-rolled bypass.
- **`git.lisp`** — every git subprocess call goes through `%run-git`, the
  sole spawn point, bounded by `*git-command-timeout*` (3s). No parallel
  hand-rolled path exists.
- **`spawn-async` / `wait-job` / `%wait-job-pgid`** (backing `cmd &`, `fg`,
  `bg`, `wait`) — block indefinitely by design. A background job or a
  foreground-job wait a human actively manages via `fg`/`bg`/Ctrl-Z/`kill` is
  not a hang risk any more than the same operation in bash or fish.

## Confirmed correct as-is: `%builtin-exec`

`%builtin-exec` (`application/builtin-commands.lisp`) calls
`sb-ext:run-program` directly with `:wait t`, no timeout, and no
`%spawn-in-own-process-group`/`%with-foreground-process-group` call. This is
not a gap: `exec` semantically **replaces** the shell (SBCL cannot literally
`execve(2)` its own image, so nshell approximates by waiting for the child
and then exiting nshell itself with the child's status), so there is no
shell left afterward to protect with a timeout, and no subordinate job to
isolate into its own process group — the exec'd program simply continues in
whatever process group nshell itself already occupied, which is what real
`exec` does. Adding either would be a regression, not a fix. Left
unchanged; recorded here so a future audit does not re-flag it.

## Not a live risk today: `pty.lisp` and `pty-spawn.lisp`

`pty-read`/`pty-write` are raw blocking syscalls with no timeout, and
`%wait-for-pty-child-ready` could block forever if a forked child never
signals readiness. `pty-spawn` currently has zero call sites in `src/`
outside its own file and `package.lisp`'s export list — it exists for the
PTY-based e2e test harness (`t/e2e/test-smoke.lisp`'s
`e2e-main-interactive-pty-*` tests), not any live shell code path. Not a
present risk; would need a bound before being wired into a real interactive
feature.

## Current conclusion (2026-08-26)

The production-audit fixes removed the default timeout. The interactive gate
was found to be bypassed on the path real interactive commands take
(`%execute-external-pipeline-stage` and `run-external-capture` read the raw
special), so an interactive `sleep 30` was still killed at 30 seconds. The
resolution removes the default bound entirely rather than re-scoping it:

- `*external-command-timeout*` and `*command-substitution-timeout*` now
  default to `nil` (unbounded), matching POSIX shells, which impose no
  execution ceiling in any mode. A long build, an editor, or an SSH session
  is legitimate foreground work interactively *and* in scripts.
- Bounding is the caller's job: tests and the completion-help path bind the
  specials to finite values, and external supervision (`timeout(1)`, CI job
  limits) owns script-level runaway protection. A security review proposed
  restoring a finite non-interactive fallback; that was declined as it would
  re-break batch scripts running legitimate >30s commands — the original
  production blocker.
- The table above therefore no longer describes default behavior: with the
  shipped defaults, no foreground external command or command substitution
  times out unless a caller binds the special. The gate function
  `%foreground-external-command-timeout` remains, and still bounds
  non-interactive runs whenever the special *is* bound.

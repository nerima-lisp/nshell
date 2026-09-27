# FR-010 PTY capture gate retry

## Result

The gate did not pass in this retry. The production foreground command path remains
on the pre-existing SBCL process fallback. The PTY implementation and ring buffer
remain available for a later retry.

## Root cause

The PTY runner started the child with `:new-session-p nil` in
`src/infrastructure/acl/pty-spawn.lisp:221-230`. The child therefore executed
`setpgid` but did not call `setsid` or claim the PTY slave as its controlling
terminal (`src/infrastructure/acl/pty-spawn-child.lisp:102-111`). Input forwarding
wrote `^Z` bytes to the PTY master, but the slave was not a controlling terminal
with the child process group as its foreground group. Consequently the child did
not produce the stop status that `pty-process-status` polls with
`WNOHANG|WUNTRACED|WCONTINUED` (`src/infrastructure/acl/pty-spawn.lisp:170-179`),
and `%wait-terminal-processes` waited indefinitely (`src/application/manage-job-wait.lisp:3-12`).
This matches the original failure: `PTY job condition timed out; output: ""` and
no prompt after `sleep 100` plus Ctrl-Z (`docs/notes/ai-native-requirements.md:462`).

The retry candidate changed the PTY child to `:new-session-p t`. It also added a
shell-context field to carry `pty-process-output` into the existing
`last-output` explain context. The candidate compiled through the Nix build's
compile phase, but the full check phase did not complete, so it was reverted and
was not enabled as the production path.

## Gate evidence

The delegated tmux run used the required dedicated socket and `/dev/null` tmux
configuration. With the specified `env -i` environment, bare commands were not
available because `PATH` was absent. Absolute-path supplemental checks observed:

| Check | Result |
| --- | --- |
| `sleep 100`, Ctrl-Z, `jobs`, `fg`, Ctrl-C | verified with `/bin/sleep` |
| `bg`, `jobs` | verified with `/bin/sleep 5` |
| Vim start and `:q` | verified with `/usr/bin/vim` |
| `yes \| head -3` | verified with `/usr/bin/yes` and `/usr/bin/head` |
| Resize and `tput cols` | verified at 80 and 120 with `/usr/bin/tput` |
| `cat` input and Ctrl-D | verified with `/bin/cat` |
| Ctrl-Z followed by another command | verified; shell remained usable |

The exact bare-command checks were not valid because the mandated environment had
no `PATH`; they reported `command not found`. The supplemental checks are useful
evidence for the PTY harness but do not replace the named e2e/integration gate.

## Verification

- `git log -1 --oneline`: verified `d46e1f7`, equal to `origin/main`.
- `git diff --check`: passed after restoring the fallback.
- `nix build --no-link -L .#checks.aarch64-darwin.default`: candidate compile
  phase reached `checkPhase`, but the check phase produced no output for several
  minutes and was interrupted. Exit status: 130. No `0 failed` summary was
  obtained.
- PTY e2e/integration CI: not run in this macOS session.

## Follow-up blocker

Before enabling PTY foreground execution, rerun the complete Nix checks and the
non-sandboxed Linux integration job, then repeat the exact tmux checklist with a
usable command path while preserving the assertions.

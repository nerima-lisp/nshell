# FR-010 PTY capture gate retry

## Result

The PTY candidate did not pass the production gate and is not connected to the
foreground command path. The fallback remains active while the PTY/ring-buffer
implementation is retained for a later retry.

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

The retry candidate changes the PTY child to `:new-session-p t` and can be
invoked by the foreground PTY runner. It also adds a
shell-context field to carry `pty-process-output` into the existing
`last-output` explain context. The candidate compiled through the Nix build's
compile phase and is currently enabled in this worktree; the full check phase
timed out, so no production-readiness claim is made.

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
  phase completed and `checkPhase` ran, but cl-nix-forge terminated the test
  runner at its 1800 second limit. Exit status: 1 (underlying builder exit 124).
  No `0 failed` summary was obtained.
- `nix develop -c sbcl --script run-tests.lisp`: started separately after the
  sandbox timeout; no summary was available when this note was updated.
- PTY e2e/integration CI: not run in this macOS session.
- Manual tmux checklist: PTY input/output, resize, `cat`, and
  shell usability worked, but direct foreground execution exposed a
  `PTY-PROCESS` type error because the production spawn wrapper had not yet
  been connected to the PTY runner. The wrapper was corrected in the retry,
  but Ctrl-Z/fg recovery still failed, so the production route was restored to
  the fallback.

## Follow-up blocker

Before declaring the PTY foreground execution production-ready, complete the
non-sandboxed suite, the Linux integration job, and the exact tmux checklist with
a usable command path while preserving the assertions.

# D09: Attach to a tmux session

1. Start a named session with an outer shell that remains after nshell exits: `tmux new-session -d -s d09 'nshell; exec sh'`.
2. Attach with `tmux attach -t d09`, detach with `Ctrl-b d`, then attach again.
3. In nshell, run `printf D09_ATTACH_OK` and then run `exit`.
4. At the outer shell prompt, run `printf D09_SESSION_LIVE` to confirm the tmux session remains usable.

Pass when `D09_ATTACH_OK` appears after reattachment and `D09_SESSION_LIVE` appears after nshell exits.

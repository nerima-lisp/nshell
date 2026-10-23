# F05: Terminal title

1. Start nshell in a terminal and inspect the title while the prompt is idle.
2. Run `sleep 30` and inspect the title while it is still running, then stop it with `Ctrl-c`.
3. Create a second directory under a temporary parent, change into it, and inspect the title again.

Pass when the idle title shows the initial working directory, the running title reflects `sleep`, and the title updates to the second working directory.

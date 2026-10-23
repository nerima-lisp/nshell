# Q07: Report history write failure on a full disk

## Procedure

1. Use a disposable VM with a small test filesystem or a quota-limited test account. Place the temporary home and history directory on that filesystem. Do not fill a workstation or the host root filesystem.
2. Start nshell, then exhaust only the test filesystem using the VM or quota fixture.
3. Submit a harmless command to trigger a history write. Capture the history error, then submit a second harmless marker command to confirm the prompt remains usable.
4. Exit the shell and inspect the history file state and process exit status.

## Pass condition

The history write failure is reported clearly and does not produce a debugger dump or disappear silently. The second command runs before the user exits. Record the filesystem or quota setup and available free space at failure.

# B10: Login environment in GUI shell queries

This check covers the `$SHELL -ilc env` call used by GUI tools.

Prerequisite: use an IDE that launches a login shell to collect its environment, with nshell configured as `$SHELL`.

1. Add a recognizable directory to the nshell login `PATH` through the account's normal configuration.
2. Restart the IDE and inspect the environment collected by its integrated terminal or task runner.
3. Confirm that startup messages did not appear in the captured environment output.

Pass when the added path is present and the environment output contains no initialization text.

# B08: IDE integrated terminals

This check covers the integrated terminals in VS Code and JetBrains IDEs.

Prerequisite: configure each IDE's terminal shell path to nshell and open a new integrated terminal.

1. In each IDE, print `SHELL`, `PATH`, and `B08_IDE_OK`.
2. Run a command that uses a path configured by the user's shell setup.
3. Close the terminal and open a new one.

Pass when both IDEs start nshell, expose the configured path, run the command, and reopen without startup errors.

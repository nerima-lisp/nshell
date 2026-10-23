# A04: macOS login environment

Prerequisite: use a macOS account whose login environment is configured by all three sources. Before testing, record one known `PATH` entry contributed by `path_helper`, one by nix-darwin, and one by Home Manager.

1. Start `nshell -l -i` from a clean terminal session.
2. Print `PATH` in nshell and in the account's normal macOS login shell.
3. Check that the three recorded entries are present in nshell's `PATH`. Use the login-shell output as the control for identifying each contribution.

Pass when all three path contributions are present in the nshell session.

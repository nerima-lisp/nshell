# A05: Linux profile environment

Prerequisite: use a Linux account and record a specific variable value or `PATH` entry that `/etc/profile` supplies for that account.

1. Start `nshell -l -i` in a fresh terminal session.
2. Print the recorded value and `PATH` in nshell and in a login session using the system shell.
3. Check that the recorded value or entry appears in nshell. Use the system-shell login as the control for identifying the `/etc/profile` contribution.

Pass when nshell exposes the same `/etc/profile` value and path entry.

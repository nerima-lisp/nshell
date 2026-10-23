# A07: Quiet noninteractive SSH login

Prerequisite: SSH access to a disposable host with nshell registered as the remote account's login shell.

1. Run `ssh host printf A07_REMOTE_OK` from a clean client shell.
2. Capture standard output and standard error separately.

Pass when standard output is exactly `A07_REMOTE_OK`, standard error is empty, and the remote command exits with status zero.

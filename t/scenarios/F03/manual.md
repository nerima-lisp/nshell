# F03: SIGTERM exit status

1. Start nshell as a child process from a test supervisor and record its process ID.
2. Send `SIGTERM` to that process.
3. Wait for it and record the exit status.

Pass when nshell exits and the supervisor observes status 143.

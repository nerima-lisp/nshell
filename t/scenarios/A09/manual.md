# A09: SIGHUP on terminal close

1. In a disposable terminal, start a background process that traps `SIGHUP` and writes a marker under its temporary home directory.
2. Close the terminal window without first exiting nshell.
3. From a separate session, check for the marker and confirm that the nshell process ended.

Pass when the trap writes the marker and nshell exits after the terminal closes.

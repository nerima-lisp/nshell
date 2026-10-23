# H05: private mode

1. Start nshell with an isolated home directory and run `echo H05_EXISTING_ENTRY`; exit normally so the history contains one known entry.
2. Enable private mode with the documented user-facing control before entering any other command. If the candidate has no such control, record the UC as unsupported and stop.
3. Run `echo H05_PRIVATE_ENTRY` and exit normally.
4. Inspect the history file, then start a second shell with the same home and search for both marker entries.

Pass when `H05_PRIVATE_ENTRY` is absent from persistent history and reverse history search, while `H05_EXISTING_ENTRY` remains available. At the revision under test, if no public private-mode control is documented, record the UC as unsupported and stop; do not infer one from private code.

# N06: persistent variables

1. Start nshell with an empty, isolated home directory.
2. Set a universal variable with `set -U N06_PERSISTED marker` and exit normally.
3. Start a new nshell process with the same home and run `echo $N06_PERSISTED`.
4. Remove the variable with `set -e N06_PERSISTED`, then start one more process and confirm it is absent.

Pass when the second process prints `marker` and the final process no longer sees the variable. At the revision under test, if `set -U` is documented as unsupported, record the UC as unsupported and stop; do not infer persistent-variable behavior from private code.

# A06: Login variables

1. Record the current values of `SHLVL`, `USER`, and `SHELL`.
2. Start a child login session with `nshell -l -i`.
3. Print those three variables in the child, then exit.

Pass when the child's `SHLVL` is one higher and its `USER` and `SHELL` match the inherited values.

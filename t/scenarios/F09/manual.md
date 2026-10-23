# F09: Mouse reporting configuration

1. Capture the PTY byte stream while nshell starts without configuration. Check that it contains neither `ESC[?1000h` nor `ESC[?1006h`.
2. Check `docs/src/guide/customization.md` and `docs/src/reference/` for a documented mouse-reporting setting. If none is documented, record configuration as unsupported and the UC as failed; do not guess a setting name. Otherwise, place the setting in an isolated `$XDG_CONFIG_HOME/nshell/init.lisp` and restart nshell with that `XDG_CONFIG_HOME`.
3. Capture the enabled session and confirm it emits a mouse-enable sequence. Exit nshell and confirm it emits the matching disable sequence (`ESC[?1000l` or `ESC[?1006l`).

Pass when the default session emits no mouse-enable sequence, the configured session enables mouse reporting, and exit disables the mode it enabled.

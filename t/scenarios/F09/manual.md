# F09: Mouse reporting stays disabled

1. Launch nshell in a PTY with the default environment and capture the output bytes.
2. Run `cat marker.txt` and confirm that it prints `F09_READY`.
3. Exit nshell.

Pass when the session exits with status 0 and emits neither `ESC[?1000h` nor `ESC[?1006h`.

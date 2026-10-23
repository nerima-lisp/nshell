# F11: Color modes and NO_COLOR

1. Start separate sessions with `TERM=xterm`, `TERM=xterm-256color`, and `TERM=xterm-256color COLORTERM=truecolor`.
2. In each session, type the same command with syntax highlighting and capture the raw PTY output.
3. Check SGR codes: 16-color output uses the standard 8/16-color codes, 256-color output uses `38;5;n` or `48;5;n`, and truecolor output uses `38;2;r;g;b` or `48;2;r;g;b`.
4. Start another session with `NO_COLOR=1`, repeat the command, and check that no color SGR styling is emitted.

Pass when each mode uses its stated SGR form, `NO_COLOR` suppresses color styling, and all sessions render the same command text.

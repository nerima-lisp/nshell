# F12: Emacs M-x shell

1. Start Emacs and use `M-x set-variable` to set `shell-file-name` to the absolute path of the nshell executable. Enter the path as a double-quoted string at the value prompt.
2. Run `M-x shell` and wait for the nshell prompt in the `*shell*` buffer.
3. Run `printf 'F12_EMACS_SHELL_OK\n'` and confirm the marker appears as output.
4. Enter another command, move through its text, and press Enter. Confirm the command runs and Emacs continues to accept input without displaying raw terminal control sequences.

Pass when the marker appears, the subsequent command runs, and Emacs accepts further input without displaying raw terminal control sequences.

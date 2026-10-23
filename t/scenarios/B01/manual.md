# B01: Vim shell commands

Prerequisite: Vim is available. Create a scratch directory, set `TMPDIR` to it, and create a disposable text file there so Vim's temporary files stay in scratch. Set `SHELL` to nshell before starting Vim so `:!` and `:r !` use nshell.

1. Open the file in Vim and run `:!printf B01_BANG_OK`.
2. Run `:r !printf B01_READ_OK`.
3. Inspect the command output and the inserted file contents, then quit Vim.

Pass when `B01_BANG_OK` is shown and `B01_READ_OK` is inserted into the file without leaving Vim in a broken terminal state.

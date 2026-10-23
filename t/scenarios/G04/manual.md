# G04: kill ring and yank-pop

Key notation: `C-x` means hold Control and press x; `M-x` means hold Alt or Meta and press x. On macOS, use Option when it is configured as Meta.

1. Start nshell in a real terminal, enter `ALPHA`, then press `C-a` and `C-k` to kill that text.
2. Enter `BRAVO`, then press `C-a` and `C-k` to add a second distinct entry to the kill ring.
3. Enter `echo `, press `C-y` to yank the most recent entry, then press `M-y` to cycle to the older entry.
4. Confirm the input line now reads `echo ALPHA`; press Enter and confirm it prints `ALPHA`.

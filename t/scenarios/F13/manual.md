# F13: Startup terminal response

1. Use a terminal emulator that answers the cursor-position report sent during startup.
2. Start nshell in a clean terminal and capture both the startup stream and visible screen.

Pass when the prompt is clean and the emulator's cursor-position response (`ESC[row;columnR`) does not appear as input or output text.

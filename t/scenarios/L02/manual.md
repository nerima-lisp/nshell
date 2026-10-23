# L02: Git prompt responsiveness in a large repository

1. Prepare a disposable Git checkout containing at least 20,000 tracked files, with the prompt configured to show branch and dirty status. Run on an idle Apple Silicon macOS host and an idle CI Linux host; keep the checkout, build, and terminal settings fixed for each host. `NSHELL_PROMPT` replaces the prompt format, so set it in the launcher environment to a unique format such as `L02_PROMPT_<run-id> {path}{git} `, retaining `{git}` so branch and dirty status remain visible.
2. Use a PTY harness and a monotonic clock. Measure startup from process creation to the configured prompt marker, then measure from sending an empty Enter to the next occurrence of that marker. Do not type the prompt marker into the shell.
3. Run five fresh-process warmups, exclude them, then collect 30 fresh-process measurements. Repeat the complete run once on the same revision and host to estimate the harness spread. Report the two medians and the sample range for each measurement.
4. During each session, type and run `echo L02_READY`; record whether key echo or command execution waits for Git status.
5. Confirm branch information appears when available and the prompt remains usable if the Git probe is slow or times out. Record the repository fixture, platform, build, sample counts, warmups, medians, and ranges.

Pass when both repeated-run medians are at most 150 ms for startup and 60 ms for empty Enter, and Git status work does not block typing or command execution. If the measured spread crosses a target or the two runs disagree, report the result as inconclusive and repeat on a quieter host; do not claim a pass from a single run.

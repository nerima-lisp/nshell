# scripts/perf: performance baseline and regression gate

These scripts compare two nshell binaries on one machine and decide whether the candidate regressed.
Absolute times on a shared, loaded machine move by a factor of two or more between runs, so the gate judges the difference between interleaved runs of the two binaries.

| File | Role |
|---|---|
| `compare.sh` | The gate: measure baseline A and candidate B, print the verdict table, write JSON |
| `noise.sh` | Measure one binary against itself and write the noise file `compare.sh --noise` takes |
| `perfharness.py` | PTY driver: runs the B1/B2 workloads in ABBA order and writes raw samples |
| `perfstats.py` | Bootstrap confidence intervals, thresholds, verdict, table and JSON |
| `legacy-bench.sh`, `legacy-bench.lisp` | Run the `bench/` benchmarks of this checkout against the nshell system of one source tree (informational) |
| `b3-*` | B3 per-key consing and I/O counts, measured in-process |

## Running

A `BINARY` is the `bin/nshell` wrapper of an nshell package build (for example `result/bin/nshell` after `nix build`).
The cold-startup metric follows its two wrapper scripts to `nshell.core`, so a binary without that layout makes the run inconclusive.

Run the scripts under a lock file shared with builds and other benchmarks so they do not overlap:

```sh
lockf LOCKFILE scripts/perf/noise.sh --out NOISE_DIR BINARY
lockf LOCKFILE scripts/perf/compare.sh \
  --noise NOISE_DIR/noise.json --out RESULT_DIR BASELINE_BINARY CANDIDATE_BINARY
```

`noise.sh` runs the full `compare.sh` protocol with the same binary as both arms.
Rerun it when the machine or the harness changes, and pass `noise.sh` the same `--harness-arg` sample-count options that `compare.sh` will use.
Without `--noise`, `compare.sh` uses the thresholds in the table under "Statistics and thresholds" alone and prints a warning.
`--note TEXT` records what differs between the two binaries (for example the build path) in the table and the JSON.

To include B3, pass both source trees: `--base-src DIR --cand-src DIR`.
`compare.sh` then runs `b3-measure.sh` in ABBA order (`--b3-blocks N` repeats the A, B, B, A runs; default 1) with the caller's environment, which must provide what `b3-measure.sh` requires (`B3_SBCL`, `CL_SOURCE_REGISTRY`).
Without the source trees, the table reports B3 as not measured.
`noise.sh --src DIR` adds B3 to the noise file the same way.

`--quick` uses tiny sample counts; use it only to check that the harness works.
Its verdicts mean nothing.

Requirements: `python3` (standard library only; tested with 3.14), `uptime`, `ps`, `lockf`. Tested on macOS only.
The cold-startup metric uses `F_NOCACHE` and `mincore`, which are macOS-specific.

## Result directory

| File | Content |
|---|---|
| `verdict.txt` | Human-readable table, uptime before and after, reasons for fail and inconclusive rows |
| `verdict.json` | The same as machine-readable JSON (`schema: nshell-perf-verdict/1`) |
| `raw.json` | Every sample, grouped by block, arm and process |
| `noise.json` | Only from `noise.sh` |
| `uptime-before.txt`, `uptime-after.txt` | `uptime` around the whole run, including B3 |
| `conditions.txt`, `harness.log`, `b3-*.json`, `b3-*.log` | Inputs and logs |

## Measured items

Every nshell process gets a fresh temporary `HOME` and XDG directories, `NSHELL_AI_COMMAND=/nonexistent`, `PATH=/usr/bin:/bin`, `TERM=xterm-256color` and a 100x24 PTY.
A redraw counts as finished when the line editor writes its closing cursor-shape sequence `ESC [ 0 SP q`.

### B1 startup (one process per sample)

| Metric | Definition |
|---|---|
| `startup.interactive_warm` | From fork to the first finished redraw of the prompt |
| `startup.interactive_history_10k` | The same, with a 10,000-record history file; the warm-up samples check that history suggestions appear |
| `startup.interactive_cold` | The same, with the Lisp core image not in the page cache (see below) |
| `startup.c_true` | `nshell -c true` until exit (`-c` is delegated to `/bin/sh` by the wrapper) |
| `startup.command_true` | `nshell --command true` until exit |
| `startup.json_command_true` | `nshell --json --command true` until exit; `n/a` while a binary does not support `--json` |

A cold start needs an empty page cache, and `purge` needs root.
For each cold sample the harness instead writes a fresh copy of the binary's `nshell.core` with `F_NOCACHE`, checks with `mincore` that under 1% of its pages are resident, and starts nshell through a copy of the wrapper scripts that points at the copy.
Only the core image is cold; the SBCL runtime, libc and the wrapper scripts stay cached.

### B2 key latency (long-lived processes)

Each session starts nshell, pastes a prefill with bracketed paste, then sends 20 warm-up keys and 200 measured keys, alternating a character and Backspace.
The buffer therefore keeps its prefilled length, and every key causes a redraw and an autosuggest lookup.
Latency is the time from writing the key to the end of the redraw it caused.
For a typed character, that is the first redraw showing the end of the buffer plus the character. Earlier redraws of the previous state are skipped.
If no such redraw arrives within 20 s, the session counts as failed.

| Metric | Prefill | Typed |
|---|---|---|
| `key.bare_1` | empty (buffer of 0 or 1 characters, command-name position) | `x` |
| `key.bare_200` | `echo ab ab …`, 200 characters | `x` |
| `key.bare_1000` | the same, 1000 characters | `x` |
| `key.sexp_200` | `(echo ab ab …`, 200 characters | `x` |
| `key.path_20k` | `cat big/item-1`, with `big/` holding 20,000 entries | `2` |

History is empty in these sessions, so autosuggest falls back to filesystem completion.
In `key.path_20k` that lists the 20,000-entry directory on every key, so this scenario is slower than the others in both arms; that is a known cost of the product, not a harness fault.

### Other items

| Metric | Definition |
|---|---|
| `tab.path_small`, `tab.path_20k` | Paste `cat small/uniq` or `cat big/uniq`, press Tab, time until a redraw shows `unique-target.txt`; Ctrl-U clears the line between samples |
| `prompt.empty_enter` | Enter on an empty line until the new prompt's redraw finishes |
| `rss.idle_kb` | `ps` RSS of the `key.bare_1` sessions right after the first prompt |
| `rss.peak_kb.<scenario>` | Peak RSS (`wait4` `ru_maxrss`) of each B2 session |

## Sample counts and order

| Item | Per run |
|---|---|
| Startup | 1 warm-up block (discarded) and 12 measured blocks per metric: 24 samples per arm |
| B2 keys | 2 blocks per scenario: 4 processes per arm, 800 measured keys per arm |
| Tab | 2 blocks: 4 processes per arm, 15 samples per variant per process after 2 warm-up samples |
| Prompt | 2 blocks: 4 processes per arm, 30 samples per process after 3 warm-up samples |

A block runs A, B, B, A, so a linear drift in machine load affects both arms equally.
At a load average around 70, one full run takes roughly 15 minutes; most of it is `key.path_20k`, where each key takes about 50-200 ms.
The counts can be raised with `--harness-arg`, for example `--harness-arg --startup-blocks --harness-arg 20`.

## Statistics and thresholds

For each metric the gate computes the difference B − A of a statistic (median, p95, p99 or mean) and its 95% confidence interval by a hierarchical bootstrap with 2000 iterations and a fixed seed.

| Rule | Threshold on the CI lower bound of B − A |
|---|---|
| Startup median | larger of +5% and +3 ms |
| Key p95 | larger of +5% and +1 ms |
| Key p99 | larger of +15% and +2 ms |
| B3 per-key consing (mean) | +10% |
| B3 per-key `stat`, file I/O, spawn | fail when every candidate run counts more than every baseline run; scenarios B3 marks `"io_gate":false` are reported, not gated |

With a noise file, each threshold is raised to twice the same-binary variation when that is larger.
The variation of a metric is `max(|CI low|, |CI high|)` of its A-vs-A difference, stored relative to the noise run's statistic and scaled to arm A of the current compare run.
Tab, prompt, RSS and key medians are reported with intervals but are not gated.

## Outcomes and exit codes

| Exit | Outcome | Meaning |
|---|---|---|
| 0 | pass | No gated metric's CI lower bound exceeds its threshold |
| 1 | fail | At least one gated metric's CI lower bound exceeds its threshold |
| 3 | inconclusive | No fail, but the run cannot support a pass: a gated metric has fewer than 75% of its planned processes valid, a correctness check failed (missing history suggestion, warm core, frame without the typed character), the harness stopped early, or a requested B3 run failed |
| 2 | usage error | Bad arguments or unreadable input |

A fail outranks inconclusive.
A row marked `pass*` passed the rule, but its CI upper bound exceeds the threshold, so a regression of that size is not excluded at this sample count.
`noise.sh` exits 0 whenever it wrote the noise file and warns if the binary failed against itself.

## Relation to bench/ and older scripts

`bench/*.lisp` is the ASDF system `nshell/benchmark` (in-process completion API and process-launch benchmarks).
`compare.sh --legacy` runs it through `legacy-bench.sh` once for arm A, then once for arm B, and stores `legacy-A.jsonl` and `legacy-B.jsonl` beside the results.
These numbers are informational and not gated; with one run per arm they are not an A/B comparison.
`--legacy` requires `--base-src` and `--cand-src`: the nshell system is loaded from each arm's source tree, and `bench/` is compiled from this checkout.
`legacy-bench.sh` needs SBCL (`B3_SBCL` or `sbcl` on `PATH`) and `CL_SOURCE_REGISTRY` naming the toolkit dependencies.
To run `--legacy` without B3, add `--b3-blocks 0`.

For completion in a 20,000-entry directory, use `key.path_20k` and `tab.path_20k` instead of `bench/completion-filesystem.sh` and `bench/completion-filesystem-stages.sh`.

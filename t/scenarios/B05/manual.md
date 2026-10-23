# B05: Make shell selection

Prerequisite: GNU Make, nshell, and a disposable directory. Create this `Makefile` there:

```make
.PHONY: check
check:
	@printf 'B05_MAKE_OK\n'
```

1. Run `make check` to use Make's default shell.
2. Run `make SHELL=/absolute/path/to/nshell check` to set Make's `SHELL` make variable explicitly.
3. Capture output and exit status for both runs.

Pass when both recipes print `B05_MAKE_OK` and return status zero.

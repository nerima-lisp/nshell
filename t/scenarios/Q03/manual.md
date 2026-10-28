# Q03: Continue after heap exhaustion

## Coverage

The `storage-conditions-are-reported-and-the-repl-recovers` unit test injects a synthetic `storage-condition`. It checks the diagnostic, the absence of `Backtrace` and `#S(`, and execution of a later command. It does not verify actual heap exhaustion. The PTY scenario `Q03-real-heap-exhaustion` covers the real allocation path.

The normal nshell executable saves SBCL runtime options in its core, so its heap size cannot be changed by adding `--dynamic-space-size` after the executable. The scenario runner does not reject `ulimit -v`; it also has no setting for imposing a per-child memory limit. `ulimit -v` limits total virtual address space, including the SBCL runtime, core, and mappings as well as the dynamic heap. Its behavior and available limits differ by OS, and it can prevent startup or cause an OS-level failure before nshell handles a storage condition. It is not used.

Other methods considered:

- `(make-array (expt 10 12))` did not signal a `storage-condition` in the initial probe.
- A 64 MiB dynamic space was too small for SBCL to start. A 128 MiB `packages.q03` build failed while compiling nshell because cl-nix-forge also applies the dynamic-space limit to the build compiler.
- Retaining allocations in a loop consumed the recovery headroom and ended in SBCL's fatal heap-exhaustion path. The scenario does not use that loop.
- A separate executable built with a 256 MiB SBCL dynamic space starts successfully on Darwin. The scenario first checks that exact size and that ordinary allocations work, then requests one 268,435,456-character string. The request is larger than the available dynamic space while leaving room for SBCL and nshell to report the condition and return to the REPL.

## Test procedure

From the repository root in Bash or Zsh, set `system` to `aarch64-darwin` on Darwin or `x86_64-linux` on Linux, then build both executables and run Q03:

```sh
system=aarch64-darwin # use x86_64-linux on Linux
normal="$(nix build --no-link --print-out-paths ".#packages.${system}.default")"
q03="$(nix build --no-link --print-out-paths ".#packages.${system}.q03")"
nix develop .#scenarios -c python3 scripts/run-scenarios.py \
  --binary "$normal/bin/nshell" \
  --mode pty \
  --scenario-id Q03-real-heap-exhaustion \
  --scenario-binary "Q03-real-heap-exhaustion=$q03/bin/nshell" \
  --repeat 1
```

The scenario verifies the dynamic-space size, successful allocator preflight, `nshell: storage exhausted`, a later `echo Q03_RECOVERED_$((1+1))` command, and normal exit. A passing run prints `PASS Q03-real-heap-exhaustion` and a summary with `selected=1 runs=1 pass=1` and `fail=0`. The scenario rejects a backtrace, an internal structure dump, and SBCL's fatal termination message (`fatal error encountered`).

## Manual status

The dedicated 256 MiB executable was built and exercised under tmux on Darwin. The captured run showed SBCL's allocation exhaustion diagnostic, nshell's storage-condition diagnostic, a successful later command, and exit status 0. Linux runtime verification remains pending the `Scenario corpus` workflow; Darwin success alone does not establish cross-platform acceptance.

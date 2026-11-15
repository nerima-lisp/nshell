# AGENTS.md — nshell

This file is the entry point for coding agents (Claude Code, Codex, …) working on nshell.
Humans are welcome to read it too.

## What nshell is

An interactive Unix shell written in Common Lisp (SBCL). S-expressions are the
command language; a "bare-line" shorthand covers simple commands, pipes and
redirections. It ships a fish-style line editor, completion, history, job
control, and AI assistance (`?` / `Ctrl-]`, `ai`, `agent`, `--mcp`).

## Where the plan lives

The v0.8 design is in `docs/design/` (Japanese). Read in this order:

1. `docs/design/README.md` — index, status of decisions, how to use the docs
2. `docs/design/00-overview.md` — goals, principles, key decisions
3. `docs/design/proposal/05-roadmap-and-decisions.md` — phases P0–P6
4. `docs/design/tasks/` — the work broken into tasks with acceptance criteria
5. The spec chapters a task points to (`language/`, `ux/`, `proposal/`, `inventory/`)

The design is normative where it says so (language spec "〜する" = MUST).
If code and design disagree, do not silently pick one: follow the design, and
note the disagreement in the PR description. If the design is ambiguous or
wrong, stop and ask instead of guessing.

## Repository map

| Path | What |
|---|---|
| `src/domain/` | pure logic: parsing (sexp + bare-line), expansion, completion, history, prompting |
| `src/application/` | evaluator, builtins, pipeline execution, agent mode |
| `src/infrastructure/` | terminal, persistence, process ACLs, assistant sidecar |
| `src/presentation/` | REPL, line editor (`input-state-*`, pure reducer), rendering |
| `packages/` | `core/kernel` and `feature/*` (assistant, command-line, …); new machine-interface code goes in `feature/machine/`, the knowledge base in `feature/kb/` |
| `data/` | declarative tables (builtin spec, key bindings, themes, completion catalogs) |
| `t/` | `unit/`, `integration/`, `e2e/`, `perf/`, `scenarios/` (JSON), `weave/` |
| `scripts/` | test runners, coverage, NFR/bench scripts (many slated for removal, see P2) |
| `docs/src/` | MkDocs user docs · `docs/design/` v0.8 design (not published) |

Layer rule: `domain` ← `infrastructure` ← `application` ← `presentation`.
A layer may use the layers to its left, never the ones to its right. The static
checks in the test suite (`t/unit/test-static-checks.lisp`) enforce this. Every
package under `packages/` keeps the same `src/<layer>/` directories, and the
check takes the layer from the path.

## Build and test

```sh
nix develop                     # interactive shell with SBCL and pinned toolkits
nix build                       # ./result/bin/nshell
nix fmt
nix flake check --print-build-logs # CI gate: all configured flake checks
```

Run the complete test suite locally with the isolated full-suite command shown below; it runs `sbcl --script run-tests.lisp` through `nix develop -c env`.
CI uses `nix flake check --print-build-logs` as its full gate; its generated `checks.default` includes `run-tests.lisp` and it runs the other configured flake checks.

Run long commands in the background, keep their output, and wait for them to finish.
Do not stop a build after a fixed time limit.
If its log has not grown for several minutes, check whether the process is still active before deciding it is stuck.
If it is stuck, signal only the PID you started, for example `kill -TERM "$pid"`.

Create a temporary state directory before testing:

```sh
test_root="$(mktemp -d)"
mkdir -p "$test_root/home" "$test_root/config" "$test_root/data" \
  "$test_root/state" "$test_root/cache"
```

Set test state inside `nix develop -c env`, as in this full-suite command:

```sh
nix develop -c env \
  HOME="$test_root/home" \
  XDG_CONFIG_HOME="$test_root/config" \
  XDG_DATA_HOME="$test_root/data" \
  XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" \
  NSHELL_AI_COMMAND=/nonexistent \
  sbcl --script run-tests.lisp
```

Set `HOME` inside `nix develop -c env`; setting it outside changes which Nix config and cache directories Nix uses.
Run the other Lisp scripts from the repository root through `nix develop -c env` with the same isolated variables:

```sh
nix develop -c env HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config" \
  XDG_DATA_HOME="$test_root/data" XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" NSHELL_AI_COMMAND=/nonexistent \
  sbcl --script scripts/test-fast.lisp # unit, main and static checks (nshell/test-unit)
nix develop -c env HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config" \
  XDG_DATA_HOME="$test_root/data" XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" NSHELL_AI_COMMAND=/nonexistent \
  sbcl --script scripts/weave.lisp # completion knowledge-base suite (nshell/weave)
nix develop -c env HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config" \
  XDG_DATA_HOME="$test_root/data" XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" NSHELL_AI_COMMAND=/nonexistent \
  NSHELL_COVERAGE_DIR="$test_root/cache/nshell/coverage" \
  sbcl --script scripts/coverage.lisp
```

The coverage report is written to `$test_root/cache/nshell/coverage` in this isolated setup.
The `test`, `test-fast`, `weave` and `cov` aliases exist in the interactive shell hook; automation uses the explicit script commands above.

`test-fast` excludes tests tagged `:slow`; the full suite keeps them.
Its target is 30 seconds for cached SBCL elapsed time; the reported time excludes Nix startup.
To measure it, set `NSHELL_ASDF_OUTPUT_DIR` to a new directory and run the command twice, recording cold and cached elapsed times separately.
With the isolated environment above, the compilation cache is written to `$test_root/cache/nshell/asdf`.

```sh
nix develop -c env HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config" \
  XDG_DATA_HOME="$test_root/data" XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" NSHELL_AI_COMMAND=/nonexistent \
  NSHELL_ASDF_OUTPUT_DIR="$test_root/cache/nshell/asdf" \
  sbcl --script scripts/test-fast.lisp
```

Without Nix (e.g. a cloud sandbox where the Nix cache is unreachable):

```sh
# Start from the repository root. SBCL must be >= 2.6.0 and < 2.6.10 because
# 2.6.10 removed sb-unix:unix-ioctl, which cl-tty-kit uses.
repo_root="$PWD"
test_root="$(mktemp -d)"
mkdir -p "$test_root/home" "$test_root/config" "$test_root/data" \
  "$test_root/state" "$test_root/cache" "$test_root/deps" "$test_root/helpers"
export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_DATA_HOME="$test_root/data"
export XDG_STATE_HOME="$test_root/state"
export XDG_CACHE_HOME="$test_root/cache"
export NSHELL_AI_COMMAND=/nonexistent
```

Check the installed compiler with `sbcl --version`.
If it reports a version from 2.6.0 up to, but not including, 2.6.10, use that system SBCL and skip the optional source-build block below.
Otherwise, run that block with an installed host SBCL older than 2.6.9 to build SBCL 2.6.9.

```sh
git clone --depth 1 --branch sbcl-2.6.9 https://github.com/sbcl/sbcl "$test_root/sbcl-source"
cd "$test_root/sbcl-source"
echo '"2.6.9"' > version.lisp-expr
sh make.sh --prefix="$test_root/sbcl"
sh install.sh
cd "$repo_root" # Return to the nshell repository root.
```

Continue in the same shell session so `$repo_root`, `$test_root` and the isolated environment remain set.

```sh
# List the locked cl-* inputs, their GitHub repository, tag/ref, and commit:
jq -r '.nodes as $nodes | .nodes.root.inputs | to_entries[] | select(.key | startswith("cl-")) | .key as $name | .value as $node | [$name, ("https://github.com/\($nodes[$node].locked.owner)/\($nodes[$node].locked.repo).git"), $nodes[$node].original.ref, $nodes[$node].locked.rev] | @tsv' flake.lock
# cl-nix-forge is Nix build tooling, not an ASDF source dependency; the loop excludes it.
# Clone the ASDF runtime inputs, transitive cl-log-kit, and test-only cl-weave
# at their listed tags under the temporary dependency directory:
deps_dir="$test_root/deps"
jq -r '.nodes as $nodes | .nodes.root.inputs | to_entries[] | select(.key | startswith("cl-")) | .key as $name | .value as $node | [$name, ("https://github.com/\($nodes[$node].locked.owner)/\($nodes[$node].locked.repo).git"), $nodes[$node].original.ref, $nodes[$node].locked.rev] | @tsv' flake.lock |
while IFS="$(printf '\t')" read -r name url ref locked_rev; do
  case "$name" in
    cl-prolog-kit|cl-parser-kit|cl-dataflow-kit|cl-boundary-kit|cl-cli|cl-tty-kit|cl-process-kit|cl-regex-kit|cl-vcs-kit|cl-tui-kit|cl-history-kit|cl-host-kit|cl-codec-kit|cl-concurrent-kit|cl-date-kit|cl-json-kit|cl-log-kit|cl-weave)
      git clone --depth 1 --branch "$ref" "$url" "$deps_dir/$name" || exit 1
      git -C "$deps_dir/$name" checkout --detach "$locked_rev" || exit 1
      ;;
  esac
done

# Build the cl-process-kit helpers used by the tests. Keep generated helpers in
# the temporary root.
helper_dir="$test_root/helpers"
cc -std=c11 -O2 -Wall -Wextra -Werror \
  "$deps_dir/cl-process-kit/native/spawn.c" \
  -o "$helper_dir/cl-process-kit-spawn"
export CL_PROCESS_KIT_SPAWN="$helper_dir/cl-process-kit-spawn"
case "$(uname -s)" in
  Darwin)
    cc -O2 -fPIC -dynamiclib "$deps_dir/cl-process-kit/native/pty.c" \
      -o "$helper_dir/libcl_process_kit_pty.dylib"
    export CL_PROCESS_KIT_PTY_LIBRARY="$helper_dir/libcl_process_kit_pty.dylib"
    cc -std=c11 -O2 -Wall -Wextra -Werror \
      src/infrastructure/acl/pty-exec-bootstrap.c \
      -o "$helper_dir/nshell-pty-bootstrap"
    export NSHELL_PTY_BOOTSTRAP="$helper_dir/nshell-pty-bootstrap"
    ;;
  Linux)
    cc -O2 -fPIC -shared "$deps_dir/cl-process-kit/native/pty.c" \
      -o "$helper_dir/libcl_process_kit_pty.so" -lutil
    export CL_PROCESS_KIT_PTY_LIBRARY="$helper_dir/libcl_process_kit_pty.so"
    ;;
esac

# Source-installed SBCL needs these paths. Omit both exports with a system SBCL.
if [ -x "$test_root/sbcl/bin/sbcl" ]; then
  export PATH="$test_root/sbcl/bin:$PATH"
  export SBCL_HOME="$test_root/sbcl/lib/sbcl"
else
  unset SBCL_HOME
fi

# Configure ASDF to find the repository and temporary dependency trees.
export CL_SOURCE_REGISTRY="$deps_dir//:$PWD/"
export NSHELL_TEST_PTY=1 CI=1
sbcl --script run-tests.lisp
```

On macOS and Linux, an unprivileged-user run is expected to finish with `failures 0`.
When running as root inside a container, these environment-only tests may fail:
`complete-path-like-command-arguments-from-filesystem`,
`regular-file-preview-reader-rejects-permission-denied-files`,
`spawn-pipeline-reaped-leader-still-terminates-descendants`, and
`run-external-timeout-terminates-descendant-processes`.

After `nix build`, run a script with `./result/bin/nshell FILE.nsh` or a command
with `./result/bin/nshell --command '(+ 1 2)'`; the command prints `3`.

The flake checks run in a Nix build sandbox, where PTY integration tests are skipped.
To run them on the host, set `NSHELL_TEST_PTY=1` and `CI=1` in the `nix develop -c env` command, as in this example:

```sh
nix develop -c env \
  HOME="$test_root/home" \
  XDG_CONFIG_HOME="$test_root/config" \
  XDG_DATA_HOME="$test_root/data" \
  XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" \
  NSHELL_AI_COMMAND=/nonexistent \
  NSHELL_TEST_PTY=1 CI=1 \
  sbcl --script run-tests.lisp
```

With `CI=1`, an unavailable PTY is a test failure instead of a skip.

## Working rules

- One task per branch/PR. Name branches `p<phase>/<task-id>-<slug>`, e.g. `p0/p0-2-test-fast`.
- Write the test first when the task has acceptance criteria; keep tests in the
  existing cl-weave style and register new files in `nshell.asd`.
- The line editor is a pure reducer over `input-state` values: test it with
  key-sequence → state assertions, no terminal needed.
- Keep behaviour changes behind the migration rules in
  `docs/design/language/L7-diff-and-migration.md`. L7 decides per row whether
  v0.8 switches to the new behaviour or keeps the old one with a warning and a
  suggested rewrite until v0.9.0.
- Never run commands that write outside the repository or a temp directory.
  Never commit secrets, history files or `result/`.
- Commit messages: Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`).
- Update `docs/design/` when an implementation decision changes the design, in the same PR.

## Things that are easy to get wrong

- Lisp symbols in host forms are currently read case-preserving (`:test` ≠ `:TEST`).
  The v0.8 spec changes this (L1/L2); until then write uppercase keywords in Lisp code.
- In S-expressions, head resolution currently checks PATH before Common Lisp,
  so `(sort …)`, `(last …)` may run external programs. L2 fixes the order.
- `-c` is delegated to `/bin/sh` on purpose (editors call `$SHELL -c`). Keep it.
- The assistant sidecar must run with no tools and no MCP servers; this is
  verified at startup. Do not weaken it when adding providers (proposal/09).

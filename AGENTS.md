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
nix flake check --print-build-logs # full suite and configured checks
```

CI runs the full suite through the flake check shown above.

Run long commands in the background, wait for the process to finish, and keep
its output. Do not stop a build with a timer.

Run Lisp test scripts from the repository root through `nix develop -c`:

```sh
nix develop -c sbcl --script run-tests.lisp        # full suite (nshell/test)
nix develop -c sbcl --script scripts/test-fast.lisp # unit, main and static checks (nshell/test-unit)
nix develop -c sbcl --script scripts/weave.lisp    # completion knowledge-base suite (nshell/weave)
NSHELL_COVERAGE_DIR="$XDG_CACHE_HOME/nshell/coverage" \
  nix develop -c sbcl --script scripts/coverage.lisp
```

The `test`, `test-fast`, `weave` and `cov` aliases exist in the interactive
shell hook. Automation uses the explicit `nix develop -c sbcl --script …`
commands above.

`test-fast` excludes tests tagged `:slow`; the full suite keeps them. Its cached
target is 30 seconds. To measure it, set
`NSHELL_ASDF_OUTPUT_DIR="$XDG_CACHE_HOME/nshell/asdf"` to a new cache directory
and run the following command twice. Record the cold and cached elapsed times
separately. The runner reports SBCL elapsed time and excludes Nix startup.

```sh
NSHELL_ASDF_OUTPUT_DIR="$XDG_CACHE_HOME/nshell/asdf" nix develop -c sbcl --script scripts/test-fast.lisp
```

Without Nix (e.g. a cloud sandbox where the Nix cache is unreachable):

```sh
# 1. SBCL >= 2.6.0 and < 2.6.10 (2.6.10 removed sb-unix:unix-ioctl, which cl-tty-kit uses).
#    Build 2.6.9 from source with any older SBCL as host:
git clone --depth 1 --branch sbcl-2.6.9 https://github.com/sbcl/sbcl && cd sbcl \
  && echo '"2.6.9"' > version.lisp-expr && sh make.sh --prefix=$HOME/sbcl && sh install.sh
# 2. Clone the nerima-lisp toolkits at the tags pinned in flake.nix into one directory, e.g. ../deps/
# 3. Run the suite
export SBCL_HOME=$HOME/sbcl/lib/sbcl PATH=$HOME/sbcl/bin:$PATH
export CL_SOURCE_REGISTRY="$PWD/../deps//:$PWD/"
sbcl --script run-tests.lisp
```

Known environment-only failures when running as root inside a container
(not bugs in nshell): `complete-path-like-command-arguments-from-filesystem`,
`regular-file-preview-reader-rejects-permission-denied-files`,
`spawn-pipeline-reaped-leader-still-terminates-descendants`, and
`run-external-timeout-terminates-descendant-processes`.

After `nix build`, run a script with `./result/bin/nshell FILE.nsh` or a command
with `./result/bin/nshell --command '(…)'`.

Always isolate state when testing, so you never touch the real history, config
or AI provider:

- Point `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and
  `XDG_CACHE_HOME` at a temporary directory.
- Set `NSHELL_AI_COMMAND=/nonexistent` so no AI provider is started.

Set `NSHELL_TEST_PTY=1` when the PTY integration tests must run. Without it
they are skipped inside a Nix build sandbox and wherever a PTY cannot be
opened; with it and `CI` set, an unavailable PTY fails the test instead of
skipping it.

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

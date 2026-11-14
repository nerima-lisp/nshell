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
| `packages/` | `core/kernel` and `feature/*` (assistant, command-line, …) |
| `data/` | declarative tables (builtin spec, key bindings, themes, completion catalogs) |
| `t/` | `unit/`, `integration/`, `e2e/`, `perf/`, `scenarios/` (JSON), `weave/` |
| `scripts/` | test runners, coverage, NFR/bench scripts (many slated for removal, see P2) |
| `docs/src/` | MkDocs user docs · `docs/design/` v0.8 design (not published) |

Layer rule: `domain` ← `application` ← `infrastructure` / `presentation`.
Never import upward. The static checks in the test suite enforce this.

## Build and test

With Nix (CI, preferred):

```sh
nix develop                     # dev shell with SBCL and all toolkits
nix build                       # ./result/bin/nshell
perl -e 'alarm 300; exec @ARGV' nix build .#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem').default --no-link
nix fmt
```

Inside `nix develop`: `test` (full suite, `run-tests.lisp`), `weave`, `cov`.

Without Nix (e.g. a cloud sandbox where the Nix cache is unreachable):

```sh
# 1. SBCL >= 2.6.0 and < 2.6.10 (2.6.10 removed sb-unix:unix-ioctl, which cl-tty-kit uses).
#    Building 2.6.9 from source with any older SBCL as host takes ~3 minutes:
git clone --depth 1 --branch sbcl-2.6.9 https://github.com/sbcl/sbcl && cd sbcl \
  && echo '"2.6.9"' > version.lisp-expr && sh make.sh --prefix=$HOME/sbcl && sh install.sh
# 2. Clone the nerima-lisp toolkits at the tags pinned in flake.nix into one directory, e.g. ../deps/
# 3. Run the suite
export SBCL_HOME=$HOME/sbcl/lib/sbcl PATH=$HOME/sbcl/bin:$PATH
export CL_SOURCE_REGISTRY="$PWD/../deps//:$PWD/"
sbcl --script run-tests.lisp        # ~2m40s, ~2,780 tests
```

Known environment-only failures when running as root inside a container
(not bugs in nshell): `complete-path-like-command-arguments-from-filesystem`,
`regular-file-preview-reader-rejects-permission-denied-files`, and two
`process-tests` that check descendant reaping (no init process to reap zombies).

To run a built binary on a script: `nshell FILE.nsh` or `nshell --command '(…)'`.
Always isolate state when testing: set `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`
to a temporary directory so you never touch the real history or config.

## Working rules

- One task per branch/PR. Name branches `p<phase>/<task-id>-<slug>`, e.g. `p0/p0-2-test-fast`.
- Write the test first when the task has acceptance criteria; keep tests in the
  existing cl-weave style and register new files in `nshell.asd`.
- The line editor is a pure reducer over `input-state` values: test it with
  key-sequence → state assertions, no terminal needed.
- Keep behaviour changes behind the migration rules in
  `docs/design/language/L7-diff-and-migration.md` (v0.8 warns, next version enforces).
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

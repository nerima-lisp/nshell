# nerima-lisp package integration audit

This audit covers [`nshell.asd`](../../nshell.asd), `src/`, the assistant feature
in `packages/`, and the dependency graph in [`flake.nix`](../../flake.nix)
for the v0.6.1 release line.

## Declared runtime dependencies with API use

| Package | Role | Source evidence |
|---|---|---|
| `cl-prolog-kit` | Completion facts and rules | [`src/domain/completion/rule-data.lisp`](../../src/domain/completion/rule-data.lisp): `make-rulebase`, `map-prolog-solutions` |
| `cl-parser-kit` | Arithmetic tokenizer and Pratt parser | [`src/package-domain.lisp`](../../src/package-domain.lisp) imports the API used by [`src/domain/expansion/arithmetic.lisp`](../../src/domain/expansion/arithmetic.lisp) |
| `cl-dataflow-kit` | DOT/Mermaid pipeline diagrams; graph validation before DOT rendering | [`src/application/pipeline-diagram.lisp`](../../src/application/pipeline-diagram.lisp): `make-graph`, `validate-graph`, `graph->dot`, `graph->mermaid` |
| `cl-host-kit` | Host environment, pathnames, and working directory | [`src/application/builtin-commands.lisp`](../../src/application/builtin-commands.lisp): `getcwd`, `chdir`; [`src/infrastructure/acl/syscall-environment.lisp`](../../src/infrastructure/acl/syscall-environment.lisp): `getenv` |
| `cl-boundary-kit` | Synchronization boundary | [`src/infrastructure/acl/syscall.lisp`](../../src/infrastructure/acl/syscall.lisp): `make-lock` |
| `cl-cli` | Executable argument parsing | [`src/main.lisp`](../../src/main.lisp): `make-option`, `option-value` |
| `cl-tty-kit` | ANSI rendering, terminal size, and grapheme widths | [`src/infrastructure/terminal/ansi.lisp`](../../src/infrastructure/terminal/ansi.lisp), [`src/infrastructure/acl/syscall-terminal.lisp`](../../src/infrastructure/acl/syscall-terminal.lisp), [`src/presentation/prompt-display.lisp`](../../src/presentation/prompt-display.lisp) |
| `cl-process-kit` | External-process lifecycle and bounded Git probes | [`src/infrastructure/acl/syscall-process-execution.lisp`](../../src/infrastructure/acl/syscall-process-execution.lisp): `spawn`, `communicate`; [`src/infrastructure/acl/git.lisp`](../../src/infrastructure/acl/git.lisp): `run` |
| `cl-history-kit` | History storage, search, and persistence | [`src/application/search-history.lisp`](../../src/application/search-history.lisp), [`src/infrastructure/persistence/file-history.lisp`](../../src/infrastructure/persistence/file-history.lisp) |
| `cl-concurrent-kit` | Task scopes and promises for syscall work | [`src/infrastructure/acl/syscall.lisp`](../../src/infrastructure/acl/syscall.lisp): `with-task-scope`, `spawn`, `await` |
| `cl-json-kit` | Assistant JSON/JSONL state, audit records, and MCP messages | [`packages/feature/assistant/src/infrastructure/audit-log.lisp`](../../packages/feature/assistant/src/infrastructure/audit-log.lisp), [`packages/feature/assistant/src/infrastructure/mcp-server.lisp`](../../packages/feature/assistant/src/infrastructure/mcp-server.lisp), [`src/infrastructure/assistant-sidecar-stream.lisp`](../../src/infrastructure/assistant-sidecar-stream.lisp) |

## Explicit test/bootstrap inputs without direct API use

`cl-regex-kit`, `cl-vcs-kit`, and `cl-tui-kit` are not direct API dependencies
of nshell. They are retained in the Nix source registry because
[`t/support/runtime.lisp`](../../t/support/runtime.lisp) loads their systems
when it bootstraps child processes, and because sibling package systems may
need those sources while the integration suite is running. Their presence in
that registry is not advertised as an nshell feature.

They are no longer declared in `nshell.asd`'s direct `:depends-on` list. The
remaining explicit Nix inputs are intentional bootstrap/build inputs and are
covered by the tagged-tree integration gate.

## Dependencies outside nshell's ASDF declaration

The sibling derivations in `flake.nix` include these dependency edges.
`cl-date-kit` and `cl-codec-kit` are also explicit Nix `lispDependencies` of
nshell. Neither they nor `cl-log-kit` is a direct dependency in `nshell.asd`.

| Package | Consumers in the build graph | nshell use |
|---|---|---|
| `cl-log-kit` | `cl-process-kit`, `cl-vcs-kit` | No direct API reference identified. The assistant writes its own redacted JSONL audit records through `cl-json-kit`. |
| `cl-date-kit` | `cl-concurrent-kit`, `cl-log-kit` | No direct API reference identified. |
| `cl-codec-kit` | `cl-tty-kit`, `cl-process-kit` | No direct API reference identified. |

## Test and build inputs

`nshell/test` uses `cl-weave`. `nshell/weave` additionally depends on
`cl-prolog-kit/weave` for completion-query tests. Loading a library or its test
helpers is not the same as running that library's own suite. The sibling
derivations do not enable `doCheck`. In particular, `checks.weave` runs
`nshell/weave`, not `cl-weave/test`.

The current CI and release integration jobs additionally run
[`scripts/test-dependencies.sh`](../../scripts/test-dependencies.sh).
It starts a separate Lisp image for each pinned dependency suite. Its
[`runner`](../../scripts/test-dependencies.lisp) requires nonempty discovery,
matching discovered, selected, executed, and passed counts, and matching test
paths. Skipped, pending, focused, or failed tests do not clear that gate.
The jobs also run the private-history storage regressions. These gates do not
retroactively verify dependencies in the published v0.6.1 tree; their results
must be checked for the commit being released.

`cl-nix-forge` supplies the Nix build helpers. `paredit-cli` is a development
tool, not an executable runtime dependency. Release refs are declared in
`flake.nix`; resolved revisions and hashes are recorded in
[`flake.lock`](../../flake.lock). This audit makes no claim that those refs are
the newest upstream tags. An upgrade must update the declaration and lock file,
review the local patches under [`nix/patches/`](../../nix/patches/), and rerun
the release gates, including the dependencies' own suites.

## Reproduce the source checks

Run these commands from the repository root.
Inspect imports and executable forms: a match in a comment or registry list is
not evidence of a runtime call, and textual absence is not a runtime test.

```sh
rg -n 'cl-(prolog|parser|dataflow|host|boundary|tty|concurrent|json)-kit|cl-cli|process-kit:|history-kit:|host-kit:|json-kit:' nshell.asd src packages
rg -n -i '\b(cl-(regex|vcs|tui|log|date|codec)-kit|regex-kit:|vcs-kit:|tui-kit:|log-kit:|date-kit:|codec-kit:)' nshell.asd src packages t/support/runtime.lisp
```

# nerima-lisp package integration audit

Which packages from the [nerima-lisp org](https://github.com/orgs/nerima-lisp/repositories)
nshell integrates, and — for every one it does not — a concrete reason. The goal
is "adopt every applicable nerima-lisp package at the direct dependency boundary,
without compatibility wrappers", so this table exists to prove the *un*-adopted
set is non-applicable rather than overlooked.

## Integrated and in active use

Every runtime system in `nshell :depends-on` is genuinely exercised (qualified-
symbol counts are from `src/`; `cl-parser-kit` is `:import-from`, so its symbols
appear unqualified):

| package | role in nshell | evidence |
|---|---|---|
| `cl-prolog-kit` | completion knowledge base — facts/rules, `map-prolog-solutions` | `domain/completion/rule-data.lisp` (8 refs) |
| `cl-parser-kit` | `$((…))` arithmetic tokenizer + Pratt parser | `:import-from` in `package.lisp`; `domain/expansion/arithmetic.lisp` |
| `cl-dataflow-kit` | reactive dataflow wiring | 12 refs |
| `cl-host-kit` | host environment, pathname, and process boundaries | `presentation/repl-environment.lisp`, `infrastructure/terminal/ansi.lisp`, `application/builtin-runtime.lisp` |
| `cl-boundary-kit` | clock/sleeper boundaries (also under cl-process-kit) | 14 refs |
| `cl-cli` | argument-vector parsing for `main` | 13 refs |
| `cl-tty-kit` | terminal control / raw-mode / rendering | 17 refs |
| `cl-process-kit` | timeout-guarded external process launch (`run`) | `infrastructure/acl/syscall-process.lisp` (6 refs) |
| `cl-history-kit` | command-history store, search, and recall navigation cursor | used directly (qualified `history-kit:...`) throughout `application/` and `presentation/`; nshell keeps only the tokenizer-coupled `!$`/Alt-. last-argument extraction in `domain/history/last-argument.lisp` |
| `cl-concurrent-kit` | structured task scopes and promises for concurrent syscall work | `infrastructure/acl/syscall.lisp` (`with-task-scope`, `spawn`, `await`) |

No declared dependency is unused, so there is no dead dependency to drop.

The flake inputs are pinned to explicit upstream release refs rather than
floating branches. The current pins include `cl-weave` `v1.3.0`,
`cl-prolog-kit` `v1.5.0`, `cl-parser-kit` `v1.1.1`, and `cl-dataflow-kit`
`v1.2.0`; the complete resolved set is recorded in `flake.lock`. A release
API's `latest` field is not treated as authoritative here because an upstream
tag may exist before its GitHub release metadata is published. A future upgrade
must update `flake.nix` and `flake.lock` together and rerun the complete check
matrix.

The test systems are kept separate from the runtime dependency audit:

| package | role in nshell's test systems | evidence |
|---|---|---|
| `cl-weave` | the test framework for the weave suite | `nshell/weave` |
| `cl-prolog-kit/weave` | cl-prolog-kit-query coverage of the completion engine | `nshell/weave` |

## Transitive, not adopted directly

| package | why not direct |
|---|---|
| `cl-log-kit` | Pulled in transitively by `cl-process-kit` for *its* structured logging. nshell itself performs no logging (a shell's diagnostics go to the user's stderr, not a structured log sink), so it is deliberately absent from nshell's own `:depends-on`. Adopting it directly would mean inventing a logging concern the shell does not have. |
| `cl-date-kit` | Pulled in transitively by `cl-concurrent-kit`; nshell consumes concurrency primitives, not date formatting or parsing. |

## Non-applicable org repositories

| package | what it is | why nshell cannot use it |
|---|---|---|
| `cl-json-kit` | dependency-free JSON reader/writer | nshell has no JSON I/O. The only `json` tokens in the tree are completion-catalog *values* (e.g. `kubectl --output json`), not parsing. |
| `cl-http-kit`, `cl-http-message-kit`, `cl-websocket-kit`, `cl-sse-kit` | HTTP, message, WebSocket, and SSE protocol libraries | nshell is a local process shell and exposes no network protocol endpoint. |
| `cl-postgresql-kit`, `cl-redis-kit` | database clients | No database connection or persistence boundary exists in the shell. |
| `cl-observability-kit`, `cl-log-kit`, `cl-resilience-kit`, `cl-event-sourcing-kit` | service observability, logging, resilience, and event-sourcing libraries | These solve service/runtime concerns absent from a local CLI; diagnostics remain user-facing stderr. |
| `cl-cffi-kit`, `cl-regex-kit`, `cl-hpack-codec-kit` | FFI, regular-expression, and compression helpers | No direct feature requires them; adding them would duplicate existing host/parser boundaries or add unused functionality. |
| `cl-tui-kit`, `cl-glfw3-kit`, `cl-vulkan-kit`, `cl-fx-quant-kit` | UI, graphics, and quantitative-computing libraries | nshell uses `cl-tty-kit` for terminal control and has no graphical or numerical UI. |
| `cl-asciiquarium`, `cl-chip8`, `cl-cmatrix`, `cl-cowsay`, `cl-nes`, `cl-nyancat`, `cl-sl`, `ncl`, `nerimux`, `loom`, `cachix` | standalone applications, tools, or infrastructure | They are independently runnable products rather than libraries used by a shell execution boundary. |
| `cl-tmux` | a full terminal multiplexer in CL | Orthogonal peer application. A multiplexer *hosts* shells; a shell does not embed one. Integration would be a dependency inversion. |
| `cl-cc`, `cl-cc-ast`, `cl-cc-binary`, `cl-cc-javascript`, `cl-cc-php`, `cl-cc-runtime`, `cl-cc-type` | a self-hosting CL compiler collection | Language-implementation infrastructure with no surface a shell consumes. |
| `cl-vcs-kit` | version-control toolkit | nshell only needs the prompt's small, timeout-bounded `git` probe; adopting a repository abstraction would add a broader policy surface without replacing the existing process boundary. |
| `paredit-cli` | the Rust S-expression refactoring CLI | A development *tool* used to perform these refactors, not a runtime dependency. |

## Conclusion

The applicable nerima-lisp surface is fully adopted: ten runtime systems plus
two test systems, all directly declared where used. The executable composition
root consumes `cl-cli` directly to parse `argv`; the command-line feature owns
the policy, contract, and help presentation, with no compatibility adapter or
duplicate parser. The un-adopted remainder is compiler infrastructure
(`cl-cc*`), a version-control helper whose surface is broader than nshell's
prompt probe (`cl-vcs-kit`), a peer application (`cl-tmux`), a format library
for a format nshell never handles (`cl-json-kit`), or a build-time tool
(`paredit-cli`).
Re-run the usage half of this audit with:

```sh
rg -o '\\b(cl-prolog-kit|cl-dataflow-kit|cl-boundary-kit|cl-cli|cl-tty-kit|process-kit|history-kit|cl-concurrent-kit)::?[a-z]' src/ \\
  | perl -pe 's/:.*$//' | sort | uniq -c | sort -rn
```

To re-check the release refs and compare them with the lock file:

```sh
for repo in cl-weave cl-prolog-kit cl-parser-kit cl-dataflow-kit cl-boundary-kit cl-cli cl-tty-kit cl-process-kit cl-history-kit cl-host-kit cl-codec-kit cl-concurrent-kit cl-date-kit; do
  printf '%s: ' "$repo"
  gh api "repos/nerima-lisp/$repo/tags?per_page=1" --jq '.[0].name'
done
```

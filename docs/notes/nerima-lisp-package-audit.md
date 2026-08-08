# nerima-lisp package integration audit

Which packages from the [nerima-lisp org](https://github.com/orgs/nerima-lisp/repositories)
nshell integrates, and — for every one it does not — a concrete reason. The goal
is "adopt every applicable nerima-lisp package, directly and without adapters",
so this table exists to prove the *un*-adopted set is non-applicable rather than
overlooked.

## Integrated and in active use

Every system in `:depends-on` is genuinely exercised (qualified-symbol counts are
from `src/`; `cl-parser-kit` is `:import-from`, so its symbols appear unqualified):

| package | role in nshell | evidence |
|---|---|---|
| `cl-prolog` | completion knowledge base — facts/rules, `map-prolog-solutions` | `domain/completion/rule-data.lisp` (8 refs) |
| `cl-parser-kit` | `$((…))` arithmetic tokenizer + Pratt parser | `:import-from` in `package.lisp`; `domain/expansion/arithmetic.lisp` |
| `cl-dataflow` | reactive dataflow wiring | 12 refs |
| `cl-host-kit` | host environment, pathname, and process boundaries | `presentation/repl-environment.lisp`, `infrastructure/terminal/ansi.lisp`, `application/builtin-runtime.lisp` |
| `cl-boundary-kit` | clock/sleeper boundaries (also under cl-process-kit) | 14 refs |
| `cl-cli` | argument-vector parsing for `main` | 13 refs |
| `cl-tty-kit` | terminal control / raw-mode / rendering | 17 refs |
| `cl-process-kit` | timeout-guarded external process launch (`run`) | `infrastructure/acl/syscall-process.lisp` (6 refs) |
| `cl-concurrent-kit` | bounded asynchronous mapping and coordination | `infrastructure/acl/syscall.lisp` |
| `cl-weave` | the entire test framework (both suites) | `nshell/test`, `nshell/weave` |
| `cl-prolog/weave` | cl-prolog-query coverage of the completion engine | `nshell/weave` |

No declared dependency is unused, so there is no dead dependency to drop.

## Transitive, not adopted directly

| package | why not direct |
|---|---|
| `cl-log-kit` | Pulled in transitively by `cl-process-kit` for *its* structured logging. nshell itself performs no logging (a shell's diagnostics go to the user's stderr, not a structured log sink), so it is deliberately absent from nshell's own `:depends-on`. Adopting it directly would mean inventing a logging concern the shell does not have. |
| `cl-date-kit` | Pulled in transitively by `cl-concurrent-kit`; nshell consumes concurrency primitives, not date formatting or parsing. |

## Non-applicable org repositories

| package | what it is | why nshell cannot use it |
|---|---|---|
| `cl-json-kit` | dependency-free JSON reader/writer | nshell has no JSON I/O. The only `json` tokens in the tree are completion-catalog *values* (e.g. `kubectl --output json`), not parsing. |
| `cl-tmux` | a full terminal multiplexer in CL | Orthogonal peer application. A multiplexer *hosts* shells; a shell does not embed one. Integration would be a dependency inversion. |
| `cl-cc`, `cl-cc-ast`, `cl-cc-binary`, `cl-cc-javascript`, `cl-cc-php`, `cl-cc-runtime`, `cl-cc-type` | a self-hosting CL compiler collection | Language-implementation infrastructure with no surface a shell consumes. |
| `paredit-cli` | the Rust S-expression refactoring CLI | A development *tool* used to perform these refactors, not a runtime dependency. |

## Conclusion

The applicable nerima-lisp surface is fully adopted: 9 runtime systems + 2 test
systems, all directly (no wrapper adapter layer), all in active use. The
un-adopted remainder is compiler infrastructure (`cl-cc*`), a peer application
(`cl-tmux`), a format library for a format nshell never handles (`cl-json-kit`),
or a build-time tool (`paredit-cli`). Re-run the usage half of this audit with:

```
rg -o '\b(cl-prolog|cl-dataflow|cl-boundary-kit|cl-cli|cl-tty-kit|cl-process-kit)::?[a-z]' src/ \
  | perl -pe 's/:.*$//' | sort | uniq -c | sort -rn
```

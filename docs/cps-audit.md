# Continuation-passing style: where nshell uses it, and where it deliberately does not

The goal "use CPS as much as possible" is in tension with "raise the readability
of complex functions" and "human-readable code". CPS earns its place when it
*decouples* concerns; it costs readability when forced onto a pure fold. This
audit records where each applies, so "as much as possible" means "everywhere it
helps", not "everywhere".

## Where CPS is used, and why it is the right shape there

| site | continuation | what CPS buys |
|---|---|---|
| `domain/expansion/expand.lisp` `%walk-directory-files` | `(file) -> ...` | The walk (data: descend depth-first) stays free of any accumulator; each caller — `recursive-directory-files` collecting a list, a matcher short-circuiting — decides what to do per file. One traversal, many uses. |
| `infrastructure/acl/syscall-process.lisp` `%wait-process-with-copiers` | `success-fn` / `timeout-fn` | The two terminal outcomes (exited vs. timed out) are passed in as continuations, so the wait logic never branches on "what to return" — the caller supplies both exit paths. |
| `infrastructure/acl/syscall-pipeline.lisp` `%wait-pipeline-with-output` | `timeout-fn` | Same two-exit-path shape for a whole pipeline. |
| `application/builtin-state-tables.lisp` | `emitter` | Table rendering emits each `(name value)` to a caller-supplied sink rather than materialising rows. |
| `cl-process-kit` `run … :on-timeout :return` | policy continuation | The timeout *policy* is a value nshell passes to the library, not a branch nshell writes. |

The common thread: a continuation is right when it separates a **traversal or a
wait** from **what to do with each result / each exit path**. That is the
data/logic split (`可能な限りdataとlogicは分けて`) expressed as control flow.

## Where CPS was considered and deliberately rejected

- **`domain/expansion/brace.lisp` `%brace-expansion-cartesian-product`.** Brace
  expansion is a pure combinatorial fold: for each option × each recursive
  option-expansion × each suffix, concatenate. Expressed as nested
  `loop … append`, it reads as exactly that sentence. Threading an `emit`
  continuation through three levels would obscure the product without removing
  any accumulator the caller cares about (the caller wants the list). The data
  (`brace-expansion-frame` struct) is already separated from the logic; adding
  CPS here would trade readability for nothing.

- **Parser/tokenizer reductions.** These already return structured result values
  (`%token-reduction-result`, parse diagnostics). Their consumers want the whole
  structure, not a per-element callback, so CPS would only add indirection.

## Conclusion

CPS is applied at every site where it decouples a traversal or a multi-exit wait
from its uses, and withheld from pure folds where `loop … append` is the more
human-readable form. "As much as possible" is bounded by the readability
requirements it shares the brief with; this is that boundary, drawn explicitly.

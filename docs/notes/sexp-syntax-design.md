# S-expression syntax redesign

**None of the syntax work here is implemented**; the three removals under
[Remove](#remove) have since shipped and are marked as such. This note records
the decisions, their consequences, and the remaining open questions.

The headline decision: nshell stops being fish-inspired. The surface syntax
becomes S-expressions, with bare command lines as sugar over them.

## Positioning

nshell targets **interactive use and scripting together**. That is the criterion
every feature decision below is measured against: a feature earns its place if
it serves daily interactive work, script authoring, or both.

Four goals motivate the syntax change, in the order they were prioritised:

1. **Eliminate quoting hell.** Arguments are a list, so word splitting, `"$@"`
   versus `$@`, `IFS`, and the re-parsing of `$(...)` results cannot occur.
   These bugs come from re-parsing strings; S-expressions never re-parse.
2. **Syntactic uniformity.** No `if`/`end` pairs, no `[` that is secretly a
   command, no ad-hoc expansion rules.
3. **Macros and homoiconicity.** Users extend the language themselves.
4. **Unity with the host language.** Evaluation rides on Common Lisp's evaluator.

Goal 4 is the weakest of the four and does not survive intact — see
[Where host-language unity stops](#where-host-language-unity-stops).

## The evaluation rule

There is exactly one rule.

> When evaluating a form `(head args...)`: if `head` is bound as a special
> operator, macro, or function, evaluate normally as Common Lisp. Otherwise the
> form is a **command form** — read its arguments under an implicit backquote
> and execute the command. Inside a command form, `,expr` (equivalently `$x`)
> returns to normal evaluation context.

Command forms are islands of implicit quotation. Nesting follows Common Lisp's
existing quasiquotation rules, so no new semantics are invented.

```lisp
(ls -la)                      ; ls unbound -> island; -la is the string "-la"
(echo ,(* 3 (+ 2 4)))         ; echo is an island; , returns to evaluation -> 18
(when (test -f x.txt)         ; when is a macro -> outside the island
  (cat x.txt))                ;   test and cat are unbound -> islands again
(when (> $count 10) ...)      ; outside an island, > is CL numeric comparison
(ls -la > "out.txt")          ; inside an island, > is a redirection
```

The same token `>` means redirection inside an island and numeric comparison
outside one. This is not ambiguous: which context applies is determined by
`head`, and a reader can decide by looking at it.

A consequence worth stating separately: **command substitution disappears**.
Command forms return values, so `(set branch (git rev-parse --abbrev-ref HEAD))`
is an ordinary evaluation. There is no `$(...)` construct and therefore no
`"$(cmd)"` quoting problem.

## Reader

### Bare lines are sugar

A line that does not begin with `(` is wrapped in one. The interactive
experience is unchanged from a conventional shell.

```
ls -la                        ; identical to (ls -la)
cat f.txt | grep foo | wc -l  ; identical to (| (cat f.txt) (grep foo) (wc -l))
```

Bare lines are a notation, not a second language. Control flow exists only as
S-expressions; a bare line is always equivalent to some single form.

### `readtable-case` is a blocking hazard

Common Lisp's standard reader upcases symbols. Under `:upcase`, `-la` in
`(ls -la)` reads as `|-LA|` and stringifies to `"-LA"`, and `*.lisp` becomes
`"*.LISP"`. **The syntax does not work on the standard readtable.**

The reader must use `:preserve`. That in turn means `when` and `let` are
case-sensitive, so either every nshell special form is defined in lower case or
the head position is matched case-insensitively. This must be settled before any
other reader work; it invalidates the design otherwise.

### Stringification

Only symbols stringify. Numbers and string literals pass through and are
converted at the point of argument construction.

```lisp
(head -n 10)   ; symbol "-n", number 10 -> "-n" "10"
(ls -1)        ; number -1 -> "-1"
```

### `$` is sugar for `,`

`$x` and `,x` are the same reader-level construct; `$(pwd)` and `,(pwd)` are the
same form. `$` exists so interactive muscle memory carries over; `,` exists so
macro authors see ordinary quasiquotation.

### No string interpolation

String literals are opaque. Concatenation is explicit.

```lisp
(tar czf ,(str target "-" stamp ".tar.gz") $target)
(echo "branch is" $branch)
```

This keeps the reader free of escaping rules at the cost of verbosity when
building filenames.

### Globbing

Glob metacharacters in a **symbol** inside an island expand. String literals
never expand.

```lisp
(ls *.lisp)                   ; expands
(rm -rf build/*)              ; expands
(echo "*.lisp")               ; literal
```

This is the one deliberate hole in "bare symbols are strings". It is accepted
because glob expansion at the command line is not negotiable for daily use.

## Pipelines and structured data

Pipelines carry **structured data**, not only byte streams.

```lisp
(| (cat f.txt) (grep foo) (wc -l))

(-> (jobs)
    (where (= :state "stopped"))
    (select :id :command))
```

### Internal commands stay minimal

Internal commands — the ones that return records — are deliberately few. `ls`,
`ps`, and other everyday tools stay external, so `ls -la` behaves exactly as it
always did and no muscle memory is broken. A command is only internalised when
structure genuinely buys something the external tool cannot give.

`^` forces the external resolution of a name that also exists internally
(`(^jobs)`). Because internal commands are few, `^` is an escape hatch that
rarely appears in practice.

### Conversion at the boundary is explicit

External commands produce strings. Crossing into structured data is always a
visible call — never inferred.

```lisp
(-> (^ps aux) (from-tsv) (where (= :user "take")))
(-> (cat data.json) (from-json) (select :name))
(-> (jobs) (to-json) (jq ".[] | .id"))
```

## Errors

A non-zero exit signals a `command-failed` condition.

The exception, taken directly from POSIX `set -e`: **in a conditional context —
the test position of `if`, `when`, `unless`, `and`, `or`, `not` — no condition
is signalled and the exit code is used as a truth value.** A command run to ask
a question has not failed by answering "no".

```lisp
(when (grep foo f.txt)                 ; conditional position -> truth value
  (echo "found"))

(make)                                 ; ordinary position -> signals on failure

(handler-case (make)
  (command-failed () (echo "build failed")))
```

### Interactive restarts require a trampoline exception

At the interactive top level, a condition offers restarts rather than printing a
message and moving on.

```
~/src> cat /etc/shadow
Permission denied.
  [0] retry with sudo
  [1] ignore and continue
>
```

This conflicts with the current REPL design. The REPL is a continuation-passing
trampoline (`src/presentation/repl-state.lisp:5`) and the line editor is a pure
reducer that returns state. Selecting a restart requires the Common Lisp stack
at the point of the signal to still be live, but the trampoline collapses the
stack at every step.

The resolution is to run a **nested input loop inside the handler** at the
signalling site. Adding a `:restart-select` input mode is unremarkable — six
modes already exist (`data/presentation/input-state-data.lisp`) — but the loop
being driven differently from the trampoline is a real, deliberate exception to
the REPL's structure, and should be documented as such where it is implemented.

## Bindings

`let` is primary and gives lexical scope, which makes "function-local by
default" fall out for free rather than needing a scope stack. `set` exists for
sequential assignment, which is how variables are actually used interactively.

```lisp
;; interactive: session variable
(set editor "emacs")

;; script: lexical
(let ((branch (git rev-parse --abbrev-ref HEAD)))
  (git push origin $branch))
```

The earlier plan to add fish-style `set -l` / `set -g` is withdrawn: lexical
scope supersedes it.

## Macros

Macros are core, not an extension. Control forms, `->`, and `|` are all defined
as macros, leaving the language core as just the reader rules and the island
rule. Macros receive unevaluated forms, so `(my-macro ls -la)` sees `ls` and
`-la` as symbols and can expand them into a command form. The macro requirement
and the "bare symbols are strings" requirement do not conflict.

The cost is error diagnosis: a macro-expansion failure must not surface as a
reader or island-rule error. This is unaddressed.

## Where host-language unity stops

Goal 4 does not survive as stated. Three concrete limits:

- **Bare lines need their own reader.** `|` is symbol-escape syntax in Common
  Lisp, and `>` `<` `&` `;` all need shell meanings in bare lines. Bare-line
  reading is a separate reader from the CL reader.
- **`,` outside a backquote is a CL reader error.** nshell's `,` works because
  command forms are an implicit backquote, so the meaning is *consistent with*
  CL quasiquotation, but it is not the standard reader's behaviour.
- **`(> :size 1024)` inside `where` is not CL's `>`.** Structured-data operators
  are macros that rewrite their bodies.

What does hold is that evaluation of the non-island parts rides on Common Lisp's
evaluator, and that the quotation semantics are borrowed rather than invented.
Claims stronger than that should not be made in user-facing documentation.

## What this replaces

Measured on the current tree:

| | lines |
|---|---|
| `src/domain/parsing/` + `src/domain/expansion/` | 4,566 |
| `t/unit/test-parser*`, `test-tokenizer*`, `test-expansion*` | 4,230 |

Both are discarded and rewritten. A Lisp reader is substantially smaller than a
POSIX-style tokenizer and parser, so the tree is expected to shrink.

### The executor is unaffected

The application layer dispatches on AST node predicates
(`src/application/execute-pipeline-control.lisp:250`) and reads accessors such
as `command-node-args` (`src/application/execute-pipeline-stage.lisp:131`). It
never sees syntax. A new reader that produces the same `command-node` and
`pipeline-node` values leaves the application and infrastructure layers intact.

One seam does move: expansion is invoked from the application layer
(`%expand-command-args-in-context`), so it shifts when `$VAR`, globbing, and
word-splitting semantics change.

### Assets that survive

| | lines | note |
|---|---|---|
| `src/presentation/input-state*` | 2,823 | pure reducer, syntax-independent |
| `src/domain/completion/` + `src/infrastructure/` | 4,891 | knowledge base retained |

Completion keeps the Prolog knowledge base and its `completes` / `has-flag`
predicates. Only context extraction is replaced: paren depth, inside/outside an
island, and command versus argument position are structurally available from
S-expressions, so context should get *more* accurate, not less.

Highlighting depends on the AST and needs rework, which is likewise easier with
explicit structure.

## Feature decisions independent of the syntax

These were settled before the syntax change and are unaffected by it.

### Remove

All three have been carried out; the descriptions below record why.

- **Domain events and the event dispatcher.** `make-event-dispatcher` is called
  only from tests; `publish-event` sites are all guarded by `(when dispatcher
  ...)` and never fire in production. The subsystem also cannot serve as a hook
  foundation: `define-event-constructors`
  (`src/domain/events/base-event.lisp:17`) discards every payload argument, so
  an event cannot carry a job id or an exit code. Scope: 98 source lines, 152
  test lines, and the `&optional dispatcher` parameter on 5 functions.
- **The `ls` builtin.** `src/application/builtin-commands.lisp:321` declares
  `args` ignored, so `ls -la` silently produces an unsorted, uncolumned listing,
  and the builtin shadows the real `ls`. Delegate to the external command.
- **`config`'s `prompt-format`.** Nothing reads it; the prompt is built from
  `prompt-model` segments. Its only reference is
  `t/unit/test-configuration.lisp:12`. Superseded by user-defined prompts.

### Keep

- **`pipeline-graph`.** Harmless, and `cl-dataflow-kit` is already a dependency.
  It should be documented and categorised as a diagnostic and visualisation
  feature rather than a daily one.

### Add

- **`bind`.** Key handling is already two-stage: a `case` over key-event types
  (`src/presentation/input-state-dispatch.lisp:154`) mapping to named actions
  such as `:kill-to-eol`, then a separate action interpreter. Replacing the
  `case` with a data table makes rebinding named actions a small change. Binding
  keys to arbitrary shell commands — which needs a `commandline` builtin to
  read and write the edit buffer from shell code, crossing the pure-reducer
  boundary — is explicitly deferred.
- **User-defined prompts.** Declarative segment configuration by default, with a
  `nshell_prompt` function overriding it when defined. The prompt is evaluated
  **once per command boundary and cached**, not on every redraw:
  `render-prompt-cont` runs on every keystroke
  (`src/presentation/repl-rendering.lisp:108`), and git status already follows
  exactly this cache-and-invalidate pattern
  (`src/infrastructure/acl/git.lisp:15`). Theme colours become configurable at
  the same time; they are currently live but hardcoded.
  `domain/prompting` keeps its no-I/O rule by using the existing injection-point
  pattern (`*git-status-resolver*`, `*prompt-time-resolver*` at
  `src/domain/prompting/prompt.lisp:5`), adding a resolver for the user function.

### Withdrawn by the syntax change

- **`math`** — arithmetic is native: `(* 3 (+ 2 4))`.
- **`argparse`** — a lambda list is the argument specification.
- **`set -l` / `set -g`** — superseded by lexical `let`.

Both `math` and `argparse` exist in fish only because shell syntax cannot
express expressions and parameter lists. They are not needed here.

## Compatibility

Breaking changes are acceptable without a migration path. The project is at
0.4.x and in early development; the old fish syntax is discarded rather than
deprecated.

## Open questions

Not settled. Listed so they are not mistaken for decisions.

- **Record representation.** plist, struct, hash table, or a dedicated record
  type for the values flowing through `->`. plist is the working assumption
  (writable as a literal, handles heterogeneous records, easy to test), but this
  has not been decided and affects both the API and performance.
- **Multi-line S-expressions in history.** History is currently line-based, and
  autosuggestion matches on line prefixes. A three-line `(when ...)` breaks the
  history unit, the `Ctrl-R` display, and the prefix-match rule. fish collapses
  newlines to a glyph for display; storing history *as S-expressions* would
  additionally make `(-> (history) (where ...))` possible, which fits the
  structured-data decision.
- **`^`'s exact spelling** and whether it is a reader macro or part of the symbol.
- **Macro-expansion error diagnosis.**
- **`abbr` and history expansion (`!!`, `!$`).** These are input-assistance
  features and are syntax-independent in principle, but what an abbreviation
  expands *to* under S-expressions is unspecified.
- **Project positioning.** "fish-inspired shell in Common Lisp" no longer holds.
  README, the docs site, and the man page all state it.

## Suggested order of work

1. ~~**Removals** (events, `ls`, `prompt-format`).~~ Done. Independent of the
   syntax, already decided, and shrank the tree before the hard work starts.
2. **Reader prototype.** Settle `readtable-case` and verify the claim that the
   executor is unaffected, by producing existing AST nodes from the new reader.
   This validates or invalidates the whole design.
3. **Specification of the remaining open questions**, informed by the prototype.
4. **`bind` and user-defined prompts.** Independent of the syntax and can
   proceed in parallel.

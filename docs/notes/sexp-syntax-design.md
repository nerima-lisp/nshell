# S-expression syntax redesign

The old reader remains the default input path. The isolated reader prototype
tests the AST boundary; it does not switch the REPL or source reader to
S-expression input. The three removals under [Remove](#remove) have shipped and
are marked as such.

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

Goal 4 is the weakest of the four and does not survive intact. See
[Where host-language unity stops](#where-host-language-unity-stops).

## The evaluation rule

> When evaluating a form `(head args...)`: if `head` is bound as a special
> operator, macro, or function, evaluate normally as Common Lisp. Otherwise the
> form is checked against the shell-function table, then becomes a **command
> form** if no binding exists, read its arguments under an implicit backquote
> and execute the command. Inside a command form, `,expr` (equivalently `$x`)
> returns to normal evaluation context.

Resolution order is Common Lisp special operator, macro, or function; lexical
then global shell-function binding; otherwise command form. A Common Lisp
binding takes precedence over a shell function with the same name, and a shell
function takes precedence over an external command.

An unescaped head named `not` resolves to `CL:NOT`; its invocation is
evaluator-aware as described under [Errors](#errors).

Command forms are islands of implicit quotation. Nesting follows Common Lisp's
existing quasiquotation rules.

```lisp
(ls -la)                      ; ls unbound -> island; -la is the string "-la"
(echo ,(* 3 (+ 2 4)))         ; echo is an island; , returns to evaluation -> 18
(when (test -f x.txt)         ; when is a macro -> outside the island
  (cat x.txt))                ;   test and cat are unbound -> islands again
(when (> $count 10) ...)      ; outside an island, > is CL numeric comparison
(ls -la > "out.txt")          ; inside an island, > is a redirection
```

Shell-style command substitution disappears. Command forms return values, so
`(set branch ,(git rev-parse --abbrev-ref HEAD))` evaluates the nested command
and passes its value to `set`. `$` followed by a form, such as `$(pwd)`, remains
reader syntax for evaluation; it does not capture command output as a string or
interpolate into a surrounding string. There is no shell-style `$(cmd)` string
substitution and therefore no `"$(cmd)"` quoting problem.

## Reader

### Bare lines are sugar

At each input boundary, leading whitespace is skipped. If the first remaining
character is `(`, the S-expression reader handles the whole input; otherwise
the bare-line scanner handles it. Bare input is tokenized before form
construction. Each command head and its arguments become a command form;
top-level `|` groups command forms into a byte-stream pipeline, while `;`,
`&&`, `||`, and `&` form sequence nodes. The interactive experience keeps bare
command entry.

In bare input, `|` binds more tightly than `&&` and `||`. The latter have equal
precedence and associate left to right. `;` is the lowest-precedence
separator and ends the current command list item. `&` backgrounds the pipeline
immediately to its left and ends that item. This groups
`a | b && c || d; e` as `((a | b) && c) || d; e`.

The tokenizer recognizes adjacent `|&` as one pipe operator that merges the
left stage's stderr into stdout before the next stage, matching `2>&1`.
Whitespace separates the tokens: `cmd | & next` is invalid because the pipe
has no right-hand stage; it does not mean `cmd | next &`.

The ampersand route also recognizes adjacent `&>` and `&>>` as combined-output
redirects. `cmd &> file` redirects both output streams. In `cmd & > file`, `&`
is the background separator, leaving `>` without a command, so parsing fails.

```
ls -la                        ; identical to (ls -la)
cat f.txt | grep foo | wc -l  ; identical to (| (cat f.txt) (grep foo) (wc -l))
```

Bare lines are a notation, not a second language. Structured control forms
such as `if` exist only as S-expressions. Bare `&&` and `||` are sequence
operators that conditionally run the next command from the preceding exit
status; they do not add bare-line block syntax. Delimiters inside strings,
comments, or escaped symbols are not bare-line operators.

Bare redirects that require a target are invalid when that target is missing.

### Symbol case is context-sensitive

The prototype uses a private readtable with `readtable-case :preserve`. This
keeps command-island symbols such as `-la`, `*.lisp`, and `MiXeD` byte-for-byte
when they become command arguments. In host-language positions, symbol lookup
canonicalizes an unescaped name to the corresponding uppercase Common Lisp
name, so `(when ...)` resolves to `CL:WHEN`. The conversion happens at host
symbol resolution, never while reading or stringifying command-island values.
The reader does not modify the process readtable or caller package.

For each island, the prototype creates a fresh package that uses `COMMON-LISP`.
Symbols not inherited from that package are interned there, converted to
strings when building command arguments, and discarded with the temporary
package after AST construction. For example, `(echo :state)` produces the
argument string `state`; in a plist, the same symbol remains a keyword key.
Explicit keyword literals keep Common Lisp reader semantics and are interned
in the shared `KEYWORD` package. This is intentional because the host language
is available and records use keyword plists; deleting the temporary reader
package does not undo keyword interning. For host-form detection, the
prototype rereads only command heads with an upcasing readtable; its escaped
symbol reader still preserves their spelling. It does not reread argument
forms, avoiding an uppercase duplicate of a keyword argument. The prototype is
not a sandbox for untrusted source.

This case-preservation decision rejects `readtable-case :upcase`, which corrupts
argument spelling before the reader can distinguish code from command data.
Defining duplicate lowercase Common Lisp forms would also split the host
namespace and is not needed with context-sensitive lookup. Escaped Common Lisp
symbols retain their explicitly supplied spelling and package semantics.

### Stringification

Only symbols stringify. Numbers and string literals pass through and are
converted at the point of argument construction. In bare-line input, single
quotes (`'...'`) and double quotes (`"..."`) delimit one argument and set
`command-arg.quote-style` to `:single` or `:double`; the scanner removes
those delimiters. In an S-expression, double-quoted Common Lisp strings are
string values, while apostrophe keeps its Common Lisp quote syntax.

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

`|` carries byte streams between external commands. `->` carries structured
values between internal commands and transformations.

In an S-expression, a standalone `|` token is the pipeline operator, as in
`(| (cat f.txt) (grep foo))`; the reader does not pass that token to the Common
Lisp reader as an escaped symbol. A delimited `|name|` remains an escaped
symbol. In bare input, the same standalone-token rule distinguishes pipeline
operators from escaped symbols.

```lisp
(| (cat f.txt) (grep foo) (wc -l))

(-> (jobs)
    (where (= :state "stopped"))
    (select :id :command))
```

### Internal commands stay minimal

Internal commands (the ones that return records) are deliberately few. `ls`,
`ps`, and other everyday tools stay external, so `ls -la` behaves exactly as it
always did and no muscle memory is broken. A command is only internalised when
structure genuinely buys something the external tool cannot give.

`^` forces the external resolution of a name that also exists internally
(`(^jobs)`). The marker is a single prefix attached to the command-head symbol;
it is not a reader macro and does not take whitespace (`(^ jobs)` is invalid).
Making `^` a reader macro was rejected because the marker has meaning only in
command-head position; keeping it in the symbol lets the command reader apply
that context-specific rule without changing reader dispatch.
The prototype strips the prefix from the executable name and keeps the marker
in sidecar metadata because the current AST has no slot for it.

### Conversion at the boundary is explicit

On successful completion, an external command's value is its stdout as one
string, including line breaks and any trailing newline. Stderr stays on the
separate diagnostic output channel unless a redirect merges it with stdout.
Exit status stays separate as execution metadata. `|` connects process byte
streams; `->` passes returned values, so
`from-json` and `from-tsv` receive that stdout string. Crossing into structured
data is always a visible call, never inferred.

```lisp
(-> (^ps aux) (from-tsv) (where (= :user "take")))
(-> (cat data.json) (from-json) (select :name))
(-> (jobs) (to-json) (jq ".[] | .id"))
```

## Errors

A non-zero exit signals a `command-failed` condition.

The exception, taken directly from POSIX `set -e`: **in a conditional context,
the test position of `if`, `when`, `unless`, `and`, `or`, or `not`, no
condition is signalled; exit status zero is true and non-zero is false.** The
evaluator enters that context before evaluating the test expression, so a
command nested in the expression sees it. For `and` and `or`, each operand is
evaluated in test context. The evaluator intercepts `not`, evaluates its one
operand in test context, and returns the normal Common Lisp boolean result.

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
trampoline (`src/presentation/cps.lisp:3-14`) and the line editor is a pure
reducer that returns state. Selecting a restart requires the Common Lisp stack
at the point of the signal to still be live, but the trampoline collapses the
stack at every step.

The resolution is to run a **nested input loop inside the handler** at the
signalling site. Adding a `:restart-select` input mode is unremarkable. Eight
modes already exist
(`data/presentation/input-state-data.lisp:12-17`), but the loop being driven
differently from the trampoline is a real, deliberate exception to the REPL's
structure, and should be documented as such where it is implemented.

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

The existing `set -l` and `set -g` behavior remains implemented. Whether those
options are retained, deprecated, or redefined under the new evaluator is a
separate compatibility decision; lexical `let` does not remove the current
builtin by itself.

## Macros

Macros are core, not an extension. `->`, `|`, and user-defined forms are
macros. Common Lisp special operators and macros keep their host semantics;
the evaluator adds conditional-status handling while it evaluates their test
positions. `not` keeps its boolean behavior through the shell-aware adapter
described above. Macros receive unevaluated forms, so `(my-macro ls -la)` sees
`ls` and `-la` as symbols and can expand them into a command form. The macro
requirement and the "bare symbols are strings" requirement do not conflict.

Macro-expansion failures must not surface as reader or island-rule errors. The
expander records a source span for every reader-produced form and carries the
origin span onto forms generated by expansion. A macro syntax condition is
reported at the nearest user-written form whose expansion was active; nested
expansion keeps that origin chain. The diagnostic includes source path, line,
column, and half-open source offsets. The expander catches only its dedicated
macro-syntax condition and preserves the original condition as the cause; it
must not convert arbitrary runtime errors into syntax errors. The reader
prototype does not evaluate or expand user macros.

## Where host-language unity stops

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

### The AST dispatch boundary can be reused

The application layer dispatches on AST node predicates
(`src/application/execute-pipeline-control.lisp:250`) and reads accessors such
as `command-node-args` (`src/application/execute-pipeline-stage.lisp:131`). It
never sees syntax. A new reader that produces the same `command-node` and
`pipeline-node` values can reuse that dispatch and its ordinary external
execution path.

The full migration still changes application code: argument expansion and
conversion, redirect handling, command resolution, structured pipeline
execution, and command substitution all consume syntax-facing data. The reader
prototype only verifies that the existing AST factory reaches the current
execution API; it does not prove that these consumers need no changes.
`src/application/execute-command-substitution.lisp` reparses command text and
captures output for the legacy substitution syntax, so that helper is removed
with the legacy expansion path. The new `$(form)` evaluation syntax is handled
by the reader and evaluator, not by reparsing command text. The replay/display
logic in `src/presentation/repl-output-handlers.lisp` is a separate consumer
and must be migrated to reader-produced forms and spans.

### Assets that survive

| | lines | note |
|---|---|---|
| `src/presentation/input-state*` | 2,823 | pure reducer, syntax-independent |
| `src/domain/completion/` + `src/infrastructure/` | 4,891 | knowledge base retained |

Completion keeps the Prolog knowledge base and its `completes` / `has-flag`
predicates. Context extraction is replaced, while the public
`completion-context` contract remains its existing five fields:
`command`, `argument-prefix`, `argument-words`, `command-position-p`, and
`redirection-target-p`. The new scanner supplies the structural facts used to
populate those fields.

Highlighting depends on the AST and needs rework, which is likewise easier with
explicit structure.

## Contracts for the prototype and follow-on work

These contracts keep the reader, REPL editor, evaluator, executor, and
completion work parallelizable. The prototype is isolated from the default
input path and does not implement every production contract below.

### WP-L00 decisions and implementation contracts

- **D-12:** Preserve input case in command-island data with a private
  `:preserve` readtable. Resolve unescaped host-language heads separately with
  an upcasing readtable; do not normalize command arguments while reading.
- **D-13:** Use keyword/value plists for records, with unique keys, source
  order, and `nil` for an empty collection. Use `get-properties` when a caller
  must distinguish an absent key from a present key whose value is `nil`.
- **`^` spelling:** Attach one `^` directly to the command-head symbol, as in
  `(^jobs)`. It is command-head metadata, not reader syntax; `(^ jobs)` is
  invalid. The prototype returns it in sidecar metadata because the current AST
  has no typed field.
- **Macro diagnostics:** Report a macro syntax condition at the nearest
  user-written form whose expansion was active, carrying its source span
  through nested expansion. Catch only the dedicated macro syntax condition
  and preserve the original condition as its cause. The reader prototype does
  not expand or evaluate macros.

The prototype lives in `src/domain/parsing/sexp-reader-prototype.lisp` and
produces the existing command and pipeline nodes. Its integration tests pass
those nodes to the current public pipeline execution API. The tests do not
wire the prototype into the default input route, which continues to use the
old reader.

For bare redirects, the prototype applies the current
`%redirect-targetless-p` policy. File, append, here-document, here-string, and
combined-output operators require a following word in the same command stage;
this includes `0<`, `0<<`, `0<<-`, `0<<<`, `>`, `>>`, `<`, `<<`, `<<-`, `<<<`,
`1>`, `1>>`, `2>`, `2>>`, `&>`, and `&>>`. `2>&1` and numeric descriptor
duplication forms such as `3>&4`, `0<&3`, and `3>&-` do not require a file
target. If a balanced input line ends without a required target, the reader
reports an error instead of waiting for another line; it does not count as
incomplete input. The prototype validates the target but continues to encode
redirects in the existing command arguments; production ASTs must use the
separate typed redirect entries specified below.

### One depth scanner

One incremental scanner is the source of truth for multiline continuation,
delimiter pairing, indentation, highlighting, and completion context. It
returns complete, incomplete, or invalid status; the open-delimiter stack;
matched delimiter spans; the invalid span when present; and the next-line
indentation. Every span uses half-open source offsets `[start,end)`. An
unmatched close is invalid at that character; an unclosed delimiter, string,
escaped symbol, or block comment is incomplete. Scanner state recognizes
strings and escapes, `|...|` escaped symbols, line comments, nested `#|...|#`
comments, and `#\` character literals so their delimiter characters do not
affect depth.

The scanner and tokenizer share one rule for `|`: a standalone token is the
pipeline operator; a delimited `|name|` is an escaped symbol. Bare-line `;` is
a sequence separator, while `;` inside an S-expression starts a line comment.
The scanner tracks which reader context applies instead of assigning one
meaning globally. Pairing, highlighting, indentation, and completion consume
the same token and span decisions; none re-counts delimiters independently.
Indentation uses the unmatched open-form stack, aligns a leading close with its
opener, and adds one configured indent unit for a continued form.

Completion continues to expose exactly the five fields listed above. New
reader state may be added internally, but consumers should not grow a parallel
context shape. The scanner determines command versus argument position and
whether the cursor is in a redirect target before the context is projected.

### Values and the external boundary

Inside a command island, an ordinary symbol becomes one command argument using
its exact symbol name and retains source span and quote/glob metadata.
`command-arg.quote-style` is `nil` for an unquoted argument, `:single` for a
single-quoted argument, and `:double` for a double-quoted argument. Only an
unquoted symbol may glob-expand; quoted strings and escaped symbols remain
opaque. Explicit `$` or `,` evaluation produces one scalar argument and never
performs implicit word splitting. Numbers are converted to strings when
constructing an external argument. Lists and records remain Lisp values for
structured pipelines and must be converted explicitly before crossing an
external process boundary. Each external argument contributes exactly one
argv string; splitting and re-parsing are forbidden.

Records use plists. The existing history persistence already
reads and writes plist records (`src/infrastructure/persistence/file-history.lisp`),
so this reuses a representation the project already persists and reads. A
record is a keyword/value plist with unique keys and source order preserved. A
collection of records is a list of plists; the empty collection is `nil`.
`getf` reads a value, and callers that must distinguish an absent key from a
key whose value is `nil` use `get-properties`. A dedicated record struct or
hash table was not chosen because it would add a second record representation
without improving the persistence seam identified for the reader gate; this makes
no performance claim. Byte streams and structured values remain distinct:
`|` connects byte streams, `->` connects structured values, and `from-json`,
`from-tsv`, and `to-json` are explicit boundary conversions.

### Redirect and forced-external representation

Production AST data separates redirects from positional arguments. Each
redirect entry carries its operator kind, file descriptor, target argument,
source span, and source order. A quoted string such as `">"` is always a
positional argument and cannot become a redirect by text inspection. The
current AST stores redirect syntax among command arguments and
`split-command-node-redirects` infers redirects from those strings without
checking quote style. The reader prototype may reuse that encoding to prove
the ordinary command and pipeline execution seam, but it cannot prove that a
quoted S-expression argument such as `(printf ">" "target")` remains positional
through the current executor. That behavior requires typed redirect entries
before the production migration ships new quoting semantics.

The prototype validates target presence only for bare-line redirects. It does
not validate redirect positions inside S-expression command islands, so
`(echo >)` can produce a command node without a target check. This path is not
part of the P2 execution proof; a production reader must represent and validate
S-expression redirects with the typed entries above.

The `^` marker is likewise explicit metadata (`force-external`) on the command
head. The prototype keeps it in a sidecar because the current AST has no such
slot. The production resolver must receive a typed marker, either in the AST or
in an explicit resolution input; it must not recover the marker from the
stripped command name.

### Function table

The current shell function table stores function bodies as source lines
(`src/application/shell-context.lisp`), which requires runtime reparsing. The
new shell function registry is separate from the Common Lisp global function
namespace. Its global table maps canonical function names to
`shell-function-binding` values, not source strings. A binding contains its
callable closure, declared lambda list, display name, and definition source
path/span. Registry keys use uppercase names for unescaped symbols and preserve
the exact name of escaped symbols, matching host-symbol resolution. Function
bodies are captured as executable forms or a closure when
defined, never as raw source lines to be parsed on invocation. A lexical
function table overlays the global table; lookup checks the lexical table
first, then the global table. Completion projects names from these tables into
the existing five-field context.

### Affected integration paths

The parser and expansion rewrite is only one part of the migration. The
following existing consumers must adopt the shared scanner or value contract
when their syntax-facing behavior changes:

- `src/presentation/highlight.lisp` and
  `src/presentation/repl-highlight.lisp` derive highlighting from scanner
  tokens and spans;
- `src/domain/completion/context.lisp`,
  `src/presentation/completion-ui-logic.lisp`, and
  `src/presentation/completion-ui-text.lisp` keep the five-field context
  projection and insert syntax-valid text;
- `src/domain/history/last-argument.lisp`,
  `src/presentation/repl-history-last-argument.lisp`,
  `src/presentation/repl-output-handlers.lisp`, and
  `src/presentation/repl-diagnostics.lisp` keep display, diagnostics, and
  last-argument behavior aligned with source spans and one-argument-per-value
  semantics;
- `src/presentation/repl-execution.lisp`,
  `src/presentation/input-state-words.lisp`,
  `src/presentation/input-state-words-scan.lisp`, and
  `src/presentation/input-state-suggestion.lisp` share scanner decisions for
  execution boundaries, structural editing, and suggestions;
- `src/domain/abbreviation/expansion.lisp` expands input before the shared
  reader and scanner process it;
- `packages/feature/assistant/src/domain/safety.lisp` and
  `packages/feature/assistant/src/domain/redaction.lisp` retain the existing
  safety policy and redact values before history or assistant output persists
  or displays them;
- `src/application/builtin-runtime.lisp`,
  `src/application/execute-pipeline-stage.lisp`, and
  `src/application/builtins.lisp` adopt new expression-evaluation and external
  argument boundary contracts.

The input-state reducer and completion knowledge base can remain
syntax-independent, but their callers must use the shared scanner results.

## Feature decisions independent of the syntax

These were settled before the syntax change and are unaffected by it.

### Remove

- ~~**Domain events and the event dispatcher**~~. `make-event-dispatcher` is called
  only from tests; `publish-event` sites are all guarded by `(when dispatcher
  ...)` and never fire in production. The subsystem also cannot serve as a hook
  foundation: `define-event-constructors`
  (`src/domain/events/base-event.lisp:17`) discards every payload argument, so
  an event cannot carry a job id or an exit code. Scope: 98 source lines, 152
  test lines, and the `&optional dispatcher` parameter on 5 functions.
- ~~**The `ls` builtin**~~. `src/application/builtin-commands.lisp:321` declares
  `args` ignored, so `ls -la` silently produces an unsorted, uncolumned listing,
  and the builtin shadows the real `ls`. Delegate to the external command.
- ~~**`config`'s `prompt-format`**~~. Nothing reads it; the prompt is built from
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
  keys to arbitrary shell commands, which needs a `commandline` builtin to
  read and write the edit buffer from shell code, crossing the pure-reducer
  boundary, is explicitly deferred.
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

### Recheck under the syntax change

- **`math`:** arithmetic is expressible as `(* 3 (+ 2 4))`, but the existing
  `math` builtin remains implemented. Decide whether to retain it after the
  evaluator and builtin contracts are specified.
- **`argparse`:** a lambda list is the argument specification.
- **`set -l` / `set -g`:** lexical `let` does not replace the implemented
  options; decide their future semantics explicitly.

`argparse` has no implementation in the current tree. Do not describe `math` or
`set -l` / `set -g` as removed until a separate change removes or replaces
their current behavior.

## Compatibility

Breaking changes are acceptable without a migration path. The project is at
0.6.x and in early development; the old fish syntax is discarded rather than
deprecated.

## Open questions

- **Multi-line S-expressions in history.** History is currently line-based, and
  autosuggestion matches on line prefixes. A three-line `(when ...)` breaks the
  history unit, the `Ctrl-R` display, and the prefix-match rule. fish collapses
  newlines to a glyph for display; storing history *as S-expressions* would
  additionally make `(-> (history) (where ...))` possible, which fits the
  structured-data decision.
- **`abbr` and history expansion (`!!`, `!$`).** Keep `!!` and `!$` as
  pre-reader expansion on bare interactive input only. Abbreviations also
  expand at the input layer, and their output must pass through the shared
  scanner and reader. Exact multi-line display and history behavior remain open.

## Suggested order of work

1. ~~**Removals** (events, `ls`, `prompt-format`).~~
2. **Reader prototype.** Validate the `readtable-case` and `^` choices by
   producing existing AST nodes from the new reader and checking the executor
   seam. This validates the AST boundary, not the full syntax migration.
3. **Specification of the remaining open questions**, informed by the prototype.
4. **`bind` and user-defined prompts.** Independent of the syntax and can
   proceed in parallel.

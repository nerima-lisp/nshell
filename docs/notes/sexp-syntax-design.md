# S-expression syntax redesign

The old reader and parser remain on the default input path until WP-X01 switches
after the [P5 reader-switch gate](#contracts-for-the-prototype-and-follow-on-work)
passes. WP-X01 then removes the old reader and its reader-specific tests. The
isolated reader prototype tests the AST boundary; it does not switch REPL input
or the source reader to S-expression input. P3 implementations may build the
new path against these contracts while the legacy path remains active; they do
not change the legacy path's behavior or make S-expressions the default.

The headline decision: nshell stops being fish-inspired. The surface syntax
becomes S-expressions, with bare command lines as sugar over them.

## The evaluation rule

The evaluator resolves each S-expression head using the order specified under
[Head resolution](#head-resolution-and-user-package). A resolved host form evaluates as Common
Lisp. Any other list is a command form: its head names the command and its
arguments are evaluated under command-island rules. `,expr` and `$expr` escape
an island argument back to value evaluation.

The reader uses the persistent `NSHELL.USER` package for user definitions.
Bare-line input is always shell command syntax and never resolves a head as a
host-language function.

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

Each parenthesized list is classified from its own first direct element.
Thus `when` is a host form, while the nested `(test ...)` and `(cat ...)` lists
are command forms because their own heads do not resolve as host forms. Atoms
directly inside the `when` form remain host-language syntax.

Shell-style command substitution in command forms disappears. Command forms
return values, so `(set branch ,(git rev-parse --abbrev-ref HEAD))` evaluates
the nested command and passes its value to `set`. `$` followed by a form,
such as `$(pwd)`, remains reader syntax for evaluation; it does not capture
command output as a string or interpolate into a surrounding string.
Unquoted here-document bodies keep their established text-expansion behavior
as specified under [Typed redirects and pipeline edges](#typed-redirects-and-pipeline-edges).

## Reader

### Bare lines are sugar

At the REPL, the REPL accumulates physical lines and joins successive lines
with one newline until the full-buffer scanner returns a complete submission;
an `:incomplete` result requests another line. The scanner retains no state
between calls. On a complete submission, leading whitespace is skipped. If
the first remaining character is `(`, the S-expression reader handles the
whole submission; otherwise the bare-line parser in `sexp-reader.lisp`
tokenizes the input and constructs its command, pipeline, and sequence AST.
The full-buffer `scan-input` API in `sexp-scanner.lisp` is a separate
structural scan for editor and completion consumers; it does not build
executable AST nodes. The reader and scanner are separate APIs, but both follow
the token-boundary and operator rules in this note. They may share private
tokenization helpers. The REPL keeps blank lines; the joined source includes
inserted newlines, and all spans are offsets into that source.
Each command head and its arguments become a command form;
top-level `|` groups command forms into a byte-stream pipeline, while `;`,
`&&`, `||`, and `&` form sequence nodes. The interactive experience keeps bare
command entry.

The first non-whitespace character selects the submission mode before history
expansion: a top-level S-expression submission must begin with `(`. A
standalone quote, vector, or atom is not a top-level command submission; those
reader forms may appear inside a parenthesized form or at a command-island
argument boundary. `!!` and `!$` expand only for bare interactive input, and
the expanded text then goes through the scanner and reader. An S-expression
submission may contain multiple top-level forms. The reader returns one
`reader-result` per form, in source order, and the REPL evaluates them in that
order. A source file uses the same mode-selection rule without interactive
history expansion. A bare-line submission continues to produce its single
command or sequence AST.

WP-L01 exposes `read-submission(source)` from `sexp-reader.lisp`. The REPL and
source-file reader call `scan-input` first and call `read-submission` only when
the scan is `:complete`. An `:incomplete` scan inserts a newline at the current
input cursor, followed by `next-indent` spaces, then places the cursor after
those spaces for the next physical line. The inserted text stays in the same
input buffer. Existing text after the cursor remains after the inserted line.
An `:invalid` scan is reported at `scan-result.invalid-span` and is not passed
to the reader; the editable buffer and cursor remain unchanged.
A nonempty bare-line submission returns a list
containing one `reader-result` whose `form` is its command, pipeline, or
sequence AST and whose `form-span-map` is an empty `eq` hash table. A
S-expression submission returns one `reader-result` per top-level form, each
with its own form and span map. Whitespace-only input returns no results. If
the reader finds invalid syntax after a complete scan, it signals
`sexp-reader-error` with a half-open `source-span` and the original condition
in `cause`; it does not convert the error to an incomplete result. The REPL
reports that error and retains the buffer and cursor for correction.

For interactive S-expression input with multiple results, the REPL evaluates
each result in source order and calls L04's
`call-with-command-failure-restarts(thunk)` around each result separately. It
starts the next result only when evaluation of the current result returns
normally; a failure that unwinds out of the wrapper stops the remaining
results. The wrapper does not treat the result list as one failure transaction.

The reader builds these as `sequence-node` values with `make-sequence-node`.
`sequence-node-commands` stores sequence items, each a `command-node` or
`pipeline-node`. Its `separators` list stores one separator for each item that
has a following separator: normally there are one fewer separators than items;
a terminal `:amp` is retained after the final item to encode backgrounding. A
terminal `:semi` is discarded, and `:and` or `:or` cannot terminate a sequence.
`sequence-node-command-separators` returns one
`sequence-node-command-separator` per item. Its `command` slot contains the
item, which may be a `command-node` or `pipeline-node`, and its `separator` slot
contains the following separator. The accessor name is retained for
compatibility. It pads a final foreground item with a `nil` separator and
retains a terminal `:amp` on the last item. For `a | b && c`, the first item
is a pipeline node and the second is a command node.

In bare input, `|` binds more tightly than `&&` and `||`. The latter have equal
precedence and associate left to right. `;` is the lowest-precedence
separator and ends the current command list item. `&` backgrounds the pipeline
immediately to its left and ends that item. This groups
`a | b && c || d; e` as `((a | b) && c) || d; e`.
The grammar requires a pipeline before every sequence separator and after each
nonterminal separator. A leading separator is invalid at that token, so `; a`
is invalid at its first `;`. When an operand is required, another separator
before a pipeline is invalid at that next separator: `a && ; b` is invalid at
`;`, and `a && && b` is invalid at the second `&&`. A trailing `&&`, `||`,
`|`, or `|&` at end of input is incomplete because its right operand is
missing. A trailing `;` or `&` is complete as specified above.

WP-L08 owns execution of these bare-line sequence operators. In `&&` and `||`
chains, an item whose following separator is `:and` or `:or` runs in test
position because its status controls the next item. Every other foreground
item, including an item followed by `:semi` and the final item, follows the
active D-06 failure policy. Exit status `0` is true and every nonzero status is
false. The status of the sequence is the status of its last executed item.
Thus, in `a && b || c`, the statuses of `a` and `b` control short-circuiting,
while `c` is the final item and follows the surrounding failure policy.

For `&`, successful background launch returns parent status `0` immediately,
registers the job with the monitor, and does not wait for child completion. The
monitor reaps the job asynchronously; a later child status does not change the
parent sequence status or signal `command-failed` in the parent. A failure to
start the background command is returned synchronously by L05 and follows the
D-06 policy. A plan error reported at its source span, such as process
substitution under `&`, signals `command-execution-plan-error` before a job
is registered and does not update `$status` or `pipestatus`. In `a & b && c`,
`a` is backgrounded, then `b` runs in the foreground and its status determines
whether `c` runs.

Only a simple source-level head is eligible for command-island resolution. A
computed or compound head, such as `((choose-form) arg)` or `("echo" arg)`, is
host syntax; the reader does not evaluate a head and then reinterpret its
result as a command name. The word “lexical” in the head-resolution order means
a shell-function binding in the active `shell-function-scope`, not a Common
Lisp `flet` or `labels` binding. The scanner callback has no Common Lisp
lexical environment, so such local function names do not select a command
island; package-local `NSHELL.USER` functions and macros are resolved by their
exact symbol names.

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
status; the item immediately before either operator is in test position under
D-06. They do not add bare-line block syntax. Delimiters inside strings,
comments, or escaped symbols are not bare-line operators.

### Symbol case is context-sensitive

The production reader uses a private readtable with
`readtable-case :preserve`. It keeps command-island symbols such as `-la`,
`*.lisp`, and `MiXeD` byte-for-byte when it builds command arguments. In a host
form, the evaluator resolves unescaped names in `NSHELL.USER` and the Common
Lisp namespace without changing command data. The reader never changes the
process readtable or caller package.

`NSHELL.USER` is persistent across input forms and uses `COMMON-LISP`. User
definitions therefore remain available to later forms. An ordinary keyword
literal such as `:state` remains a keyword for value operations and converts to
the symbol name `state` when used as an external argument. A record continues
to use keyword keys. Command-island package-like text such as `name:/path` is
data, not a package reference. Package qualification is parsed only in a
host-form position.

Structured records use property lists with keyword keys. The empty record is
`nil`.

The prototype still uses a temporary package and rejects `#` dispatch. Those
prototype limits do not define the production reader contract. The reader is
not a sandbox for untrusted source.

### Stringification

Strings pass through unchanged, numbers use their printed notation, symbols use
their names, and character values become one-character strings. These
conversions apply to Lisp values at an argument boundary. Ordinary
command-island tokens remain source text, including numeric-looking tokens; only host forms or explicit value expressions produce Lisp numbers.
In bare-line input, single quotes (`'...'`) and double quotes (`"..."`)
delimit one argument and set `command-arg.quote-style` to `:single` or
`:double`; the scanner removes those delimiters. In an S-expression,
double-quoted Common Lisp strings are string values, while apostrophe keeps
its Common Lisp quote syntax.

```lisp
(head -n 10)   ; "-n" and "10" remain source tokens -> "-n" "10"
(ls -1)        ; "-1" remains a source token
```


### `$` is sugar for `,`

`$x` and `,x` are the same reader-level construct; `$(pwd)` and `,(pwd)` are the
same form. `$` exists so interactive muscle memory carries over; `,` exists so
macro authors see ordinary quasiquotation. The evaluator resolves the
unquoted expression in its active value environment, including lexical `let`
bindings and shell variables such as `status`; `$` is not a separate variable
expansion pass.

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

In an S-expression, `|` is a pipeline operator only as the head of a pipeline
form, as in `(| (cat f.txt) (grep foo))`. At an argument position, an unquoted
standalone `|` is the literal argument string `"|"`. A delimited `|name|` is
an escaped symbol and never acts as an operator. In bare input, a standalone
unquoted `|` is a pipeline operator and adjacent `|&` is a pipeline operator
that also connects the left stage's stderr to the right stage's stdin.

```lisp
(| (cat f.txt) (grep foo) (wc -l))

(-> (jobs)
    (where (= :state "stopped"))
    (select :id :command))
```

### Internal commands stay minimal

The few internal commands that return records are `:value` builtins.
`ls`, `ps`, and other everyday tools stay external, so `ls -la` behaves exactly
as it always did. A command is only internalised when structure genuinely
buys something the external tool cannot give.

`^` forces lookup of the executable name in `PATH` only (`(^jobs)`). The marker
is one prefix attached to the command-head symbol; it is not a reader macro and
does not take whitespace (`(^ jobs)` is invalid). Its AST behavior is specified
under [Head resolution](#head-resolution-and-user-package).
`sexp-reader-prototype-command-metadata` is a prototype-only struct with
`command-node` and `force-external-p` slots. The prototype returns it as a
second value: a list with one entry per command stage, in source order, whose
`command-node` slot references the corresponding AST node. The boolean remains
for existing prototype callers; production consumers read the AST slot.

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

A failing command updates `$status` to the final pipeline stage's shell status and updates `pipestatus` with every stage's shell status in source order. The rules below define when a nonzero status signals and how pipeline failure is selected:

- At an interactive top-level command boundary, display the failure status and continue without signaling.
- In a function, a script, or an invocation using `-e`, signal `command-failed` for a pipeline failure selected by the pipeline rules below.
- In the test position of `if`, `when`, `and`, `or`, or `not`, return a boolean from the final stage status and do not signal. `and` and `or` evaluate each operand in test position. `unless` is not included in this test-position contract.

Test position applies only to a command form evaluated directly as the test or operand. A host-language form keeps its Common Lisp result. Commands evaluated inside that host form's function arguments use value position and follow the active function, script, or `-e` failure policy.

`command-failed` is owned by WP-L04 in `nshell.application` and has these slots:

| Slot | Type | Meaning |
|---|---|---|
| `command` | string | Command name of the selected failing stage. |
| `status` | integer | Normalized shell status of the selected failing stage. |
| `stage-statuses` | list of integers | Normalized shell statuses for all stages, in source order. |
| `signal` | `(or null (integer 1 *))` | Raw signal number for the selected stage, or `nil` after a normal exit. |

The pipeline evaluator retains each stage's raw signal while selecting failures. A nonzero upstream stage terminated by `SIGPIPE` is excluded. If several other stages have nonzero statuses, select the first one in source order for `command`, `status`, and `signal`. The pipeline's ordinary `$status` remains the final stage status, even when an earlier stage supplies the condition's `status`.

WP-L04 defines these special variables in `nshell.application`:

| Variable | Type | Binding owner and purpose |
|---|---|---|
| `*interactive-top-level-p*` | boolean | WP-L04 defines it; the presentation boundary binds it true for direct interactive input. WP-L02 and WP-L07 bind it false inside functions and scripts. |
| `*command-test-position-p*` | boolean | WP-L04 defines it; WP-L02 binds it around direct command forms in the test positions above. |
| `*errexit-p*` | boolean | WP-L04 defines it; WP-L07 binds it from the script `-e` option. |

WP-L04 owns the condition and failure policy. WP-L02 owns evaluator test bindings, WP-L08 binds test position around bare-line sequence items whose following separator is `:and` or `:or`, WP-L07 owns script and `-e` bindings, and the presentation layer owns the interactive top-level binding. When a condition is raised during an interactive function or script call, WP-L04 offers restarts from a nested input loop at the signalling site. A direct top-level command failure does not enter that loop.

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

`set -l` and `set -g` remain supported options of the existing `set` builtin,
with their current local- and outermost-scope effects. WP-L03 exposes the
existing handler through its `:argv` binding; `let` adds lexical bindings and
does not redefine these options. Changing their behavior requires a separate
accepted requirement and does not block WP-L03.

## Macros

Macros are core, not an extension. `->`, `|`, and user-defined forms are
macros. Common Lisp special operators and macros keep their host semantics;
the evaluator adds conditional-status handling while it evaluates their test
positions. `not` keeps its boolean behavior through the shell-aware adapter
described above. Macros receive unevaluated forms, so `(my-macro ls -la)` sees
`ls` and `-la` as symbols and can expand them into a command form. The macro
requirement and the "bare symbols are strings" requirement do not conflict.

Macro-expansion failures must not surface as reader or island-rule errors. The
expander records a source span for every reader-produced compound form and
carries the origin span onto forms generated by expansion. A macro syntax condition is
reported at the nearest user-written form whose expansion was active; nested
expansion keeps that origin chain. The diagnostic includes source path, line,
column, and half-open source offsets. The expander catches only its dedicated
macro-syntax condition and preserves the original condition as the cause; it
must not convert arbitrary runtime errors into syntax errors. The reader
prototype does not evaluate or expand user macros.

WP-L01 owns `sexp-reader-error` in `sexp-reader.lisp`, with slots `source-span`
(`nil` or a half-open span) and `cause` (`nil` or a condition). It also owns
`reader-result` with slots `form` (`t`) and `form-span-map` (an `eq` hash
table). Each result contains one
top-level form; its map covers only that form's tree. Keys are every
nonempty list root, vector, and compound reader-prefix wrapper created from
source, including nested forms. Reader-prefix wrappers include quote (`'`),
backquote, comma, comma-at, function quote (`#'`), and the shell value prefix
(`$`) when they produce a compound form. `#.` reader evaluation remains
disabled. A list contributes its root cons cell, not
its internal cdr cells. Atomic values and the empty list `nil` are not keys.
Each key maps to its half-open source span; interned symbols are never keys.
For a reader-prefix wrapper, the span starts at the first source character of
the prefix and ends after the complete prefixed operand, including nested
forms. For example, the wrapper produced from `'(a)` covers the quote and the
entire list.
WP-L02 looks up macro call forms in the map and carries the call span to
generated forms, preserving nested call origins for diagnostics.

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

### The AST dispatch boundary can be reused

The application layer selects execution by AST node predicates
(`src/application/execute-pipeline-control.lisp:250`) and reads accessors such
as `command-node-args` (`src/application/execute-pipeline-stage.lisp:131`).
This AST selection is separate from command-head resolution, which chooses
host evaluation, shell-function lookup, builtin lookup, or `PATH`, and from
builtin invocation, which selects the binding's argument mode. Execution
never sees source syntax.

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

| Asset | Role |
|---|---|
| `src/presentation/input-state*` | Pure reducer, syntax-independent. |
| `src/domain/completion/` and `src/infrastructure/` | Retained Prolog completion knowledge base. |

Completion keeps the Prolog knowledge base and its `completes` / `has-flag`
predicates. Context extraction is replaced; the new scanner supplies the
structural facts used to populate the existing `completion-context` contract
described under [Shared depth scanner](#shared-depth-scanner).

## Contracts for the prototype and follow-on work

P2 is the reader design gate, and WP-L00b owns its closure. It passes when the
prototype produces existing command and pipeline nodes, the existing execution
tests pass without expectation changes, and the shared contracts below are
fixed. WP-L00b records the result in its report; P3 and P4 start after P2
passes. P3 implements the language core; P4 implements syntax-dependent
interactive features. P5 is the reader-switch gate: every P0/P1 use-case
scenario in project requirements section 4 must pass on both operating systems,
NFR-01 through NFR-09 in section 6 must be met, and no T3
independent-verification finding under section 8 may remain. WP-X01 owns the
switch and may change the default input path only after P5 passes. These
contracts define the shared boundary for P3 and P4.
WP-L00b owns the AST definitions in
`src/domain/parsing/ast.lisp` and `src/domain/parsing/ast-arguments.lisp`;
follow-on work uses their constructors and accessors. No WP may redefine these
structs.

### Head resolution and user package

Common Lisp facilities remain available to user code. WP-L07 creates persistent package `NSHELL.USER` with `COMMON-LISP` in its use list and arranges ASDF loading for user modules. User code can define ordinary `defun` and `defmacro` forms there. The stable public `NSHELL` API remains limited to `NSHELL:MAIN`; `NSHELL.USER` is the evaluation package, not a promise to stabilize every internal shell API.

The evaluator resolves an S-expression command head in this order:

1. A `^`-marked head bypasses Lisp functions, shell functions, and builtins and searches `PATH` only. The reader stores the marker in `command-node.force-external-p` and removes the prefix from the command name.
2. An explicitly package-qualified host symbol is evaluated as a host form. This includes symbols in `CL` and `NSHELL.USER`.
3. Common Lisp special operators and macros, plus the evaluator-aware forms `if`, `when`, `and`, `or`, and `not`, are host forms. `not` uses the status-aware adapter in [Errors](#errors).
4. A package-local `NSHELL.USER` function or macro is evaluated as a host form. “Lexical” shell-function bindings are resolved at step 5 through the active `shell-function-scope`; Common Lisp `flet` and `labels` bindings are not inputs to command-island classification.
5. A lexical shell-function binding is checked, then the global shell-function registry.
6. Builtins are checked.
7. An executable is searched for in `PATH`.
8. An inherited ordinary Common Lisp function is evaluated as a host form only if no shell function, builtin, or executable matched.

This order keeps inherited names such as `find`, `sort`, `time`, `sleep`, `read`, and `print` from taking everyday command names. A package-qualified host head remains an explicit way to call them. Bare-line input always uses shell command resolution and never consults `NSHELL.USER` or the Common Lisp function namespace.

`classify-sexp-head(context head-source)` receives the active
`shell-context` and the exact source spelling of a simple head token. It returns
`:host-form` when this resolution selects host evaluation and
`:command-island` otherwise. It uses the same order as evaluation, including
package-qualified names, shell functions, builtins, and `PATH`, but never
evaluates a form or starts a process. WP-L02 owns this function; L01 and E03
pass a closure that supplies the active context to the scanner's
`head-classifier` callback. A non-symbol, computed, or compound head bypasses
this callback and remains host syntax. The callback's lexical shell-function
lookup uses the active shell-function scope; it does not infer Common Lisp
lexical function bindings from `shell-context`.

Host-form Common Lisp names use uppercase name lookup, so unescaped `nil`,
`t`, special forms, macros, and fallback functions work in lowercase. Exact
lexical or package-local `NSHELL.USER` definitions retain the spelling read
with `:preserve`. Escaped names never undergo this case conversion. Explicit
package qualifiers use the canonical names `CL:` and `NSHELL.USER:`.

### Command-island token rules

Command-island arguments are tokenized before Common Lisp reads host forms. The reader preserves each ordinary argument token's source spelling. Reader syntax is enabled only in the host-form and reader-prefix positions shown below.

| Input | Command-island rule |
|---|---|
| `.` and `..` | Each is one literal argument atom with its spelling preserved. A standalone dot in an argument list is not dotted-pair syntax. |
| `:name` | A keyword literal. As an external argument it converts to the keyword symbol's name without the colon; as a plist key it remains a keyword. |
| `pkg:name` or `name:/path` | One literal argument atom. A colon inside an argument does not select a package. Package qualification is recognized in host-form position. |
| `#` | Ordinary argument data. It does not start Common Lisp reader dispatch inside an island. `#\\` character literals are recognized only in host-form position. |
| `'` | In a host form, the Common Lisp quote prefix. At the start of an island argument (input start, after whitespace, or after `(`), it prefixes a Common Lisp quote form; inside an already-started argument atom it is data. |
| `$` and `,` | At an argument boundary, introduce value evaluation (`$x` is equivalent to `,x`). Inside an atom such as `a$b`, they are ordinary data characters. |
| Numbers | Ordinary island atoms preserve their source spelling, including `0755` and `1.10`. Numeric reader semantics apply in host forms; evaluated numbers are converted only when crossing to argv. |
| `|` and `|&` | At argument position, each standalone unquoted token is a literal argument with its source spelling. It is a pipeline operator only as the head of `(| stage...)` or `(|& stage...)`. |
| `|name|` | An escaped symbol whose exact name is preserved. It is never an operator and never glob-expands. |
| Redirect operators | Only an unquoted, unescaped direct element in a command form's argument list is syntax. Its following direct element is its target. A string, escaped symbol, nested form, or evaluated value whose value happens to be `>` remains positional data. |
| `<(form)` and `>(form)` | An adjacent unquoted marker and parenthesized command or pipeline form at a direct argument position is one process-substitution argument. The reader keeps it as one positional placeholder and adds a typed redirect entry with the nested form and shared source span. |

Glob metacharacters in an unquoted command-island source token expand when the
command crosses an argv boundary: an external process or a `:argv` builtin.
WP-L03 calls the public `nshell.domain.expansion:expand-glob(pattern
&optional filesystem)` for each eligible source string. It does not call
`expand-all`, which also performs brace, tilde, arithmetic, variable, and
list-reference expansion, or the private `%expand-glob-with-prefix` helper, which adds
assignment-like prefix behavior. `expand-glob` returns sorted matches, or a
one-element list containing the original pattern when there is no glob syntax
or no match. The current API suppresses directory-enumeration conditions, so
such a failure is indistinguishable from no matches and also returns the
original pattern. L03 preserves this API behavior; changing it requires a
separate expansion API change.

One eligible argument becomes one or more path strings. A `:value` builtin
receives its original evaluated arguments without globbing. String literals,
escaped symbols, and values produced by `$` or `,` never expand. No argument is
split into words or reparsed. The production reader records source eligibility
in `command-arg.glob-p`; WP-L02 carries that flag only for source tokens, while
evaluated values set it to `nil`.

A quoted form at an island argument boundary produces one unevaluated Lisp
value. A simple value uses the explicit argv conversion rules; a quoted list or
record is rejected by `:argv` and must be passed to a `:value` builtin or
converted explicitly.

### Values, stream positions, and builtin calls

A **value position** asks for one Lisp value. It includes an unquote expression, a host-function argument, a `let` initializer, and every input or stage of `->`. Host forms and shell functions return their Lisp value. An external command or `:argv` builtin returns stdout as one string, including line breaks and the trailing newline; a `:value` builtin returns its Lisp value. Stderr remains on the diagnostic channel unless a typed redirect merges it. Exit status remains separate metadata and follows [Errors](#errors).

A **stream position** writes or consumes bytes. It includes a bare-line command and every stage connected by `|` or `|&`. These positions connect byte streams and do not capture stdout as an argument. A structured value enters a byte stream only through an explicit conversion such as `to-json`. `->` passes the prior stage's Lisp value to the next stage; converting external output into structured data requires an explicit conversion such as `from-json` or `from-tsv`.

A `:value` builtin can run only in value position. Using one as a bare-line
command or a stage in a byte-stream pipeline is a source-located evaluator
error at the command head; the handler is not called and the result is not
serialized implicitly. A `:argv` builtin or external command in value
position returns stdout as one string. WP-L02 checks the value-versus-stream
position before invoking the binding owned by WP-L03.

`command-arg` remains the source-text argument type and gains these slots:

| Slot | Type | Meaning |
|---|---|---|
| `value` | string | Source argument text after reader delimiters are removed. |
| `quote-style` | `(member nil :single :double)` | Source quoting style. |
| `here-doc-literal-p` | boolean | Whether a here-document delimiter was quoted. |
| `fragments` | list of `command-fragment` | Legacy tokenizer fragments used by the current reader's expansion path. Each fragment holds text, quote style, and escaped character offsets. S-expression arguments use evaluated values; this slot remains for the default reader until WP-X01 switches the input path. |
| `source-span` | `(or null list)` | Half-open `[start,end)` character offsets, or `nil` when unavailable. |
| `glob-p` | boolean | Whether this source argument may glob-expand. Defaults to `(null quote-style)` for old constructors. |

`evaluated-command-arg`, defined in `ast-arguments.lisp` by WP-L00b, carries a runtime argument:

| Slot | Type | Meaning |
|---|---|---|
| `value` | `t` | The evaluated Lisp value. |
| `source-span` | `(or null list)` | The half-open source span that produced the value. |
| `glob-p` | boolean | Whether the source form permits glob expansion; evaluated values use `nil`. |

Each source span is a two-element list of nonnegative character offsets with `start <= end`; its end is exclusive. Existing AST span slots keep this representation. WP-L00b adds the argument type and accessors; WP-L01 records spans and source glob eligibility; WP-L02 constructs evaluated arguments; WP-L03 consumes them at the builtin and process boundaries.

`,x` contributes exactly one evaluated argument, including when `x` returns `nil` or a list. Its source span covers the complete reader-prefix form, including the comma. `,@xs` is allowed only in a direct command-island argument list and splices a proper list into separate command arguments; it does not add splicing to host-function argument lists. Each spliced argument keeps the span of the complete `,@` form. `,@nil` contributes zero arguments, and a non-list value is an error. In particular, `,nil` is one `nil` value, not zero arguments.

WP-L03 owns `builtin-binding` with slots `handler` (`function`) and
`argument-mode` (`(member :argv :value)`). The existing
`+builtin-registry-specs+` in `data/application/builtin-spec-data.lisp` remains
an alist of `(name . handler)` entries for the legacy installer. WP-L03 adds a
separate `+builtin-binding-specs+` list in the same file; its entries have the
shape `(name handler &optional argument-mode)`, where `handler` is a symbol
naming a function and the binding stores that symbol's function object. The
new binding registry is
seeded from every legacy entry as `:argv`, then the binding specs are applied
in source order and may add or replace bindings. An omitted mode defaults to
`:argv`; a `:value` mode must be declared explicitly. The `:argv` handler
signature is `(context string-args)` and returns
`(values (or string null) integer-status)`. An existing side-effecting handler
may return `nil` when it emits no stdout, preserving its legacy return shape.
`evaluated-command-args` is a position-ordered proper list of
`evaluated-command-arg` records, preserving each argument's value and source
span. The `:value` handler signature is `(context evaluated-command-args)` and
returns `(values lisp-value integer-status)`. A value-mode builtin keeps its
result as a Lisp value; it does not silently serialize that value into an argv
string. The evaluator applies the active command-failure policy to either
mode's status.

WP-L03 adds a separate `*builtin-binding-registry*` and the operations
`register-builtin(name binding)` and
`lookup-builtin-binding(name) => (values binding found-p)`, and
`dispatch-builtin(context binding evaluated-command-args) => (values result status)`
for the S-expression evaluator. Names use exact case-sensitive strings.
Until WP-X01, the existing `*builtin-registry*` remains the legacy handler
table used by the old reader and executor. `lookup-builtin` consults only that
table and continues returning the legacy handler function. The new binding
table is initialized from every
existing legacy entry as a `:argv` binding, using the same handler. The legacy
installer remains unchanged through WP-X01. `register-builtin` and
`lookup-builtin-binding` access only the new table. The new evaluator checks
that the command position is valid for the binding's mode, then calls
`dispatch-builtin`; it does not call handlers directly. The dispatcher owns
mode-specific argument preparation and handler invocation. For `:argv`, it
expands each `glob-p` source string first, preserving its source span on every
match; non-globbed arguments pass through WP-L06's `argv-scalar-string` with
their source span. It normalizes a handler's `nil` output to `""` while
preserving status. For `:value`, it passes
the evaluated argument records unchanged and keeps the returned Lisp value.
During the transition, `register-builtin` changes only the new binding table;
no new binding is mirrored into the legacy table or its specs. This keeps the
legacy registry and installer unchanged through WP-X01, so the old executor
cannot receive a `:value` binding or call one with the legacy
`(context string-args)` signature.
The new evaluator uses only `lookup-builtin-binding`. `register-builtin`
replaces a binding with the same name and returns the new binding. Lookup
returns `(values nil nil)` on a miss.

WP-L06 owns the shared `argv-scalar-string(value &key source-span)` converter
and `command-argument-type-error` condition. The converter returns one string
or signals that condition for `nil` and cons-valued data, including proper
lists and plist records. Records use keyword-key property lists, with `nil` as
the empty record; the converter does not distinguish a record from another
list at runtime. It uses the supplied argument or redirect source span for the diagnostic. This is an evaluator
error before command launch, not a synthetic process status: it does not update
`$status` or `pipestatus`, does not invoke the builtin or external command,
and is reported by the evaluator at the originating span.

For accepted values, strings pass through, characters become one-character
strings, numbers use `princ-to-string`, and non-`nil` symbols use
`symbol-name`. Keywords omit their leading colon. Rejecting `nil` keeps the
empty record collection from becoming the string `"NIL"` and preserves the
plist representation stated above. A source token spelled `nil` in an island
remains the string `"nil"`; rejection applies to the Lisp value `nil`.

This scalar conversion is used only when building argv for an external process
or a `:argv` builtin, converting a file redirect path, or producing here-string
bytes. WP-L03 owns glob expansion when building argv for external commands and
`:argv` builtins, using the public `nshell.domain.expansion:expand-glob` API
and the active filesystem.
WP-L02 preserves `glob-p` and source spans on evaluated arguments but does not
expand them. WP-L03 expands eligible source strings before scalar conversion;
expanded matches retain the originating span for diagnostics. Each non-globbed
evaluated argument contributes one string. Glob matches contribute one string
each, and a no-match pattern contributes its original string. Host-function
calls, shell-function calls, `:value` builtins, and `->` pass Lisp values
without this conversion. No conversion splits or reparses a string.

### Typed redirects and pipeline edges

WP-L00b defines `pipeline-edge` in `ast.lisp` and the redirect types and accessors in `ast-arguments.lisp`. WP-L01 creates these values; WP-L08 executes redirects and process substitutions. Positional arguments and redirect entries occupy separate `command-node` slots. A standalone process-substitution entry carries the source span of its positional argument so WP-L08 can replace that argument with the resulting path.

The existing `split-command-node-redirects` function is a legacy adapter that
extracts redirect syntax from `command-node.args`. It remains on the old input
path through WP-X01 and keeps its current behavior. The production S-expression
path reads `command-node.redirects` directly; WP-L08 must not reconstruct its
typed redirects from positional arguments. WP-L08 may add private typed-plan
helpers in `ast-redirect-split.lisp`, but must leave the existing exported
function, its result types, and its old-reader callers unchanged. New-path
helpers consume `redirect-entry` accessors and never call the legacy splitter.

`redirect-entry` has slots `kind`, `file-descriptor`, `target`, `source-span`, and `source-order`. Its types are:

- `kind`: one of `:input-file`, `:output-file`, `:append-output-file`, `:force-output-file`, `:error-file`, `:append-error-file`, `:both-output-files`, `:append-both-output-files`, `:duplicate-input-fd`, `:duplicate-output-fd`, `:here-document`, `:here-document-strip-tabs`, `:here-string`, `:process-substitution-input`, or `:process-substitution-output`.
- `file-descriptor`: `nil` or a nonnegative integer. Use `nil` for combined stdout-and-stderr file redirects and standalone process-substitution entries. For file, here-document, and here-string redirects, it is the destination descriptor: input redirects default to 0, output redirects to 1, and error redirects to 2. For descriptor duplication, it is the destination descriptor.
- `target`: the type union `(or command-arg redirect-fd-target redirect-fd-close-target redirect-heredoc-target redirect-procsub-target)`.
- `source-span`: a nullable half-open source span covering a redirect operator and target, or a full standalone process-substitution form.
- `source-order`: a zero-based nonnegative integer preserving the order of redirect and standalone process-substitution entries in the command form.

The target variants are:

| Type | Slots | Meaning |
|---|---|---|
| `redirect-fd-target` | `file-descriptor`: nonnegative integer | Source descriptor for `2>&1` or `3>&4`; the entry slot is the destination descriptor. |
| `redirect-fd-close-target` | none | Closes the destination descriptor, as in `3>&-`. |
| `redirect-heredoc-target` | `delimiter`: `command-arg`; `body`: string; `expand-p`: boolean; `strip-tabs-p`: boolean; `body-span`: nullable source span | Stores the delimiter and collected body. |
| `redirect-procsub-target` | `direction`: `(member :input :output)`; `form`: `ast-node` | Represents a process substitution form. |

File and here-string targets use `command-arg`. WP-L00b supplies `make-redirect-entry(kind file-descriptor target source-span source-order)`, `make-redirect-fd-target(file-descriptor)`, `make-redirect-fd-close-target()`, `make-redirect-heredoc-target(delimiter body expand-p strip-tabs-p body-span)`, and `make-redirect-procsub-target(direction form)`.

WP-L02 evaluates a file redirect target exactly once in the active shell value
environment. WP-L08 passes that result and the redirect span to
`argv-scalar-string` before opening the path; `nil`, lists, and records signal
`command-argument-type-error`. Redirect targets are never split, glob-expanded,
or reparsed. A process-substitution target instead uses its prepared resource
path.

WP-L08 validates process-substitution form shape and direction during a
preflight of the typed AST, before allocating substitution resources or
starting the containing command. A missing closing delimiter is an incomplete
reader/scanner result; a balanced substitution containing a sequence, a
nested substitution, a non-command form, or a direction mismatch is an
execution-plan error reported at its source span and owned by WP-L08.

WP-L08 defines `command-execution-plan-error` with `source-span`, `operation`,
and `cause` slots. `source-span` is `nil` or a half-open character-offset
pair; `operation` is one of `:preflight`, `:allocate`, `:open`, or `:start`;
`cause` is `nil` or the originating condition. It signals this condition for
invalid process-substitution plans, descriptor-path failures,
resource-allocation failures, redirect-open failures, and process-substitution
stage-start failures. WP-L02 reports the condition at its source span and
preserves `cause`; it is not a child process status or `command-failed`, and it
does not update `$status` or `pipestatus`. Failures to start ordinary command
stages use L05's normal pipeline execution result and D-06 policy.

The kinds map as follows: `<` and `0<` to `:input-file`; `>` and `1>` to `:output-file`; `>>` and `1>>` to `:append-output-file`; `>|` to `:force-output-file`; `2>` to `:error-file`; `2>>` to `:append-error-file`; `&>` to `:both-output-files`; `&>>` to `:append-both-output-files`; `<&` to `:duplicate-input-fd`; `>&` to `:duplicate-output-fd`; `<<` to `:here-document`; `<<-` to `:here-document-strip-tabs`; and `<<<` to `:here-string`. A standalone `<(form)` argument uses `:process-substitution-input`, and `>(form)` uses `:process-substitution-output`; each has a `redirect-procsub-target` with the matching direction and a span linking it to the source argument. A process substitution used as the target of `<` or `>` stays a `:input-file` or `:output-file` entry whose target is `redirect-procsub-target`. Here-document expansion follows the delimiter's `here-doc-literal-p`; `<<-` also sets `strip-tabs-p`. File, combined-file, here-document, here-string, and descriptor-duplication operators require a target; `<&` and `>&` accept an integer source descriptor or `-` to close the destination. Missing targets and missing process-substitution forms make a balanced command invalid rather than incomplete.

In a command island, adjacent `<(` or `>(` at a direct argument position
introduces process substitution; the parenthesized form is its command or
pipeline AST, not a second positional argument. The scanner emits a
`:process-substitution` token for the `<` or `>` marker and scans the following
parenthesized form normally, including its delimiter pair and nested tokens.
The reader preserves the full source spelling as one positional argument and
adds the matching standalone redirect entry. The argument and entry share the
full-form source span. With a separating space, `<` or `>` remains a redirect
operator and the following form is its target.

`body` stores the raw body text, including its line endings, without the
terminating delimiter line. `body-span` is the matching half-open character
range: it starts immediately after the delimiter line's line ending and
ends at the start of the terminator line, before any leading tabs accepted
by `<<-`. With `<<-`, leading tabs are removed from each body line for
execution; the stored body and span retain the original tabs.

`expand-p` is true exactly when the delimiter was unquoted. An unquoted
body uses the existing here-document text expansion: shell variables and
command substitutions are expanded, backslash protects `$`, backtick, and
backslash, and backslash-newline is removed. Expansion performs no word
splitting or pathname expansion. A quoted delimiter disables all body
expansion. Here-document bodies are the sole text context that retains the
existing `$(...)` command-substitution behavior; elsewhere `$(form)` is
S-expression value evaluation.

The existing behavior is implemented by
`%expand-here-doc-body-in-context` in
`src/application/execute-pipeline-expansion-here-doc.lisp`. It expands shell
variables through `expand-double-quoted` using `shell-context-environment`;
this text expansion does not look up lexical `let` bindings.

For `<<<`, WP-L02 evaluates the target once as one scalar value. WP-L08 passes
the value and its source span to `argv-scalar-string` and appends exactly one
newline before connecting it to the destination descriptor. The target is not
split or glob-expanded.

`command-node.redirects` is a list of `redirect-entry` values in source order, including standalone process-substitution entries. `command-node.force-external-p` is a boolean defaulting to `nil`. `make-command-node` keeps all existing positional arguments and appends optional `redirects` and `force-external-p` arguments. `make-pipeline-node` keeps its existing calls; when an edge list is supplied, it contains one `pipeline-edge` for each adjacent pair of commands. `nil` edges on a legacy node mean ordinary stdout-only pipes.

WP-L08 prepares process substitutions in pipeline stage order from left to
right, then by ascending `source-order` within each stage. `source-order` is
zero-based per command and is unique across that command's redirects and
standalone substitutions. This preparation finishes before pipeline
defaults are connected or ordinary redirects are applied.

A standalone substitution entry's `source-span` equals the
`source-span` of its corresponding `command-arg`; production readers must
provide both spans. WP-L02 copies that span to the matching
`evaluated-command-arg`. WP-L08 replaces that one evaluated argument with a
platform-generated path string, preserving argument order. A substitution
used as a redirect target has no positional argument and keeps its prepared
resource for the redirect application step.

WP-L05 exposes
`spawn-byte-stream-node-in-context(context ast &key stdin-fd stdout-fd)` and
`wait-byte-stream-execution(handle)`. The first accepts only a command or
pipeline AST, starts it asynchronously with the ordinary pipeline and redirect
rules, and returns an opaque execution handle after all stages start. If a
stage cannot start, it signals the originating launch condition and terminates
and reaps any stages it already started before signaling. Each
descriptor keyword is an integer file descriptor or `nil` to inherit the
shell's corresponding standard descriptor; stderr otherwise follows the
ordinary diagnostic routing. The caller retains ownership of supplied file
descriptors. The wait function reaps all stages and returns the L05
`pipeline-execution-result`, whose `status` is the final stage shell status,
`stage-statuses` is the ordered list of normalized shell statuses, and
`stage-signals` is the ordered list of raw signal numbers or `nil` for normal
exits. Neither function registers a user-visible shell job or updates the
containing command's `$status` or `pipestatus`. WP-L08 uses
this boundary for process-substitution forms, waits for their handles after
the containing foreground command or pipeline completes, and ignores their
exit statuses for the containing command.

Process substitution in a command or pipeline that is backgrounded with `&`
is rejected during preflight, before allocating resources or spawning either
the substitution or containing command. The source-located plan error names
the substitution span. This preserves the current background-execution
boundary while preventing resources from being released before an asynchronous
containing job finishes.

`<(form)` exposes a readable path whose bytes come from `form` stdout.
`>(form)` exposes a writable path whose bytes become `form` stdin. The form
must be a command or pipeline with only external-command stages; sequence ASTs
and nested process substitutions are invalid before the containing command
starts. The substitution runs through the ordinary byte-stream executor. Its
stderr remains on the diagnostic channel, and its nonzero status does not
change the containing command's status. A process substitution used with `<`
must have direction `:input`; one used with `>` must have direction `:output`.
A direction mismatch is an invalid command detected before launch.

The path comes from the platform's descriptor-path mechanism and must be
usable by child processes on both aarch64 Darwin and x86_64 Linux. The backend
may use `/dev/fd` or `/proc/self/fd` as supported by the platform. If neither
mechanism is available or resource allocation fails, WP-L08 reports a
source-located error before starting the containing command and releases any
resources already prepared.

After preparation, WP-L08 connects each pipeline's default stdin and stdout
and applies ordinary redirects left to right by `source-order`. It keeps each
process-substitution resource alive through the containing command or
pipeline, then closes its endpoints and reaps its process. On any failure after
preparation starts, including a later substitution, redirect conversion or
open, or containing-command launch, it closes all prepared endpoints and
all file descriptors opened for redirects, then terminates and reaps every
substitution process already started. If L05 cannot start a
process-substitution stage, L08 signals
`command-execution-plan-error` with that substitution's source span,
`:start`, and the launch condition as `cause`. If opening an ordinary redirect
fails, L08 signals the same condition with the redirect's source span, `:open`,
and the filesystem condition as `cause`. In either case, the containing
command is not started, prepared resources are released, and `$status` and
`pipestatus` are unchanged.

`pipeline-edge` has `kind` (`(member :pipe :pipe-stderr-to-stdout)`) and `source-span` (nullable half-open span for the operator). `(|& stage...)` is the S-expression form whose edges all use `:pipe-stderr-to-stdout`. Ordinary `(| stage...)` edges use `:pipe`. Mixed bare-line pipelines store a separate kind on each edge. No AST represents `|&` by appending `"2>&1"` to positional arguments.

Pipeline defaults connect each left stage's stdout to the next stage's stdin
before ordinary redirects are applied. Explicit redirects apply left to right
by `source-order` and override those defaults. For a
`:pipe-stderr-to-stdout` edge, WP-L08 duplicates the left stage's resulting
stdout onto stderr after its explicit redirects. Thus, if `>` redirects stdout
to a file, stderr follows that file and the next stage receives no bytes from
that stage.

The prototype still encodes bare redirects in command arguments and `|&` as a synthetic `"2>&1"` argument because its compatibility check uses the existing execution path. That encoding is confined to the prototype and its tests; it is not the production AST contract. The old reader and its redirect behavior remain on the default input path until WP-X01 passes P5 and switches to the new reader.

P5 is the cutover gate for WP-X01, not a completion gate for WP-L01. It
requires all P0/P1 use cases to pass on both operating systems, NFR-01 through
NFR-09 to be met, and no unresolved T3 findings. Until WP-X01 passes that
gate, P3/P4 implementations may build the new reader path, but no WP changes
the default reader or removes legacy-reader tests.

### Shared depth scanner

WP-L01 owns the stateless, full-buffer `scan-input` API and scanner types.
Each call scans the entire current string; no scanner state is retained.

```lisp
(scan-input source &key (cursor (length source))
                       (reader-context :auto)
                       (indent-width 2)
                       head-classifier)
  => scan-result
```

`source` is a string. `cursor` is a character offset from zero through
`(length source)`. `reader-context` is `:auto`, `:bare-line`, or `:sexp`;
`:auto` selects S-expression context when the first non-whitespace character
is `(` and bare-line context otherwise. `indent-width` is a positive
integer and defaults to 2 for direct scanner callers. WP-E03 owns the editor
setting, also defaulting to two spaces, and always passes that setting to the
scanner. In `:sexp` context, `head-classifier` is required
and has type `(function (string) (member :host-form :command-island))`. It
receives the complete source spelling of each list's first direct element for
token classification. If `cursor` is inside that head token before its
terminating delimiter or whitespace, the scanner also passes the prefix from
the token start through `cursor` for cursor-role classification. This partial
classification does not change the source tokens or scan status. The complete
head classification determines the token kind and reader context; the partial
classification determines only the cursor role at that position. If the two
classifications differ, a partial `:host-form` gives cursor role `:host-form`,
and a partial `:command-island` gives `:command-head`. When `cursor` is omitted,
the prefix ends at the end of `source`. An empty head slot maps to
`:command-head` and does not invoke the callback. The classifier returns
`:host-form` or `:command-island` using the head-resolution
rules in this note and the active shell context. WP-L02 owns
`classify-sexp-head`; it does not evaluate the form or run a command. The
scanner calls the classifier once for each complete simple non-pipeline list
head and at most once more for the cursor prefix when the cursor is inside
that head. The classifier is side-effect-free and must use non-loading
registry lookup; it does not invoke the shell-function lookup-miss hook or
autoload functions.
These calls classify heads only; they do not alter scan state. The scanner
recognizes `(| ...)` and `(|& ...)` structurally without the callback.
WP-L01's reader and WP-E03 pass the classifier for S-expression scans.

Tokens, delimiter pairs, open delimiters, status, and invalid span describe
all of `source`. `cursor` selects the positions used for `cursor-role` and
`next-indent`; indentation is computed from the prefix
`(subseq source 0 cursor)`, as if a newline were inserted there. With no
explicit cursor, both cursor-dependent results use the end of `source`.


`scan-token` has slots `kind`, `text`, `span`, and `reader-context`. `kind`
is one of `:whitespace`, `:command-head`, `:argument`, `:host-form`,
`:escaped-symbol`, `:string`, `:character-literal`, `:reader-prefix`,
`:line-comment`, `:block-comment`, `:delimiter-open`, `:delimiter-close`,
`:pipeline`, `:pipeline-stderr`, `:redirect`, `:process-substitution`,
`:here-doc-delimiter`,
`:here-doc-body`, `:sequence-separator`,
`:and`, `:or`, `:background`, `:comma-unquote`, `:dollar-unquote`, or
`:invalid`. `text` is the exact source substring. `span` is a half-open
character-offset pair. In bare-line context, `reader-context` is
`:bare-line`. In S-expression context, each list is classified from its own
head. A command form's head and direct arguments use `:command-island`; direct
tokens in a host form use `:host-form`, while each nested list is classified
from its own head. A reader prefix switches its following form and its nested
forms to `:host-form`.

`delimiter-frame` has `opener` (character), `expected-close` (character), and
`opener-span` (source span). `delimiter-pair` has `open-span` and `close-span`.
Parentheses are the only paired delimiters. `delimiter-pairs` is ordered by
opening span; `open-delimiters` contains unmatched opening parentheses in
source order, outermost first. Strings, escaped symbols, and block comments
can make a scan incomplete but do not create delimiter pairs. `scan-result`
has slots `status`, `tokens`, `open-delimiters`, `delimiter-pairs`,
`invalid-span`, `next-indent`, and `cursor-role`. `status` is `:complete`,
`:incomplete`, or `:invalid`; the token and delimiter slots are lists of their
named types; `invalid-span` is `nil` or a source span; `next-indent` is a
nonnegative integer; and `cursor-role` is `:command-head`, `:argument`,
`:redirect-target`, `:host-form`, `:comment`, or `:none`. Here-document body
tokens map to `:none`. Here-document delimiter tokens map to
`:redirect-target`; structural open and close delimiters use the enclosing
form's role and do not map to `:redirect-target` by token kind alone.
`invalid-span` is
non-`nil` exactly when status is `:invalid`; it covers the offending source
token, or is the zero-width `[length,length)` insertion point when a required
token is absent at EOF. Complete and incomplete results have no invalid span.

`cursor-role` is selected deterministically. If `cursor` is inside a
non-whitespace token's half-open span, that token owns the position:
command-head tokens map to `:command-head`; arguments, strings, and escaped
symbols map to `:argument`; redirect operators and here-document delimiter
tokens map to `:redirect-target`; a `:process-substitution` marker maps to
`:redirect-target` when it is the target of a redirect and `:argument` when it
is a standalone positional argument;
pipeline and sequence operators map to `:command-head`; host-form tokens
and reader prefixes map to `:host-form`; comments map to `:comment`. An
opening delimiter before its first direct element maps to `:command-head`
unless the enclosing list has resolved as a host form, in which case it maps
to `:host-form`. Other delimiters use the enclosing form's role. At a token
boundary, the token to the right owns the position because token spans are
half-open. Whitespace tokens are gaps and follow the rule below.

In whitespace or at end of input, the scanner uses the innermost enclosing
form and the previous significant token. A missing redirect target takes
priority and maps to `:redirect-target`. A bare-line start, an empty form
head, or a position immediately after a pipeline or sequence operator maps
to `:command-head`. A position in a direct command argument list maps to
`:argument`; one in a host form maps to `:host-form`; one inside a comment
maps to `:comment`. Outside an open form, whitespace between top-level
S-expressions maps to `:none`. At the end of a bare-line command after its
head or an argument, the role is `:argument`. A completed top-level
S-expression with no following token maps to `:none`.

Unclosed parentheses, strings, escaped symbols, nested block comments, and
here-document bodies are incomplete. At EOF, a reader prefix that still needs
an operand (`'`, backquote, `,`, `,@`, `#'`, or `$`) and a partial `#\\`
character literal are also incomplete. An unmatched close delimiter or
malformed operator order is invalid at the offending span. A trailing `;` is
complete; a trailing `&` backgrounds the preceding command and is complete.
In bare-line context, a trailing escape, `|`, `|&`, `&&`, or `||` is
incomplete. A required redirect target missing at the end of a balanced
command is invalid, matching the existing redirect contract.

For a full-buffer scan, definite invalidity takes precedence over incompleteness.
When both are present, `scan-result` reports the first definite invalid span in
source order and uses status `:invalid`; it does not request another line.
Invalid scans are not passed to `read-submission`. The REPL reports the error
and retains the buffer and cursor for correction. An `:incomplete` scan instead
inserts one physical newline at the cursor, using `next-indent`, and scans the
same `*input-state*` buffer again after the next physical line.

For `<<` and `<<-`, the scanner recognizes each direct redirect delimiter in
source order. After the command's terminating newline, it consumes one body at
a time and does not tokenize body contents as shell or Lisp syntax. A body ends
at a physical line exactly matching its delimiter; `<<-` ignores leading tabs
when matching. Multiple bodies are consumed in declaration order, each
beginning on the line after the preceding delimiter. The delimiter argument
and matching terminator use `:here-doc-delimiter`; body text uses
`:here-doc-body`. Their spans preserve the original source, and the body span
includes body line endings but excludes the terminating delimiter line. EOF
before a matching delimiter is `:incomplete` with no `invalid-span`. The
delimiter token inherits the surrounding bare-line or command-island
`reader-context`; body tokens use `:here-doc-body`. A cursor inside body text
has role `:none`, so it is not treated as a command argument or redirect target.
The same rule applies to bare-line and command-island redirects. In an
S-expression command form, the command line must end before the body begins;
the closing `)` follows the terminator line, where normal command-island
scanning resumes. Structural parentheses inside the body have no syntax.

The scanner ignores delimiter-like characters inside strings, comments, escaped symbols, and character literals. `|` is a pipeline token in bare-line syntax or in pipeline-head position; `|&` is a `:pipeline-stderr` token in bare-line operator position and as the head of `(|& stage...)`; `|name|` is one escaped-symbol token. In bare-line context, an unquoted `#` starts a line comment through the next newline. In host-form context, `;` starts a line comment and nested `#| ... |#` forms a block comment. In command-island context, `#` is argument data and does not start reader dispatch or a block comment. `#\\` character literals are recognized only in host-form context. The scanner supplies token and span decisions to delimiter pairing, highlighting, indentation, and completion. It returns `delimiter-pairs` as structural data; WP-E05 owns rendering and consumes those pairs, while WP-E03 uses scanner continuation and indentation results.

In a command-island direct argument, an unquoted `<` or `>` immediately
followed by `(` emits a `:process-substitution` marker token for that one
character. The following opening parenthesis starts the nested form and is
still included in the ordinary delimiter-pair result. A spaced `< (` or
`> (` does not form a process substitution.

In `:sexp` context, pipeline-head position means the first direct element after
an opening parenthesis. At that position, `|` and `|&` use the pipeline token
kinds with `reader-context` `:command-island`. In any other list position,
they are argument tokens with `reader-context` `:command-island`.

For G06, WP-E05 consumes `delimiter-pairs` to highlight the matching
parenthesis when the cursor is on either member of the pair; unmatched
parentheses have no match. A delimiter is under the cursor when its one-character
half-open span contains the cursor offset.

WP-E03 owns G05 vertical movement. On a multi-line buffer, Up and Down move
between adjacent physical lines; at the first or last line they leave the
cursor in place instead of switching to history. On a one-line buffer, the
existing history behavior remains. Vertical movement preserves a preferred
terminal-cell column. Count each grapheme by its rendered cell width and
advance a tab to the next 8-cell boundary. If the preferred column falls
inside a wide grapheme or tab expansion, place the cursor before it. If the
target line ends first, place the cursor at its end but keep the preferred
column for the next vertical move. A horizontal move or edit resets the
preferred column. Newline-delimited physical lines are used; terminal wrapping
does not create additional movement lines.

`next-indent` is a count of spaces to insert at `cursor`. Scanner columns count
source characters, including each tab as one column. Apply these rules in
order to the prefix before `cursor`:

1. In a here-document body, insert zero spaces so body text remains unchanged.
2. In an unclosed string, escaped symbol, or block comment, align with the
   innermost unfinished construct's opener column.
3. With an unmatched opening parenthesis, use the innermost opener. If the
   current physical line's suffix from `cursor` to its line ending begins,
   after spaces and tabs, with that opener's matching `)`, align with the
   opener. Otherwise add one `indent-width` unit to its character column. Do
   not inspect later physical lines.
4. After a bare-line continuation operator or escape, add one `indent-width`
   unit to the leading indentation of the physical line containing that
   operator. This uses the most recent continued line when input spans several
   physical lines.
5. In all other cases, insert zero spaces.

WP-E03 inserts spaces for automatic indentation. WP-C06 projects `cursor-role` into the existing completion context.
That context retains exactly five fields: command, argument-prefix,
argument-words, command-position-p, and redirection-target-p. WP-E03 consumes
continuation and indentation data; WP-E05 consumes token spans and
`delimiter-pairs`; WP-C06 consumes the cursor role.

### Shell-function registry

WP-L07 owns the global shell-function registry, its binding types, autoload hook, and user-package definition path. WP-L02 owns evaluator syntax and calls the registry API. Registry code replaces source-line reparsing with captured callables.

`shell-function-binding` has slots `callable` (`function`), `lambda-list` (list), `display-name` (string), `source-path` (nullable pathname or string), and `source-span` (nullable source span). A callable receives `(context evaluated-command-args)` and returns one Lisp value; command failures use `command-failed`. The evaluator passes the argument values to the declared lambda list while retaining their spans for diagnostics.

`shell-function-registry` has slots `global-table` (an `equal` hash table) and `lookup-miss-hook` (a function or `nil`). A `shell-function-scope` has slots `table` (an `equal` hash table) and `parent` (a nullable `shell-function-scope`). These names and accessors belong to WP-L07.

The API is:

- `register-shell-function(registry name binding &key escaped-p)` stores a binding in the global table and returns it.
- `peek-shell-function(registry name &key scope escaped-p)` checks the lexical scope chain before the global table and returns `(values binding found-p)` without running the lookup-miss hook.
- `lookup-shell-function(registry name &key scope escaped-p)` checks the lexical scope chain before the global table and returns `(values binding found-p)`; only this loading lookup may run the miss hook.
- `lookup-miss-hook`, when present, receives `(registry canonical-key)` once after a complete miss. It may autoload and register the requested function. The lookup retries the scope and global tables once after the hook; hook errors propagate.
- `define-shell-function(name lambda-list &body body)` defines a global shell function in the active shell context and records its callable, lambda list, display name, and source location.
- `with-shell-functions((name binding)...) &body body` creates a lexical scope whose bindings shadow the global table for the body.

Unescaped names use uppercase canonical keys, so `MyFn` and `myfn` refer to the same binding. Escaped names preserve exact spelling and use a separate key namespace, so `|MyFn|` does not collide with unescaped `MyFn`. Package-qualified Common Lisp symbols bypass this registry.

### Review finding closure

This ledger records the disposition of all 12 findings required for the WP-L00b
contract. Each finding is adopted as a contract gap and resolved in the named
section; the table keeps the review-to-contract mapping visible in this note.

| Finding | Contract decision | Reason |
|---|---|---|
| 1 | Value and stream positions; external and `:argv` stdout is one string in value position. | Keeps byte streams distinct from Lisp values and makes conversion explicit. |
| 2 | D-06 displays status at interactive top level, raises `command-failed` inside functions, scripts, and `-e`, and treats listed test positions as booleans. D-07 selects failure from all stages except upstream `SIGPIPE`; truth and `$status` use the final stage. | Matches the project decisions and distinguishes displayed top-level status from signalled command failure. |
| 3 | Test position applies only to direct command forms in the listed test slots. | Prevents test semantics from changing commands nested in host-function arguments. |
| 4 | Head resolution uses `NSHELL.USER`, the stated resolution order, and PATH-only `^`; bare lines never resolve host forms. | Keeps daily command names usable while preserving explicit host calls. |
| 5 | The command-island token table preserves source spelling for the listed punctuation and numeric-looking tokens. | Prevents Common Lisp reader syntax from changing command data. |
| 6 | `evaluated-command-arg`, builtin modes, splicing, and scalar argv conversion are explicit. | Preserves Lisp values until the external argv or here-string boundary and rejects lossy compound conversion. |
| 7 | `glob-p` is separate from quoting; escaped symbols and evaluated values do not glob. | Preserves literal patterns when the source explicitly quotes or escapes them. |
| 8 | Argument-position `|` and `|&` are literal; only pipeline-head syntax creates an edge. | Prevents a command argument from being reinterpreted as AST structure. |
| 9 | Redirect targets and pipeline edges use typed values and source order. | Gives execution enough information to preserve descriptor and ordering semantics without reparsing text. |
| 10 | `scan-input` is a stateless full-buffer API with typed tokens, cursor roles, and incomplete trailing operators. | Lets the REPL, editor, highlighter, and completion share one structural result. |
| 11 | The shell-function registry has explicit define, lookup, miss-hook, and escaped-name rules. | Makes scope, autoload, and name canonicalization shared behavior rather than caller-specific guesses. |
| 12 | `command-node.force-external-p` carries `^` separately from the command name. | Keeps forced PATH lookup structural and out of positional arguments. |

The separate ownership-collision proposal is also adopted: WP-L00b owns the
shared AST definitions, and each follow-on WP consumes them through
constructors and accessors.

### WP ownership and extension rules

WP-L00b owns the shared AST definitions and this contract. The table covers
P3/P4 consumers of these shared types. WP-X01 owns the later default-reader
switch and removal of the legacy reader and its tests; it starts only after the
P5 gate passes. These ownership boundaries prevent parallel WPs from
rebuilding shared structures:

| WP | Owned files | Types or definitions it may add | Extension rule |
|---|---|---|---|
| L01 | `src/domain/parsing/sexp-reader.lisp`, `src/domain/parsing/sexp-scanner.lisp`, `src/domain/parsing/sexp-reader-prototype.lisp`, matching reader/scanner tests, and `nshell.asd` entries | `reader-result`, `sexp-reader-error`, `scan-token`, `scan-result`, `delimiter-frame`, `delimiter-pair`, reader-private types | `sexp-reader.lisp` owns `read-submission`, bare-line tokenization, and construction of executable AST; `sexp-scanner.lisp` owns the editor's full-buffer structural scan and does not construct AST. Construct shared AST values through WP-L00b constructors. L01 is the only follow-on WP allowed to amend `ast.lisp` or `ast-arguments.lisp`; it must add a contract entry and accessor before consumers use a new field. |
| L02 | `src/application/sexp-evaluator.lisp`, evaluator data files, evaluator tests, and `nshell.asd` entries | Evaluator environment and private evaluation-result types; `classify-sexp-head` | Use `evaluated-command-arg`, `command-node`, registry accessors, and `reader-result.form-span-map` for macro origins. Expose the same head classifier to L01 and E03; classify via `peek-shell-function` so scanning never autoloads. Report L08's `command-execution-plan-error` at its source span. Do not evaluate forms during scanning. Ask L01 to add a shared AST field instead of redefining a node. |
| L03 | `src/application/builtin-runtime.lisp`, `data/application/builtin-spec-data.lisp`, `src/application/execute-pipeline-expansion.lisp`, `src/application/builtins.lisp`, matching tests, and its `nshell.asd` entries | `builtin-binding` and builtin dispatch types | Own `register-builtin`, `lookup-builtin-binding`, `dispatch-builtin`, and the new `+builtin-binding-specs+`. Keep legacy `+builtin-registry-specs+`, installer, and `lookup-builtin` handler semantics unchanged until WP-X01; register new bindings only in the new table. Consume AST through accessors; do not edit AST definitions. |
| L04 | New `src/application/command-failed.lisp` and failure-policy files, helper definitions in `src/presentation/repl-output-handlers.lisp`, restart-mode data and tests | `command-failed` and condition-policy types; the three special variables in `nshell.application` | Owns condition slots, policy, and `call-with-command-failure-restarts(thunk)`. Consume the pipeline result interface supplied by L05; do not change pipeline or AST structures or E03-owned submission functions. |
| L05 | `src/application/execute-pipeline-stage.lisp`, `src/application/execute-source-pipeline.lisp`, `src/application/execute-pipeline.lisp`, streaming/value executor files, matching tests | Pipeline execution-result and stream-routing types; `spawn-byte-stream-node-in-context` and `wait-byte-stream-execution` | Consume `pipeline-node.edges` and typed argument accessors. Expose per-stage status and signal metadata to L04 without changing `command-failed`. Implement the asynchronous byte-stream boundary for L08 process substitutions as specified above. |
| L06 | New `src/application/sexp-value-conversion.lisp`, matching conversion tests, and its `nshell.asd` entry | JSON, TSV, line, regex, and string conversion types; `command-argument-type-error`; `argv-scalar-string` | Own the shared scalar argv converter and its source-located type error. L03 and L08 call it at their argv and redirect boundaries; they do not duplicate conversion rules. Do not add implicit conversions to AST or stream boundaries. |
| L07 | `src/application/shell-context.lisp`, `src/application/builtin-source-reader.lisp`, `src/application/shell-function-registry.lisp`, `src/package-user.lisp`, matching tests, and `nshell.asd` entries | `shell-function-binding`, `shell-function-registry`, `shell-function-scope`, `NSHELL.USER` package and loader types | Own registry and package definitions. L02 uses their public accessors and definition API; it does not recreate the registry. |
| L08 | `src/domain/parsing/ast-redirect-split.lisp`, `src/application/execute-pipeline-redirect.lisp`, `src/application/execute-pipeline-expansion-here-doc.lisp`, `src/application/execute-pipeline-stage-background.lisp`, the `%execute-sequence-node-in-context` definition in `src/application/execute-pipeline-control.lisp`, new `src/application/execute-pipeline-process-substitution.lisp`, matching tests, and its `nshell.asd` entries | `command-execution-plan-error`; redirect execution-plan and process-substitution runtime types; bare-line `:and`, `:or`, and `:amp` sequence execution | Own bare-line logical connectors and background execution under the D-06 test-position contract. Consume `redirect-entry` and target accessors. Preserve the legacy `split-command-node-redirects` adapter and its result behavior; new-path helpers use typed redirects directly. Reject process substitution under `&` before allocation. It does not edit the core AST or pipeline-edge types. |
| E03 | `src/presentation/input-state-core.lisp`, `src/presentation/input-state-copy.lisp`, `src/presentation/input-state-dispatch-data.lisp`, `src/presentation/input-state-dispatch.lisp`, new `src/presentation/input-state-vertical-navigation.lisp`, `src/presentation/input-state-vi-edit.lisp`, `src/presentation/input-state-words.lisp`, `src/presentation/input-state-words-scan.lisp`, `%execute-command-line`, `%execute-incomplete-command`, and `%execute-parse-error` in `src/presentation/repl-output-handlers.lisp`, `t/unit/test-input-state-navigation.lisp`, `t/unit/test-input-state-navigation-properties.lisp`, `t/unit/test-input-state-vi.lisp`, continuation/indentation tests, and `nshell.asd` entries | `input-state` slot `preferred-visual-column` (`nil` or nonnegative integer); editor continuation and indentation state; G05 vertical movement | Own the preferred-column slot and its copy/reset behavior, Up/Down dispatch and movement, REPL scanner/reader dispatch, and continuation over the existing `*input-state*` buffer; do not create another submission buffer. Retain invalid input and cursor; for incomplete input, insert a newline followed by `next-indent` spaces at the current cursor and leave the cursor after those spaces. Route complete submissions through `read-submission`. Consume `scan-result`; keep the two-space default in the editor setting, pass it to `scan-input`, and provide the active `classify-sexp-head` callback for S-expression scans. Wrap each top-level result evaluation with L04's `call-with-command-failure-restarts`. |
| E05 | `src/presentation/highlight.lisp`, `src/presentation/repl-highlight.lisp`, diagnostic and highlighting tests | Highlight projection types | Consume scanner token kinds, spans, and `delimiter-pairs`; own rendering of matching delimiters and do not re-tokenize or edit scanner types. |
| C06 | `src/domain/completion/context.lisp`, `src/presentation/completion-ui-logic.lisp`, `src/presentation/completion-ui-text.lisp`, completion tests | Completion projection types only | Keep the existing five-field `completion-context`; project scanner `cursor-role` into it. |
| E06 | Suggestion, abbreviation, history-expansion, and last-argument files under `src/presentation/` and `src/domain/`, with their tests | Suggestion and history projection types | Consume scanner and AST accessors; do not add fields to scanner or completion context. |
| A01 | `packages/feature/assistant/src/domain/safety.lisp`, `packages/feature/assistant/src/domain/redaction.lisp`, assistant safety tests | Safety and redaction projection types | Consume evaluated values and source spans through accessors; preserve existing classification and redaction policy. |

Every owner may add private value types in its owned files. A WP that needs a field on a shared type must state the field, type, reader, and consumer in this note, then ask L01 for the sole AST-file amendment. Other WPs use the resulting accessor and constructor; they do not copy, subclass, or redefine the shared struct. The same rule applies to scanner and registry types: their owner adds fields and accessors before consumers depend on them.

### Prototype and migration boundary

The prototype at `src/domain/parsing/sexp-reader-prototype.lisp` remains isolated from the default input path. Existing legacy execution tests keep their expectations; new prototype tests cover the AST fields and do not replace legacy-reader tests. WP-L00b adds AST fields with defaults that preserve old constructor behavior.

The prototype tests the command and pipeline AST boundary. It records escaped-symbol glob eligibility, keeps argument-position `|` and `|&` literal, and sets `command-node.force-external-p`. It does not implement the production scanner, package resolution, command-island redirect extraction, or typed `|&` edges.

The migration order remains L01 reader/scanner, L02 evaluator, then parallel L03/L04/L06/L07, followed by L05/L08. P4 consumers can implement against the scanner and AST contracts after L01. No P3/P4 WP changes the default reader before WP-X01.

## Compatibility

Breaking changes are acceptable without a migration path. The project is at
0.6.x and in early development; the old fish syntax is discarded rather than
deprecated.

## History and abbreviation handoff

`!!` and `!$` remain pre-reader expansion on bare interactive input only.
Abbreviations expand at the input layer, and their output passes through the
shared scanner and reader. WP-E06 owns multi-line history entry, display, and
autosuggestion matching; it must settle those presentation rules before P5.
Those choices do not change the reader's one-result-per-top-level-form rule or
the source spans' offsets in the joined submission string.

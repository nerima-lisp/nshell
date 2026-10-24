# S-expression syntax redesign

Decision IDs in this note refer to section 2 of the active requirements plan
at `/private/tmp/nshell-work/plan/requirements.md`. This is a local planning
input and is not copied into the repository. The P5 acceptance scope is the
use-case catalog in section 4, the NFR targets in section 6, the evidence rules
in section 8, and the phase dependencies in section 9; the plan remains the
source of truth for the catalog and its measurement methodology.

The old reader and parser remain on the default input path until WP-X01 switches
after the [P5 reader-switch gate](#contracts-for-the-prototype-and-follow-on-work)
passes. WP-X01 then removes the old reader and its reader-specific tests. The
isolated reader prototype tests the AST boundary; it does not switch REPL input
or the source reader to S-expression input. P3 implementations may build the
new path against these contracts while the legacy path remains active; they do
not change the legacy path's behavior or make S-expressions the default.

Fish is an interaction-quality reference for editing, completion, and
responsiveness, not a syntax or compatibility target. The new surface syntax
is S-expressions, with bare command lines retained as command-entry sugar.

## The evaluation rule

An S-expression list with a non-symbol or compound head evaluates as a Common
Lisp host form. A list with a simple symbol head follows the resolution order
under [Head resolution](#head-resolution-and-user-package): a host-form match
evaluates as Common Lisp; otherwise it is a command form whose head names the
command and whose arguments use command-island rules. `,expr` and `$expr`
escape an island argument back to value evaluation.

The reader preserves user symbols without interning them into a package.
Evaluation resolves unescaped user names in the persistent `NSHELL.USER`
package, which is created during package-definition loading before WP-L01.
Bare-line input is always shell command syntax and never resolves a head as a
host-language function.

Every evaluated form has a value, stream, or test position. Value position
returns one Lisp value; stream position reads or writes bytes; test position
uses a direct command's exit status as a boolean. In every executable body,
the last form inherits the enclosing position and earlier forms are in stream
position with their values discarded. A direct command used as a conditional
test has test position. The detailed rules and examples are under
[Values, stream positions, and builtin calls](#values-stream-positions-and-builtin-calls).
At the top level, a host form uses value position. A direct command or pipeline
form uses stream position, as does a bare-line AST.

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

Each parenthesized list with a simple symbol head is classified from that
head. Thus `when` is a host form, while the nested `(test ...)` and `(cat ...)`
lists are command forms because their own heads do not resolve as host forms.
Atoms directly inside the `when` form remain host-language syntax.

An empty list `()` has no head and is the Common Lisp value `nil`, so it is
always host syntax. It produces a `reader-result` whose `form` is `nil`; it is
not a command and does not invoke head classification.

Command forms do not splice command output into source text. An external
command in value position returns stdout as one string with trailing linefeeds
removed. For example, `(set branch ,(git rev-parse --abbrev-ref HEAD))`
evaluates the nested command and passes its string result to `set`. `$` followed
by a form, such as `$(pwd)`, evaluates that form once and yields its result as a
Lisp value; it does not interpolate text into an enclosing source string.
Unquoted here-document bodies are the exception and keep their established
text-expansion behavior as specified under [Typed redirects and pipeline
edges](#typed-redirects-and-pipeline-edges).

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
tokenization helpers. Blank physical lines entered while a submission is
incomplete remain in the editable buffer and in the joined source as newline
characters. All spans are offsets into that exact source.
Each command head and its arguments become a command form;
top-level `|` groups command forms into a byte-stream pipeline, while `;`,
`&&`, `||`, and `&` form sequence nodes. The interactive experience keeps bare
command entry.

Bare-line operators use longest-match tokenization, so adjacent spellings such
as `|&`, `&&`, `||`, `&>>`, `&>`, `<<-`, and `<<<` remain single operators.
Quotes and backslash escapes suppress operator recognition while active.
Adjacent quoted and unquoted pieces concatenate into one argument. An unquoted
`#` starts a comment only at an argument boundary; `name#suffix` is data. A
trailing backslash or unterminated quote is incomplete input. Argument spans
include their source spelling, including quote and escape characters; the
command span excludes surrounding whitespace, trailing comment text, and a
terminal `;` that does not separate another item.

In bare-line input, `$x` and an entire double-quoted token such as `"$HOME"`
produce one `command-value-form` of kind `:value`. The `$` operand is read as a
single value form. This is not string interpolation: `$` inside a larger token,
inside single quotes, or beside other text remains literal. A leading
`NAME=value` word is stored in `command-node.environment-assignments` only when
a command head follows it. The prefix applies to that command only, retains its
source spelling and span, and is excluded from positional arguments. An
assignment-only line is not lifted by L01.

The first non-whitespace character selects the submission mode before history
expansion: a top-level S-expression submission must begin with `(`. A
submission that begins with an atom remains bare-line command syntax. Once `(`
selects S-expression mode, every later top-level Common Lisp datum is accepted,
including atoms, vectors, quote forms, and strings; each is evaluated in
source order. `!!` and `!$` expand only for bare interactive input. E03
captures the submission's `:bare-line` or `:sexp` mode from the raw buffer
before history expansion, then passes the same submission-mode
`reader-context` explicitly to `scan-input` and `read-submission`; an
expansion that changes the first
non-whitespace character cannot switch the submission mode. Incremental editor
scans may use `:auto`. An S-expression submission may contain multiple
top-level forms. The reader returns one
`reader-result` per form, in source order, and the REPL evaluates them in that
order. A source file uses the same mode-selection rule with `:auto` and without
interactive history expansion. A bare-line submission continues to produce
its single command or sequence AST.

For example, `'(x)` begins with a quote, so it selects bare-line mode. A quote
form is read as a host datum after an opening list has selected S-expression
mode, as in `(progn '(x))`.

WP-L01 exposes `(read-submission source &key (reader-context :auto)
source-path source-map) =>
list-of reader-result` from
`sexp-reader.lisp`. It preserves forms and source spans without resolving
command heads or receiving shell state. The REPL and source-file reader
call `scan-input` first and call `read-submission` only when the scan is
`:complete`; for S-expression scans, they pass the active WP-L02
`classify-sexp-head` closure to `scan-input` as `head-classifier`.
For source files, WP-L07 passes `:auto` to both APIs. For interactive input,
WP-E03 passes the context captured from the raw buffer to both APIs.
`read-submission` has no classifier parameter. WP-L07's
`builtin-source-reader.lisp` owns this scan-and-read dispatch for source files;
WP-E03 owns it for interactive input. Both pass each returned
`reader-result` to WP-L02's `evaluate-reader-result-in-context(context
reader-result)` in source order. The source-file reader evaluates under the
active script policy and does not install the interactive restart wrapper.
For source files, `source-path` is the script pathname or string; for REPL
input it is `nil`. A missing `source-map` means identity mapping. If history
expansion changed interactive input, E06 supplies a vector with one
`[raw-start, raw-end)` editor-buffer span per character in the expanded source;
unchanged characters map to their own one-character span, and every character
inserted by one expansion maps to the original history-expression span. E03
passes this map to L01 and uses the same map to translate scanner diagnostics.
All reader and AST spans index the exact post-expansion string passed as
`source`.

Here `reader-context` on `read-submission` and `scan-input` means the
submission-wide mode (`:auto`, `:bare-line`, or `:sexp`). The similarly named
`scan-token.reader-context` slot records the local syntax context of one token
(`:bare-line`, `:command-island`, `:host-form`, or `:here-doc-body`). The
`read-submission` option does not receive or freeze shell-context resolution;
the scanner callback classifies syntax context only. WP-L02 resolves each
source-backed command head again
during evaluation, because earlier forms may have changed the active shell
scope.
For source files, `:invalid` signals `sexp-reader-error` at
`scan-result.invalid-span`, and `:incomplete` signals it at
`scan-result.incomplete-span`. In either case, the source reader evaluates no
results from that file. These errors have no `cause` because scanning, rather
than the Common Lisp reader, found the problem.
For interactive input, an `:incomplete` scan
inserts a newline at the current
input cursor, followed by `next-indent` spaces, then places the cursor after
those spaces for the next physical line. The inserted text stays in the same
input buffer. Existing text after the cursor remains after the inserted line.
An interactive `:invalid` scan is reported at `scan-result.invalid-span` and
is not passed to the reader; the editable buffer and cursor remain unchanged.
A nonempty bare-line submission returns a list containing one `reader-result`
whose `form` is its command, pipeline, or sequence AST, whose `source` is the
complete submission string, whose `source-span` is the AST span, and whose
`form-span-map` is an empty `eq` hash table. A bare-line AST span starts at its
first owned syntax token and ends after its last owned token; it excludes
leading or trailing whitespace, trailing comment text, and a final `;` that
does not separate two AST items. Separators between sequence items remain
inside the sequence span. An S-expression submission returns
one `reader-result` per top-level form, each with the complete submission in
`source`, that form's `source-span`, its unevaluated Lisp form, and its span map.
In S-expression mode, `form` is never an AST node: the reader preserves the
parsed form for evaluation and macro expansion. Whitespace-only input returns
no results. If the reader finds invalid syntax after a complete scan, it signals
`sexp-reader-error` with a half-open `source-span` and the original condition
in `cause`; it does not convert the error to an incomplete result. The REPL
reports that error and retains the buffer and cursor for correction.
The production reader allows standard dispatch forms `#\`, `#'`, `#(`, `#A`,
`#B`, `#C`, `#O`, `#P`, `#R`, `#S`, `#X`, `#*`, `#+`, `#-`, and `#:`; nested
`#| ... |#` comments are also allowed. It rejects `#.` and shared or circular
reader labels (`#n=` and `#n#`) with `sexp-reader-error` at the dispatch span.
The reader consumes `#S` payload syntax but retains the complete spelling as
an opaque source marker; it never invokes a structure constructor. In
`reader-result.form`, the marker is a fresh uninterned symbol whose
`symbol-origins` entry stores the complete spelling in `source-name`, its
half-open `source-span`, and `opaque-dispatch-p: t`. Unknown
implementation-specific dispatch handlers are never invoked. Before evaluating
a host form, WP-L02 scans the whole form and rejects every opaque dispatch
marker with `sexp-evaluation-syntax-error` at that marker's source span. The
scan precedes macro expansion and host side effects, including evaluation of
earlier forms or selection of a conditional branch; quoted data is included.
A direct top-level command or pipeline form instead passes direct opaque
arguments through source-backed AST conversion as their original spelling.
Opaque markers in command value expressions or quoted command values are
rejected before they are evaluated or materialized. Thus a command nested in a
host form is covered by that host form's scan. A standalone `.` is also
retained as a source marker so command conversion can preserve it as an
argument; WP-L02 restores it to dotted-list syntax in host forms. A
shared object can occur at multiple source positions, but
`form-span-map` is keyed by `eq`
and stores only one origin span per object; circular forms also cannot be
represented as source-backed syntax trees. `#\` character literals remain
valid in host-form positions, and `#` remains data inside command islands.
`reader-result` also has `source-path` (nullable
pathname or string), `source-map` (nullable origin vector), and
`symbol-origins` (an `eq` hash table keyed by fresh uninterned symbol markers).
`sexp-reader-error` carries the same `source-path` and `source-map` metadata in
addition to `source-span` and `cause`. The origin map records each symbol's
exact source name, `escaped-p`, explicit package qualifier when present,
half-open source span, and applicable marker flags such as
`opaque-dispatch-p` or `opaque-dot-p`. Evaluation resolves ordinary markers
at evaluation time; reading does not intern user symbols or map `nil` to
`CL:NIL`.
The reader caps recursive datum nesting at 256 levels. A datum at level 257 is
rejected with `sexp-reader-error` on its first source character before it is
consumed.

`#+` and `#-` use the active Common Lisp feature set without evaluating source.
An included conditional form's span begins at the dispatch prefix and includes
the feature expression and payload; an excluded form produces no
`reader-result`.

For interactive S-expression input with multiple results, the REPL evaluates
each result in source order and calls L04's
`call-with-command-failure-restarts(thunk)` around each result separately. The
thunk calls WP-L02's `evaluate-reader-result-in-context(context reader-result)`
for exactly one result. L02 classifies and evaluates that result, converting
command-island forms to AST and routing reader-produced AST through L08. The
REPL starts the next result only when evaluation of the current result returns
normally; a failure that unwinds out of the wrapper stops the remaining
results. The wrapper does not treat the result list as one failure transaction.

The reader builds these as `sequence-node` values with `make-sequence-node`.
New-reader sequences contain only `command-node` or `pipeline-node` items. For
compatibility with the existing source parser, the shared constructor accepts
any `ast-node`, including its control-flow nodes. Its `separators` list stores
one separator for each item that has a following separator: normally there are
one fewer separators than items;
a terminal `:amp` is retained after the final item to encode backgrounding. A
terminal `:semi` is discarded, and `:and` or `:or` cannot terminate a sequence.
`sequence-node-command-separators` returns one
`sequence-node-command-separator` per item. Its `command` slot contains the
item, which may be any `ast-node`, and its `separator` slot contains the
following separator. The accessor name is retained for compatibility. It pads
a final foreground item with a `nil` separator and
retains a terminal `:amp` on the last item. For `a | b && c`, the first item
is a pipeline node and the second is a command node.

`make-sequence-node` enforces the `ast-node` item type, separator domain,
separator count, and terminal-separator rules above. Public AST constructors
validate every non-`nil` source span as exactly two nonnegative integer
offsets with `start <= end`; they copy the validated pair. Synthetic nodes may
use `nil`.

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

The tokenizer recognizes adjacent `|&` as one pipe operator that merges the
left stage's stderr into stdout before the next stage, matching `2>&1`.
Whitespace separates the tokens: `cmd | & next` is invalid because the pipe
has no right-hand stage; it does not mean `cmd | next &`.

The ampersand route also recognizes adjacent `&>` and `&>>` as combined-output
redirects. `cmd &> file` redirects both output streams. In `cmd & > file`, `&`
is the background separator, leaving `>` without a command, so parsing fails.

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

An ordinary keyword
literal such as `:state` remains a keyword for value operations and converts to
the symbol name `state` when used as an external argument. A record continues
to use keyword keys. Command-island package-like text such as `name:/path` is
data, not a package reference. Package qualification is parsed only in a
host-form position.

Structured records are ordinary proper property lists with keyword keys,
written as literals such as `(:state "stopped" :id 7)` or constructed with
`list`. No record-constructor API is part of this contract. The empty record is
`nil`.

An unescaped `nil` or `t` maps to `CL:NIL` or `CL:T` at evaluation time;
escaped `|nil|` and `|t|` remain ordinary user symbols. Unescaped CL names are
looked up using their uppercase CL spelling, while user-package names retain
the exact source spelling. Escaped names retain their exact spelling and
bypass CL case conversion. `escaped-p` comes from the source token: a
vertical-bar-delimited symbol is escaped; an ordinary symbol token is not.
Package-qualified names use their explicit canonical package and name. No
user symbol is interned while reading.

The prototype still uses a temporary package and rejects `#` dispatch; those
limitations do not apply to the production contract. The production reader is
not a sandbox for untrusted source.

`escaped-p` records only Common Lisp vertical-bar symbol syntax such as
`|MiXeD|`. Bare-line quote delimiters and backslash escapes are represented by
command argument fragments and do not set this symbol-origin field.

### Quote handling

In bare-line input, single quotes (`'...'`) and double quotes (`"..."`)
delimit one argument and set `command-arg.quote-style` to `:single` or
`:double`; the scanner removes those delimiters. In an S-expression,
double-quoted Common Lisp strings are string values, while apostrophe keeps
its Common Lisp quote syntax.

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

### Pathname expansion

For an external command or a `:argv` builtin, an ordinary unquoted and
unescaped command-island word is eligible for pathname expansion. WP-L03
applies brace, tilde, then glob expansion to its original source spelling when
`expand-p` is true. `:value` builtins receive the original value
without pathname expansion. String literals, escaped symbols, numeric-looking
tokens, and evaluated values are not eligible.

```lisp
(ls *.lisp)                   ; expands
(rm -rf build/*)              ; expands
(echo "*.lisp")               ; literal
```

An eligible source word remains one AST argument even when pathname expansion
produces multiple paths. This is the deliberate exception to treating every
bare symbol as a single string value.

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
Bare-line input accepts adjacent `^cmd` and stores the same force-external
flag; `^ cmd` is invalid. The marker is removed from the executable name and is
not a positional argument.
`sexp-reader-prototype-command-metadata` is a prototype-only struct with
`command-node` and `force-external-p` slots. The prototype returns it as a
second value: a list with one entry per command stage, in source order, whose
`command-node` slot references the corresponding AST node. The boolean remains
for existing prototype callers; production consumers read the AST slot.

## Errors

The rules below define nonzero command-status handling and pipeline failure
selection. A failing command updates `$status` to the final pipeline stage's
shell status and `pipestatus` with every stage's shell status in source order.

- At an interactive top-level command boundary, display the failure status and continue without signaling.
- In a function, a script, or an invocation using `-e`, signal `command-failed` for a pipeline failure selected by the pipeline rules below.
- Direct command forms in the test position of `if`, `unless`, `when`, `cond`, `and`, `or`, or `not` return a boolean from the final stage status and do not signal. This changes status conversion and failure suppression only: stdout and stderr still go to their currently bound streams, without capture or discard. `and` and `or` evaluate each operand in test position; each `cond` clause test is also in test position. A `case` selector is an ordinary value expression, not a test-position command.

Test position applies only to a command form evaluated directly as the test or operand. A host-language form keeps its Common Lisp result. Commands nested inside a host expression used as a test use value position and follow the active function, script, or `-e` failure policy.

`command-failed` is owned by WP-L04 in `nshell.application` and has these slots:

| Slot | Type | Meaning |
|---|---|---|
| `command` | string | Command name of the selected failing stage. |
| `status` | integer | Normalized shell status of the selected failing stage. |
| `stage-statuses` | list of integers | Normalized shell statuses for all stages, in source order. |
| `signal` | `(or null (integer 1 *))` | Raw signal number for the selected stage, or `nil` after a normal exit. |

The pipeline evaluator retains each stage's raw signal while selecting failures. A nonzero upstream stage terminated by `SIGPIPE` is excluded. If several other stages have nonzero statuses, select the first one in source order for `command`, `status`, and `signal`. The pipeline's ordinary `$status` remains the final stage status, even when an earlier stage supplies the condition's `status`.

L02 invokes `call-with-command-failure-policy(command-ast thunk)` once at the
command or pipeline evaluation boundary. The thunk returns
`(values value integer-status pipeline-execution-result)`. L04 applies the
failure policy and is the only owner that constructs and signals
`command-failed`. It uses the final stage status for `$status` and test-position
truth, and the source-ordered `pipeline-execution-result` to select a failure.
Direct interactive top-level commands and direct test-position commands do
not signal. This is separate from E03's `call-with-command-failure-restarts`,
which encloses each top-level result; L02's policy call handles commands and
pipelines evaluated within that result.

The REPL's continuation trampoline runs the prompt cycle around E03's
submission/resume flow and L04's nested command-failure restart loop. Each
step returns either a zero-argument continuation or the explicit `+repl-exit+`
value. `nil` and any other non-function result violate this contract: the
trampoline writes one diagnostic line to standard error and retries the initial
step. Ordinary completion returns a continuation. Ctrl-D and `exit` return
`+repl-exit+` when shutdown proceeds after any active-job warning; EOF and
SIGHUP return it directly. After cleanup, `run-repl` returns
`*last-exit-code*`.

`execute-reader-ast-in-context(context ast stage-evaluator)` returns
`(values value integer-status pipeline-execution-result)`. A standalone command
returns a one-stage result. For a pipeline, stage index `i` in the result maps
to AST stage `i`; existing callers may continue to use the first two values.

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
positions. The evaluator applies the test-position rule from [Errors](#errors)
when it evaluates `not`. Macros receive unevaluated forms, so
`(my-macro ls -la)` sees `ls` and `-la` as symbols and can expand them into a
command form.

Macro-expansion failures must not surface as reader or island-rule errors. The
expander records a source span for every reader-produced compound form and
carries the origin span onto forms generated by expansion. A macro syntax
condition is reported at the nearest user-written form whose expansion was
active; nested expansion keeps that origin chain. The diagnostic includes
source path, line, column, and half-open source offsets. WP-L02 owns
`command-macro-syntax-error` in `nshell.application`, with `source-span` (`nil`
or a half-open span), `source-path` (nullable pathname or string), and `cause`
(`nil` or a condition) slots. The expander
catches only this condition and preserves the original condition as the cause; it
must not convert arbitrary runtime errors into syntax errors. The reader
prototype does not evaluate or expand user macros.

WP-L01 owns `sexp-reader-error` in `sexp-reader.lisp`, with slots `source-span`
(`nil` or a half-open span), `source-path` (nullable pathname or string),
`source-map` (nullable origin vector), and `cause` (`nil` or a condition). It
also owns
`reader-result` with slots `form` (`t`; an AST node in bare-line mode and an
unevaluated Lisp form in S-expression mode), `source` (the complete source
string), `source-span` (the top-level form's half-open source span, including
empty list forms), `form-span-map` (an `eq` hash table), `source-path`
(nullable pathname or string), `source-map` (nullable origin vector), and
`symbol-origins` (an `eq` hash table keyed by fresh uninterned markers). Each
`symbol-origins` value records `source-name`, `escaped-p`, an explicit package
qualifier when present, and the half-open source span. `source-span`
starts at the first source character of the datum and ends after its final
token, excluding surrounding whitespace and comments. For a nonempty compound
form, it equals the root span in `form-span-map`; for `nil`, it supplies the
span because the empty list is not a map key. Each result contains one
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
generated forms, preserving nested call origins for diagnostics. The reader
does not evaluate forms or expand macros.

WP-L01 also owns
`(command-form->ast source form form-span-map head-classifier) => (or
command-node pipeline-node)`. `source` is the complete submission string;
`form` must be a nonempty source-backed list whose root has a span in
`form-span-map`. `head-classifier` has type `(function (string) (member
:host-form :command-island))` and resolves simple stage heads against the
active shell context. WP-L02 classifies an ordinary outer form first and calls
this helper only when that form is `:command-island`; the helper does not
classify that outer head a second time. For `(| ...)` and `(|& ...)`, the
operator head is syntax, not a classifier input. The helper calls
`head-classifier` once for each simple direct stage head in a pipeline or
process-substitution form, including recursively nested process-substitution
forms. A `:host-form`, computed head, or compound head in a command-only stage
position signals `sexp-reader-error` at that form's span.

The helper uses the form's span from `form-span-map` to tokenize only that
source range with command-island rules, then constructs AST nodes through the
shared constructors. The raw Lisp form supplies evaluated-value forms; the
source supplies token boundaries, literal spelling, and
process-substitution adjacency. The helper does not evaluate arguments or
expand macros. A `(| ...)` or `(|& ...)` form produces a `pipeline-node`; each
stage must be a nonempty command-island form. An empty list is always the host
value `nil`. A balanced pipeline with fewer than two stages, including `(|)`
and `(| (cat))`, is invalid reader syntax and signals `sexp-reader-error`
after the complete scan; it is not incomplete input.
Each pipeline stage must be a direct ordinary command-island list; a stage may
not itself be `(| ...)`, `(|& ...)`, or a sequence/control form. Therefore
`(| (| a b) c)` and `(|& (| a b) c)` are invalid at the nested stage. A
process-substitution form may be one command or one pipeline, but not a
sequence or control form. Nested process substitutions remain rejected by
preflight.
WP-L02 preserves host forms for Common Lisp evaluation and passes raw macro
operands to macro expansion before it classifies forms produced by that
expansion. Macro-generated command forms have no source token spans; WP-L02
converts their direct Lisp elements structurally, and a generated
process-substitution target must use the shared typed constructors. The
`head-classifier` closure supplies the active shell context to AST conversion;
WP-E03 passes the same kind of callback to `scan-input` for editor roles.

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
`src/application/execute-command-substitution.lisp` reparses command text for
legacy substitution syntax. L03 owns migrating that implementation to the new
value path; the legacy expansion call site is removed at the reader switch.
The new `$(form)` evaluation syntax is handled by the reader and evaluator, not
by reparsing command text. The replay/display
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
prototype produces existing command and pipeline nodes, existing execution
tests pass without expectation changes, and the shared contracts below are
fixed. P3 and P4 start after P2 passes. P3 implements the language core; P4
implements syntax-dependent interactive features. P5 is the reader-switch
gate. WP-X01 owns the switch and may change the default input path only after
P5 passes when every P0 and P1 use case in the acceptance catalog passes on
both Linux and macOS. The catalog covers launch and login, external-tool
invocation, command execution, interactive programs, job control, terminal
and signal handling, line editing, history, suggestions, completion,
highlighting and diagnostics, prompts, directories, variables and environment,
S-expression language behavior, configuration and extensions, robustness, AI
regressions, and distribution and operations. No use case is excluded because
its implementation belongs to another WP. P5 also requires every NFR-01
through NFR-09 target below and no unresolved independent-verification (T3)
findings. Measure timing targets on an idle Apple Silicon Darwin host and Linux
CI using the project acceptance plan's methodology; report NFR-05 using its
p99 criterion.

| NFR | P5 target |
|---|---|
| NFR-01 | Interactive startup to first prompt: ≤150 ms. |
| NFR-02 | `nshell -c true` is within 15 ms of `/bin/sh -c true`. |
| NFR-03 | 1,000 external commands complete in ≤5 s. |
| NFR-04 | Empty Enter to next prompt: ≤60 ms, including Git-managed directories; fill Git status afterward. |
| NFR-05 | Key input to redraw: p99 ≤16 ms for buffers up to 1,000 characters. |
| NFR-06 | Completion in a 20,000-entry directory: ≤100 ms; suggestions do not block key input. |
| NFR-07 | Idle RSS: ≤150 MB. |
| NFR-08 | Fixed-seed fuzzing of 100,000 reader and input-state cases produces zero debugger displays, core dumps, or hangs. |
| NFR-09 | Coverage remains ≥85% overall and ≥90% for new code. |

These contracts define the shared boundary for P3 and P4.
WP-L00b owns the AST definitions in
`src/domain/parsing/ast.lisp` and `src/domain/parsing/ast-arguments.lisp`;
follow-on work uses their constructors and accessors. No WP may redefine these
structs.

### Head resolution and user package

Common Lisp facilities remain available to user code. WP-L00b creates
persistent package `NSHELL.USER` with `COMMON-LISP` in its use list during
package-definition loading, before WP-L01's reader loads. WP-L07 owns the
shell-function registry, user-module loader, and autoload path. User code can
define ordinary `defun` and `defmacro` forms in `NSHELL.USER`. The documented
public `NSHELL` API is the stable extension surface for shell-function,
builtin, hook, and completion registration. Reader, evaluator, and execution
internals remain private.

The evaluator resolves an S-expression command head in this order:

1. A `^`-marked head bypasses Lisp functions, shell functions, and builtins and searches `PATH` only. The reader stores the marker in `command-node.force-external-p` and removes the prefix from the command name.
2. An explicitly package-qualified host symbol is evaluated as a host form. This includes symbols in `CL` and `NSHELL.USER`.
3. Common Lisp special operators and the evaluator-aware forms `if`, `when`, `unless`, `and`, `or`, `not`, `let`, `let*`, `progn`, `cond`, `case`, and `handler-case` are host forms. The evaluator applies test-position policy only to direct tests and operands listed under [Errors](#errors); body forms inherit their enclosing position under the body rule below. Other Common Lisp macros are not reserved here.
4. A package-local `NSHELL.USER` function or macro is evaluated as a host form. Common Lisp `flet` and `labels` bindings are not inputs to command-island classification.
5. A lexical shell-function binding is checked, then the global shell-function registry.
6. Builtins are checked.
7. An executable is searched for in `PATH`.
8. An inherited ordinary Common Lisp function or macro is evaluated as a host form only if no shell function, builtin, or executable matched.

This order keeps inherited names such as `find`, `sort`, `time`, `sleep`, `read`, and `print` available as everyday commands. For example, `(time make)` selects a matching shell function, builtin, or PATH executable; `CL:TIME` explicitly selects the host macro. Bare-line input always uses shell command resolution and never consults `NSHELL.USER` or the Common Lisp namespace.

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
| Numbers | An unquoted, unescaped numeric-looking island token preserves its spelling as a string and has `expand-p` true; `glob-p` is true only if that spelling contains a glob metacharacter. Thus `0755` remains the string `"0755"` and has no glob expansion. Numeric reader semantics apply in host forms; evaluated numbers have both expansion flags false and are converted only when crossing to argv. |
| `|` and `|&` | At argument position, each standalone unquoted token is a literal argument with its source spelling. It is a pipeline operator only as the head of `(| stage...)` or `(|& stage...)`. |
| `|name|` | An escaped symbol whose exact name is preserved. It is never an operator and has both `expand-p` and `glob-p` false. |
| S-expression strings | A string literal in a command island becomes one `command-arg` whose `value` is the string contents, `quote-style` is `:double`, and both expansion flags are false. |
| Ordinary unquoted tokens | Preserve the source spelling as one `command-arg`; set `expand-p` true independently of `quote-style`, including for numeric-looking tokens, and set `glob-p` only when the token contains a glob metacharacter. |
| Redirect operators | An operator must be one complete direct reader token in a command form's argument list; the following direct element is its target. Reader-token boundaries, not shell character runs inside a token, determine adjacency. A string, escaped symbol, nested form, or evaluated value whose value happens to be `>` remains positional data. Thus `(cat<input)` has the command head `cat<input`, and `(echo hi>out)` has the argument `hi>out`; neither contains a redirect. Write `(cat < input)` or `(echo hi > out)` for redirection. |
| `<(form)` and `>(form)` | At the start of a direct argument element, an unquoted `<` or `>` immediately followed by `(` begins one process-substitution argument. The marker and parenthesized command or pipeline form share one source span. A whitespace or other token boundary before the marker is required; `(cat<(producer))` is not process substitution, while `(cat <(producer))` is. As a redirect target, use separate elements such as `(cat < <(producer))`. |

The token must match a redirect operator exactly. The accepted spellings are
those in the typed redirect map below, plus a decimal destination descriptor
immediately prefixed to `<&` or `>&` (for example, `3>&`). That prefix is part
of the operator token and never consumes digits from a preceding argument.
The target is always the next direct element. In command-island syntax,
`(cmd 2>& 1)` is a descriptor duplication redirect; `(cmd 2>&1)` has one
ordinary direct element and is not a redirect. Bare-line syntax retains its
own shell tokenization rules.

An unquoted command-island source word expands when it crosses an argv boundary
to an external process or a `:argv` builtin. This covers C14 (tilde and brace
expansion) and C13 (globbing); WP-L03 owns both. WP-L01 preserves the word's
source spelling and sets `command-arg.expand-p` explicitly for each eligible
unquoted word. This flag is independent of `quote-style`: L01 sets it to `nil`
for string literals and escaped symbols, including escaped names whose
`quote-style` is `nil`. WP-L02 leaves it `nil` for evaluated values and quoted
forms.

WP-L01 sets `command-arg.glob-p` only when the preserved source spelling has
glob metacharacters. WP-L02 copies both source flags to `evaluated-command-arg`
only for a source `command-arg`. Values produced by `$x`, `,x`, `,@xs`, or
`'(...)` have both flags set to `nil`. `expand-p` authorizes brace and tilde
expansion; `glob-p` gates globbing and records source metacharacters. At
`command-argv-strings(context evaluated-command-args)`, WP-L03 leaves an
argument unchanged when `expand-p` is false. Otherwise it applies
`expand-braces`, then `expand-tilde` using the context environment, then
`expand-glob` using the context filesystem when `glob-p` is true. It applies
this order to each result from the preceding step. One
eligible argument can therefore produce multiple argv strings, but arguments
are never split into words or reparsed. A `:value` builtin receives its
original evaluated arguments without word expansion.

WP-L03 uses the public `nshell.domain.expansion:expand-braces(input)` and
`expand-tilde(input env)` APIs followed by `expand-glob(pattern &optional
filesystem)`. It does not call `expand-all`, which also performs arithmetic,
variable, and list-reference expansion, or the private
`%expand-glob-with-prefix` helper, which adds assignment-like prefix behavior.
`expand-glob` returns sorted matches, or a one-element list containing the
original pattern when there is no glob syntax or no match. The current API
suppresses directory-enumeration conditions, so such a failure is
indistinguishable from no matches and also returns the original pattern. L03
preserves this API behavior; changing it requires a separate expansion API
change.

Within a command island, `;` is a Common Lisp line comment through the next
newline, matching host-form comment syntax. A semicolon intended as command
data must be quoted or escaped. Bare-line `;` remains a sequence separator.

A quoted form at an island argument boundary produces one unevaluated Lisp
value. A simple value uses the explicit argv conversion rules; a quoted list or
record is rejected by `:argv` and must be passed to a `:value` builtin or
converted explicitly.

The shared AST stores source-ordered island arguments in
`command-node.argument-forms`, a list whose elements are either `command-arg`
or `command-value-form`. `command-value-form` has `kind` (`:value`, `:splice`,
or `:quoted`), `form` (the raw operand for `:value` and `:splice`, or the
quoted datum for `:quoted`), and nullable `source-span`. `$x` and `,x` both
produce `:value`; `,@xs` produces `:splice`; `'(...)` produces `:quoted`.
WP-L02 evaluates each `:value` or `:splice` operand exactly once and expands a
splice only when its result is a proper list. A `:quoted` datum is passed as a
value without evaluation. `command-node.args` remains the compatibility
projection containing only `command-arg` elements. Existing positional
`make-command-node` calls keep their argument order; the new optional
`environment-assignments` argument follows `argument-forms`. If
`argument-forms` is omitted, it is derived from `args`.

A `(| ...)` or `(|& ...)` form used as a value argument is stored in a
`:value` `command-value-form` with the raw source-backed pipeline form. It
remains in `argument-forms` and is not projected into `args`. WP-L02 uses the
reader result's span map to convert and evaluate that nested pipeline in value
position.

### Values, stream positions, and builtin calls

A **value position** asks for one Lisp value. It includes an unquote
expression, a host-function argument, a `let` or `let*` initializer, a
`case` selector, and every input or stage of `->`. At a top-level
boundary, a direct command, pipeline, or bare-line command is in
**stream position**. The position rule for every executable body is:
its last form inherits the enclosing form's position; each earlier body
form is in stream position and its result is discarded. This applies to
branch bodies, clauses, handler bodies, and function bodies. A direct
command form in a conditional test slot has test position. A host-form
test keeps its Common Lisp value, and commands nested inside it use
value position. Test position converts command status to a boolean and
suppresses command-failure signaling, but still sends stdout and stderr
to their currently bound streams; it neither captures nor discards
output. A `case` selector is a value expression, not a status test. In
`handler-case`, the protected form inherits the enclosing position; each
handler clause body follows the body rule, while its condition type
specifier is not an expression. Host forms and shell functions return
their Lisp value. An external command or `:argv` builtin in value
position returns stdout as one string after removing all trailing
line-feed characters (`#\Newline`); other bytes, including a carriage
return before a line feed, are preserved. Stream-position output is
unchanged. A `:value` builtin returns its Lisp value. Stderr remains on
the diagnostic channel unless a typed redirect merges it. Exit status
remains separate metadata and follows [Errors](#errors).

A **stream position** writes or consumes bytes. It includes top-level command, pipeline, and sequence items, bare-line commands, and direct command forms in an inherited stream-position body. Every stage connected by `|` or `|&` is also a stream position, including when the pipeline expression itself is in value position. A value-position pipeline captures its combined stdout as one string and removes all trailing line-feed characters; its stages still exchange bytes. Stream positions do not capture stdout as an argument. A structured value enters a byte stream only through an explicit conversion such as `to-json`. `->` passes the prior stage's Lisp value to the next stage; converting external output into structured data requires an explicit conversion such as `from-json` or `from-tsv`.

The body rule applies to these forms as follows:

| Form | Example and resulting positions |
|---|---|
| `if` | `(if (test -e branch) (git push origin branch) (echo skipped))`: the direct command test is test position; a host-form test keeps its Common Lisp value. The selected branch inherits the enclosing position. |
| `unless` and `when` | `(unless (test -e branch) (echo checking) (echo missing))`: a direct command test is test position; a host-form test keeps its Common Lisp value. The first body command streams and the last inherits the enclosing position. `when` applies the same rule. |
| `cond` | `(cond ((test -e branch) (echo present) (git push origin branch)) (t (echo skipped)))`: direct command clause tests are test position; host-form tests keep their Common Lisp values. Earlier forms in the selected clause stream, and its last form inherits the enclosing position. |
| `case` | `(case (length (git status --porcelain)) (0 (echo checking) (echo clean)) (otherwise (echo dirty)))`: the selector is value position; earlier forms in the selected clause stream, and its last form inherits the enclosing position. |
| `let*` | `(let* ((branch (git rev-parse --abbrev-ref HEAD))) (echo pushing) (git push origin $branch))`: each initializer is value position; the first body command streams and the last inherits the enclosing position. `let` applies the same body rule. |
| `progn` | `(progn (echo phase) (git rev-parse --abbrev-ref HEAD))` used as a value: `echo` streams and its result is discarded; the final command returns the value. |
| `handler-case` | `(handler-case (git push origin main) (command-failed () (echo retrying) (echo failed)))`: the protected form inherits the enclosing position; earlier handler forms stream and the last inherits it. Condition type specifiers are not expressions. |
| Shell functions and `defun` | Both `(define-shell-function publish (branch) (echo starting) (git push origin $branch))` and `(defun publish (branch) (echo starting) (git push origin $branch))` stream the first body command; the last inherits the function invocation's position. |
| Value-position `(| ...)` | `(let ((line (| (git log --oneline) (head -1)))) line)`: both stages exchange bytes; the pipeline returns combined stdout as a string with trailing line feeds removed. |

In `(let* ((branch (git rev-parse --abbrev-ref HEAD))) (git push origin $branch))`, the initializer is value position. Its stdout `main\n` becomes the string `main` after trailing LF removal, and the final body command inherits the surrounding position. At top level it streams; inside a value expression it returns its stdout as a value.
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
| `expand-p` | boolean | Whether this source argument permits brace, tilde, and glob expansion. Defaults to `nil`; WP-L01 sets it explicitly for unquoted source words, independently of `quote-style`. |

`evaluated-command-arg`, defined in `ast-arguments.lisp` by WP-L00b, carries a runtime argument:

| Slot | Type | Meaning |
|---|---|---|
| `value` | `t` | The evaluated Lisp value. |
| `source-span` | `(or null list)` | The half-open source span that produced the value. |
| `glob-p` | boolean | Whether the source form permits glob expansion; evaluated values use `nil`. |
| `expand-p` | boolean | Whether the source argument permits brace, tilde, and glob expansion; evaluated values use `nil`. |

Each source span is a two-element list of nonnegative character offsets with `start <= end`; its end is exclusive. Existing AST span slots keep this representation. WP-L00b adds the argument type and accessors; WP-L01 records spans and pathname-expansion eligibility; WP-L02 constructs evaluated arguments; WP-L03 consumes them at the builtin and process boundaries.

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
`dispatch-builtin(context binding evaluated-command-args &key argv-strings)
=> (values result status)` for the S-expression evaluator. Names use exact
case-sensitive strings.
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
uses supplied `argv-strings` or calls `command-argv-strings`; that function
expands each eligible source argument in brace, tilde, then glob order,
preserving its source span on every result, and converts remaining arguments
through WP-L06's `argv-scalar-string` with their source span. It normalizes a
handler's `nil` output to `""` while
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
WP-L03 exposes
`command-argv-strings(context evaluated-command-args) => list-of string` for
external stages and `:argv` builtins. It expands eligible source patterns and
uses WP-L06's scalar converter. `dispatch-builtin` uses this function for
`:argv` unless precomputed strings are supplied; WP-L05 uses it to prepare
external and builtin stage arguments.

An `:argv` builtin used as a pipeline stage is in stream position even when the
pipeline expression is in value position. L08 dynamically binds the stage's
standard streams from L05's `pipeline-stage-io`. A handler may read stdin and
write incremental stdout or stderr through those streams; any stdout string it
returns is written after the handler returns, following its direct stdout
writes. A standalone value-position `:argv` builtin keeps its returned stdout
as one Lisp string and does not write it to stage streams. `:value` builtins
are rejected in stream position.

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

WP-L06 also owns the user-library APIs `to-json(value)`, `from-json(text)`,
`to-tsv(rows)`, `from-tsv(text)`, `to-lines(text)`, `from-lines(lines)`,
`regex-match-p(pattern text)`,
`regex-find(pattern text &key start) => (values match start end captures)`,
`regex-replace(pattern replacement text &key all-p)`,
`split-string(text separator &key omit-empty-p)`,
`join-strings(strings separator)`, and
`replace-string(text needle replacement &key all-p)`. JSON objects are
string-keyed alists and arrays are lists. TSV uses unquoted tab-separated
string fields and LF-terminated records; fields that contain tabs or line
breaks are not representable. Line conversion normalizes CRLF, and
`from-lines` emits LF-terminated lines. String separators, search needles, and
replacement text are literal. `regex-find` uses zero-based character offsets
with an end-exclusive `end`; `captures` is an ordered list of captured strings
or `nil` for an unmatched group. Wrong argument types signal `type-error`;
malformed JSON, TSV, line, or regex input signals
`value-conversion-error(operation input cause)`. O11 uses the existing Common
Lisp arithmetic functions `+`, `-`, `*`, `/`, `mod`, `rem`, `expt`, `1+`,
`1-`, `abs`, `floor`, `ceiling`, `truncate`, and `round` in `NSHELL.USER`;
these functions need no wrappers. The pinned `cl-regex-kit` flake input already supplies the regex
library; L06 adds its `nshell.asd` dependency when implementing these regex
functions, without changing `flake.nix`.

This scalar conversion is used only when building argv for an external process
or a `:argv` builtin, converting a file redirect path, or producing here-string
bytes. WP-L03 owns brace, tilde, and glob expansion when building argv for
external commands and `:argv` builtins, using the public
`nshell.domain.expansion:expand-braces`, `expand-tilde`, and `expand-glob` APIs
with the context environment and filesystem.
WP-L02 preserves `expand-p`, `glob-p`, and source spans on evaluated arguments
originating from source `command-arg` values but does not expand them. WP-L03
expands eligible source strings before scalar conversion; expanded results
retain the originating span for diagnostics. Each argument that does not
expand contributes one string. Brace and glob results contribute one string
each; a glob no-match contributes its original pattern. Host-function
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
helpers consume `ast-redirect-entry` accessors and never call the legacy splitter.

`ast-redirect-entry` has slots `kind`, `file-descriptor`, `target`, `source-span`, and `source-order`. Its types are:

- `kind`: one of `:input-file`, `:output-file`, `:append-output-file`, `:force-output-file`, `:error-file`, `:append-error-file`, `:both-output-files`, `:append-both-output-files`, `:duplicate-input-fd`, `:duplicate-output-fd`, `:here-document`, `:here-document-strip-tabs`, `:here-string`, `:process-substitution-input`, or `:process-substitution-output`.
- `file-descriptor`: `nil` or a nonnegative integer. Use `nil` for combined stdout-and-stderr file redirects and standalone process-substitution entries. For file, here-document, and here-string redirects, it is the destination descriptor: input redirects default to 0, output redirects to 1, and error redirects to 2. For descriptor duplication, it is the destination descriptor.
- `target`: the type union `(or command-arg redirect-fd-target redirect-fd-close-target redirect-heredoc-target redirect-procsub-target)`.
- `source-span`: a nullable half-open source span covering a redirect operator and target, or a full standalone process-substitution form. Every reader-created entry has this span; `nil` is reserved for synthetic AST values without source text.
- `source-order`: a zero-based nonnegative integer preserving the order of redirect and standalone process-substitution entries in the command form.

The target variants are:

| Type | Slots | Meaning |
|---|---|---|
| `redirect-fd-target` | `file-descriptor`: nonnegative integer | Source descriptor for `2>&1` or `3>&4`; the entry slot is the destination descriptor. |
| `redirect-fd-close-target` | none | Closes the destination descriptor, as in `3>&-`. |
| `redirect-heredoc-target` | `delimiter`: `command-arg`; `body`: string; `expand-p`: boolean; `strip-tabs-p`: boolean; `body-span`: nullable source span | Stores the delimiter and collected body. |
| `redirect-procsub-target` | `direction`: `(member :input :output)`; `form`: `(or command-node pipeline-node)` | Represents a command or pipeline process-substitution form. Sequence and control-flow nodes are rejected. |

File and here-string targets use `command-arg`. WP-L00b supplies `make-ast-redirect-entry(kind file-descriptor target source-span source-order)`, `make-redirect-fd-target(file-descriptor)`, `make-redirect-fd-close-target()`, `make-redirect-heredoc-target(delimiter body expand-p strip-tabs-p body-span)`, and `make-redirect-procsub-target(direction form)`. The constructors reject incompatible redirect kinds, destination descriptors, targets, and process-substitution directions. Combined-output and standalone process-substitution entries require `file-descriptor` = `nil`; other entries require a nonnegative destination descriptor. Input-file targets accept a command argument or an `:input` process-substitution target; output-file targets accept a command argument or an `:output` process-substitution target. Other file and here-string kinds require a command argument. Descriptor-duplication kinds require an fd target or close target. Here-document kinds require a here-document target whose `strip-tabs-p` matches the kind.

WP-L02 evaluates a file redirect target exactly once in the active shell value
environment. WP-L08 passes that result and the redirect span to
`argv-scalar-string` before opening the path; `nil`, lists, and records signal
`command-argument-type-error`. Redirect targets are never split, glob-expanded,
or reparsed. If conversion signals `command-argument-type-error`, WP-L08 closes
resources already prepared and re-signals that same condition unchanged; it
does not wrap it as a `command-execution-plan-error`. A process-substitution
target instead uses its prepared resource path.

WP-L01 converts a process-substitution form to `command-node` or
`pipeline-node`. Empty, host, computed-head, or sequence forms in this
command-only position signal `sexp-reader-error` during AST conversion; they
cannot be stored in the `redirect-procsub-target.form` slot. WP-L08 checks
runtime constraints during typed-AST preflight, before allocating substitution
resources or starting the containing command: every stage must resolve as an
external command; nested process substitutions, background execution, and a
direction mismatch are execution-plan errors at the relevant source span. A
missing closing delimiter is an incomplete scanner result.

WP-L08 defines `command-execution-plan-error` in `nshell.application` with
`source-span`, `operation`, and `cause` slots. `source-span` is `nil` or a
half-open character-offset pair; `operation` is one of `:preflight`,
`:allocate`, `:open`, `:start`, or `:wait`;
`cause` is `nil` or the originating condition. It signals this condition for
invalid process-substitution plans, descriptor-path failures,
resource-allocation failures, redirect-open failures, and pipeline or
process-substitution start and wait failures. WP-L02 reports the condition at
its source span and preserves `cause`; it is not a child process status or
`command-failed`, and it does not update `$status` or `pipestatus`. A command
lookup or exec failure attributable to an ordinary stage is represented as
that stage's shell status
(`127` when no command is found, `126` when a found command cannot execute);
other stages finish, L05 returns the pipeline result, and D-06 applies. A
process-creation or descriptor-setup failure that cannot be represented as a
stage status is an infrastructure condition: L05 terminates and reaps stages
already started, then signals `byte-stream-execution-error` with operation
`:start` and the original condition as `cause`. L08 wraps it as
`command-execution-plan-error` at the containing pipeline span. A wait/reap
failure follows the same path with operation `:wait`. For a
process-substitution stage, L08 cleans prepared resources and uses the
substitution redirect span for either operation. These failures do not return
a pipeline result, update `$status` or `pipestatus`, or apply D-06.

WP-L05 owns `byte-stream-execution-error` in `nshell.application`, with
`operation` (`(member :start :wait)`) and `cause` (`condition`) slots, and
`make-byte-stream-execution-error(operation cause)`. L05 signals it only for
process creation, descriptor-setup, wait, or reap failures; ordinary command
statuses are never wrapped in it.

The kinds map as follows: `<` and `0<` to `:input-file`; `>` and `1>` to `:output-file`; `>>` and `1>>` to `:append-output-file`; `>|` to `:force-output-file`; `2>` to `:error-file`; `2>>` to `:append-error-file`; `&>` to `:both-output-files`; `&>>` to `:append-both-output-files`; `<&` to `:duplicate-input-fd`; `>&` to `:duplicate-output-fd`; `<<` to `:here-document`; `<<-` to `:here-document-strip-tabs`; and `<<<` to `:here-string`. A standalone `<(form)` argument uses `:process-substitution-input`, and `>(form)` uses `:process-substitution-output`; each has a `redirect-procsub-target` with the matching direction and a span linking it to the source argument. A process substitution used as the target of `<` or `>` stays a `:input-file` or `:output-file` entry whose target is `redirect-procsub-target`. Here-document expansion follows the delimiter's `here-doc-literal-p`; `<<-` also sets `strip-tabs-p`. File, combined-file, here-document, here-string, and descriptor-duplication operators require a target; `<&` and `>&` accept an integer source descriptor or `-` to close the destination. Missing targets and missing process-substitution forms make a balanced command invalid rather than incomplete.

In a command island, adjacent `<(` or `>(` at a direct argument position
introduces process substitution; the parenthesized form is its command or
pipeline AST, not a second positional argument. The scanner emits a
`:process-substitution` token for the `<` or `>` marker and scans the following
parenthesized form normally, including its delimiter pair and nested tokens.
The reader preserves the full source spelling as one positional argument and
adds the matching standalone redirect entry. The argument and entry share the
full-form source span.

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

`command-node.redirects` is a list of `ast-redirect-entry` values in source order, including standalone process-substitution entries. `command-node.force-external-p` is a boolean defaulting to `nil`. `command-node.environment-assignments` is a list of `command-arg` values in source order, defaulting to `nil`; it holds only the leading bare-line `NAME=value` words that precede a command head. These words retain their spelling and spans, do not appear in positional arguments, and have `expand-p` set to `nil`. `make-command-node` keeps all existing positional arguments and appends optional `redirects`, `force-external-p`, `argument-forms`, and `environment-assignments` arguments. `make-pipeline-node` keeps its existing calls; when an edge list is supplied, it contains one `pipeline-edge` for each adjacent pair of commands. `nil` edges on a legacy node mean ordinary stdout-only pipes.

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
resource for the redirect application step. For a standalone argument, L08
duplicates the prepared endpoint to an unused descriptor number not targeted
by the consuming stage's redirect map, clears close-on-exec on that descriptor,
adds it as a live destination in the stage map, and generates the path from
that number. If another mapping would occupy that number, L08 chooses another.
It keeps the parent descriptor open through an internal consuming stage; an
external child inherits the mapped descriptor through exec. Other stages close
their copies under the `transient-descriptors` rule below.

The reader-produced AST path is explicitly separate from the legacy executor.
WP-L02 sends every command, pipeline, or sequence AST obtained from a
`reader-result` to WP-L08's
`execute-reader-ast-in-context(context ast stage-evaluator)` entry point.
`stage-evaluator` has type `(function (context command-node)
evaluated-command-stage)` and is WP-L02's
`evaluate-command-stage-in-context`. L08 calls it only for command stages it
will execute, after sequence short-circuiting and process-substitution
preflight. The legacy input path continues through its existing executor and
`split-command-node-redirects` adapter until WP-X01; presence or absence of
redirects is not used to distinguish the paths.

WP-L02 owns the private `evaluated-command-stage` type with slots
`command-node`, `dispatch-kind`, `binding`, `arguments`, and
`redirect-target-values`. `dispatch-kind` is `:external`, `:builtin`, or
`:shell-function`; `binding` is a `builtin-binding` or
`shell-function-binding` for the matching internal kind and `nil` for an
external stage. `arguments` is the position-ordered list of
`evaluated-command-arg` values. `redirect-target-values` is a source-ordered
list of `(source-order . evaluated-command-arg)` pairs for file and here-string
targets. Each value retains its source span. L02 evaluates positional
arguments and those redirect targets exactly once when constructing the
record; here-document body expansion remains in L08. L08 uses the
`source-order` key to pair each target value with its `ast-redirect-entry`.
`evaluate-command-stage-in-context(context command-node)` resolves the active
command binding at execution time and returns this record. It rejects a
`:value` builtin in stream position before calling the handler.

WP-L05 owns `pipeline-stage-io` with `descriptor-map` and
`transient-descriptors` slots and
`make-pipeline-stage-io(descriptor-map transient-descriptors)`. The map is a
source-ordered list of
`(destination-fd . source-fd-or-:closed)` pairs; both descriptors are
nonnegative integers. A source descriptor names an open descriptor in the
parent process, including an inherited shell descriptor, a pipeline endpoint,
or an opened redirect resource. A destination absent from the map inherits
the same-numbered shell descriptor. WP-L05 applies the map as simultaneous
child descriptor bindings, so one destination change cannot alter the source
seen by another entry. WP-L08 creates pipeline endpoints and redirect
resources, resolves descriptor state from left to right, and builds one map
per command stage. For a duplication redirect, it snapshots the source
descriptor currently bound to the requested descriptor; a close redirect
stores `:closed`. It then applies each `:pipe-stderr-to-stdout` edge according
to the typed edge contract. This supports arbitrary destination descriptors,
including `3>&1` and `3>&-`. L08 owns these routing rules and opened
descriptors. L05 does not read redirect entries or pipeline edges on this
execution path. `transient-descriptors` is a list of unique nonnegative
descriptor numbers for the L08-created descriptors inherited from the parent
for this pipeline, including pipe and
process-substitution endpoints, here-document pipes, and opened redirect
resources. L08 supplies the same complete list for every stage. After applying
the descriptor map, L05 closes each listed descriptor in an external child
unless that descriptor number is a destination in the map. A `:closed`
destination is already closed, and every open destination retains its mapped
binding. L08 includes each standalone process-substitution path descriptor as
a live destination in its consuming stage's map, so the child close actions
preserve the descriptor named by the path. This drops inherited endpoints and
resources belonging only to other stages, so they cannot keep a pipe writer
alive and delay EOF. L05 never closes the parent-owned descriptors.

`pipeline-stage-io` also supports
`pipeline-stage-stream(descriptor &optional stage-io) => (or stream :closed)`
for internal stages; omitted `stage-io` defaults to `*pipeline-stage-io*`. It
resolves the final descriptor map for any nonnegative
descriptor; duplicated descriptors return the same stream object, and an
unmapped descriptor inherits the corresponding shell descriptor. L05 owns
this accessor and the dynamically bound `*pipeline-stage-io*`. During an
internal stage, L08 binds `*pipeline-stage-io*` and binds `*standard-input*`,
`*standard-output*`, and `*error-output*` to descriptors 0, 1, and 2. A
closed standard descriptor is represented by a stream that signals
`stream-error` when used. L08 owns the original source descriptors and lends
them to L05 through stage launch. L05 passes inherited copies to external
children, applies the stage's close actions, and owns only the duplicate
descriptors backing internal-stage streams; it closes those duplicates when
each stage finishes. After every stage has inherited or duplicated its
mappings, L08 closes the parent-side copies that no longer feed an active
writer, before waiting, so an unused pipe write end cannot delay EOF. It keeps
a standalone process-substitution path descriptor open until an internal
consumer returns, or until the external consumer has inherited it. On launch
failure, L08 closes the originals after
L05 has terminated and reaped started stages. Process-substitution process
handles and resource metadata remain with L08 until the containing execution
finishes and those processes have been reaped.

WP-L05 exposes
`spawn-byte-stream-node-in-context(context evaluated-stages stage-io
internal-stage-dispatcher)` and `wait-byte-stream-execution(handle)`.
`evaluated-stages` is the source-ordered list of
`evaluated-command-stage` records; `stage-io` has one
`pipeline-stage-io` per stage. The dispatcher has type
`(function (context evaluated-command-stage pipeline-stage-io argv-strings)
(values integer (or null integer)))` and is supplied by L08 for
internal stages. Builtins return their handler status and a `nil` signal.
Shell-function stages return status `0` and `nil` signal on a normal return; if
the callable signals `command-failed`, L08 converts its `status` and `signal`
slots to the stage result and lets the containing pipeline apply D-06 after all
stages finish. The callable's Lisp return value is discarded in a stream
position. Before starting any stage, L05 prepares argv strings for every
external and `:argv` builtin stage through L03's `command-argv-strings`. A
conversion error propagates before any stage starts, without updating shell
status. L05 launches external
stages with those strings. For `:builtin` stages, L08's dispatcher calls
L03's `dispatch-builtin` with the prepared `argv-strings` and writes its
returned stdout string to the stage's mapped stdout descriptor after the
handler returns. While a builtin runs, its dynamic standard streams refer to
the mapped stage descriptors: it may consume `*standard-input*`, write
incremental output to `*standard-output*`, and write diagnostics to
`*error-output*`. If it both writes to `*standard-output*` and returns a stdout
string, the returned string is appended after the writes. For
`:shell-function` stages, the dispatcher invokes the
binding from L07 with the evaluated arguments while the same streams and
`*pipeline-stage-io*` are bound; the function may read and write those streams
or access another descriptor with `pipeline-stage-stream`. Its return value
is not serialized into the byte stream. L05 starts the stages asynchronously
using those descriptors and returns an opaque execution handle after all
stages start. If process creation or descriptor setup fails,
it signals `byte-stream-execution-error` with operation `:start` and the
originating condition as `cause`, then terminates and reaps any stages it
already started before signaling. Command-not-found and non-executable
outcomes are stage statuses, not infrastructure conditions. WP-L08 retains
ownership of supplied descriptors and closes them during its cleanup.
The wait function reaps all stages and returns the L05
`pipeline-execution-result`, whose `status` is the final stage shell status,
`stage-statuses` is the ordered list of normalized shell statuses, and
`stage-signals` is the ordered list of raw signal numbers or `nil` for normal
exits. L05 uses the status and signal values returned by the internal-stage
dispatcher for builtin and shell-function entries. If a wait or reap
operation fails, L05 terminates and reaps every
remaining stage, closes its streams, and signals
`byte-stream-execution-error` with operation `:wait` and the originating
condition as `cause`; it never returns a partial result. Neither function
registers a user-visible shell job or updates the containing command's
`$status` or `pipestatus`.

L08 catches `byte-stream-execution-error` from either operation, cleans up
redirect and process-substitution resources, then signals
`command-execution-plan-error` with the same operation and the byte-stream
condition as `cause`. A containing pipeline uses its AST span; a
process-substitution failure uses the corresponding redirect entry's span.
No partial pipeline result is returned, shell status is not updated, and D-06
is not applied. A process-substitution stage's normal nonzero exit is reaped
but is not part of the containing pipeline result or its `pipestatus`; it
does not update `$status` or trigger D-06. An infrastructure wait/reap failure
signals the plan condition as specified above.

WP-L05 also exposes
`command-node-external-p(context command-node) => boolean` for L08 preflight.
It uses the same runtime command dispatch as stage execution and allocates no
resources or processes. It returns true when normal resolution selects the
external-command path, including a missing PATH entry that will later produce
the ordinary command-not-found status; `force-external-p` also selects that
path. WP-L08 checks every process-substitution stage with this API before
allocating resources. It uses the spawn/wait boundary for substitution forms,
waits for their handles after the containing foreground command or pipeline
completes, and ignores their exit statuses for the containing command.

Process substitution in a command or pipeline that is backgrounded with `&`
is rejected during preflight, before allocating resources or spawning either
the substitution or containing command. The source-located plan error names
the substitution span. This preserves the current background-execution
boundary while preventing resources from being released before an asynchronous
containing job finishes.

`<(form)` exposes a readable path whose bytes come from `form` stdout.
`>(form)` exposes a writable path whose bytes become `form` stdin. The form
must be a command or pipeline with only external-command stages; sequence ASTs
are rejected during L01 AST conversion, and nested process substitutions are
rejected by WP-L08 preflight before the containing command starts. The
substitution runs through the ordinary byte-stream executor. L08 recursively
applies the same typed redirect and pipeline-edge planning to the contained
command or pipeline, including here-documents and descriptor duplication;
nested process substitutions are still rejected during preflight. Its
stderr remains on the diagnostic channel, and its nonzero status does not
change the containing command's status. A process substitution used with `<`
must have direction `:input`; one used with `>` must have direction `:output`.
A direction mismatch is an invalid command detected before launch.

WP-L08 owns selection and validation of the platform's descriptor-path
mechanism. The resulting path must be usable by child processes on both
aarch64 Darwin and x86_64 Linux; the backend may use `/dev/fd` or
`/proc/self/fd` as supported by the platform. If neither mechanism is
available or resource allocation fails, WP-L08 reports a source-located error
before starting the containing command and releases any resources already
prepared.

After preparation, WP-L08 connects each pipeline's default stdin and stdout
and applies ordinary redirects left to right by `source-order`. It keeps each
process-substitution process alive through the containing command or
pipeline. Once both producer and consumer stages have inherited or duplicated
their mappings, L08 closes parent-side endpoint copies before waiting; it keeps
the process handle until the containing execution finishes and then reaps the
process. No unused parent write endpoint remains open during that wait. On any failure after
preparation starts, including a later substitution, redirect conversion or
open, or containing-command launch, it closes all prepared endpoints and
all file descriptors opened for redirects, then terminates and reaps every
substitution process already started. If L05 cannot start a
process-substitution stage, L08 signals
`command-execution-plan-error` with that substitution's source span,
`:start`, and the `byte-stream-execution-error` as `cause`; that condition
retains the original launch condition in its own `cause`. If opening an
ordinary redirect fails, L08 signals the same condition with the redirect's
source span, `:open`, and the filesystem condition as `cause`. In either case, the containing
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

The prototype still encodes bare redirects in command arguments and `|&` as a synthetic `"2>&1"` argument because its compatibility check uses the existing execution path. That encoding is confined to the prototype and its tests; it is not the production AST contract.

P5 is WP-X01's cutover gate, not a completion gate for WP-L01.

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
integer and defaults to 2 for direct scanner callers. WP-E03 owns the
editor-local constant `+editor-indent-width+` in
`src/presentation/input-state-core.lisp`, set to 2, and always passes it to
the scanner. L01's scanner tests own the `next-indent` calculation; E03's
`t/unit/test-input-state-continuation.lisp` tests insertion and cursor
placement, and `t/unit/test-repl-submission.lisp` tests REPL dispatch and
buffer retention. In `:sexp` context, `head-classifier` is required
and has type `(function (string) (member :host-form :command-island))`. It
receives the complete source spelling of each list's first direct element for
token classification. If `cursor` is inside that head token before its
terminating reader delimiter or whitespace, the scanner also passes the
prefix from the token start through `cursor` for cursor-role classification. This partial
classification does not change the source tokens or scan status. The complete
head classification determines the token kind and reader context; the partial
classification determines only the cursor role at that position. If the two
classifications differ, a partial `:host-form` gives cursor role `:host-form`,
and a partial `:command-island` gives `:command-head`. When `cursor` is omitted,
the prefix ends at the end of `source`. An open list with no first direct
element maps to `:command-head` and does not invoke the callback. A completed
empty list is the host form `nil` and does not invoke the callback. The
classifier returns `:host-form` or `:command-island` using the head-resolution
rules in this note and the active shell context. WP-L02 owns
`classify-sexp-head`; it does not evaluate the form or run a command. The
scanner calls the classifier once for each complete simple non-pipeline list
head and at most once more for the cursor prefix when the cursor is inside
that head. The classifier is side-effect-free and must use non-loading
registry lookup; it does not invoke the shell-function lookup-miss hook or
autoload functions.
These calls classify heads only; they do not alter scan state. The scanner
recognizes `(| ...)` and `(|& ...)` structurally without the callback.
WP-E03 passes the classifier to `scan-input` for S-expression editor roles.
`read-submission` does not receive or freeze shell-context resolution;
WP-L02 supplies the active classifier when evaluating a source-backed command
form.

Tokens, delimiter pairs, open delimiters, status, and invalid span describe
all of `source`. `cursor` selects the positions used for `cursor-role` and
`next-indent`; indentation is computed from the prefix
`(subseq source 0 cursor)`, as if a newline were inserted there. With no
explicit cursor, both cursor-dependent results use the end of `source`.


`scan-token` has slots `kind`, `text`, `span`, and `reader-context`.
Token `reader-context` is one of `:bare-line`, `:command-island`, `:host-form`,
or `:here-doc-body`; this per-token syntax context is distinct from the
`scan-input` submission-mode option above, which accepts `:auto`,
`:bare-line`, or `:sexp`. `kind`
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
tokens in a host form use `:host-form`. Quote, backquote, and function-quote
prefixes keep their operands in `:host-form`. The evaluated-value prefixes `,`,
`,@`, and `$` put their operands in value position without forcing host-form
dispatch. Normal head resolution decides whether a parenthesized operand is a
host form or a command form: `,(+ 1 2)` is a host form, while `,(git status)`
and `$(git status)` are command forms. A command-form operand uses
`:command-island` for its head and direct arguments. `,@` evaluates its operand
the same way before splicing a proper list.

`delimiter-frame` has `opener` (character), `expected-close` (character), and
`opener-span` (source span). `delimiter-pair` has `open-span` and `close-span`.
Parentheses are the only paired delimiters. `delimiter-pairs` is ordered by
opening span; `open-delimiters` contains unmatched opening parentheses in
source order, outermost first. Strings, escaped symbols, and block comments
can make a scan incomplete but do not create delimiter pairs. `scan-result`
has slots `status`, `tokens`, `open-delimiters`, `delimiter-pairs`,
`invalid-span`, `incomplete-span`, `next-indent`, and `cursor-role`. `status` is `:complete`,
`:incomplete`, or `:invalid`; the token and delimiter slots are lists of their
named types; `invalid-span` and `incomplete-span` are each `nil` or a source
span; `next-indent` is a
nonnegative integer; and `cursor-role` is `:command-head`, `:argument`,
`:redirect-target`, `:host-form`, `:comment`, or `:none`. Here-document body
tokens map to `:none`. Here-document delimiter tokens map to
`:redirect-target`; structural open and close delimiters use the enclosing
form's role and do not map to `:redirect-target` by token kind alone.
`invalid-span` is non-`nil` exactly when status is `:invalid`; it covers the
offending source token, or is the zero-width `[length,length)` insertion point
when a required token is absent at EOF. `incomplete-span` is non-`nil` exactly
when status is `:incomplete`, and is the zero-width `[length,length)` point
where more source is required. Complete and invalid results have no
incomplete span.

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

WP-E04 owns `apply-sexp-structural-edit(state scan-result action)`, which
returns an updated input state and output event. `action` is one of
`:forward-sexp`, `:backward-sexp`, `:delete-forward-sexp`,
`:delete-backward-sexp`, `:slurp-forward`, `:slurp-backward`, `:barf-forward`,
or `:barf-backward`. E04 consumes the L01 full-buffer scan result and does not
tokenize the buffer again. E03 owns scanner invocation and the generic input
reducer; E04 owns its named action entries and branches in the dispatch tables.

WP-E05 owns `highlight-line(input &key scan-result cursor-position
absolute-start)`. The input is one physical line; scanner spans and cursor
positions use whole-buffer character offsets, while returned highlight spans
are line-relative. With a scanner result, `highlight-line` delegates to the
internal `highlight-line-from-scanner(input scan-result cursor-position
absolute-start)` contract. `%render-edit-buffer-line` and `render-edit-buffer`
pass the scanner result, absolute cursor, and each line's absolute start. Calls
without a scanner result keep the legacy route through P5.

In `:sexp` context, pipeline-head position means the first direct element after
an opening parenthesis. At that position, `|` and `|&` use the pipeline token
kinds with `reader-context` `:command-island`. In any other list position,
they are argument tokens with `reader-context` `:command-island`.

In a command-island argument list, the scanner emits `:redirect` only when a
complete direct reader token exactly matches a spelling in the typed redirect
map. It does not split an ordinary token at `<` or `>`: `(cat<input)` has the
head token `cat<input`, and `(echo hi>out)` has the argument token `hi>out`.
The redirect target is the next direct element. A process-substitution marker
is the exception: `<(` or `>(` is recognized at the start of a direct argument
element, with no separator between the marker and its nested form.

WP-E05 consumes `delimiter-pairs` to highlight the matching parenthesis when
the cursor is on either member of the pair; unmatched parentheses have no
match. A delimiter is under the cursor when its one-character half-open span
contains the cursor offset.

WP-E03 owns vertical movement. On a multi-line buffer, Up and Down move
between adjacent physical lines; at the first or last line they leave the
cursor in place instead of switching to history. On a one-line buffer, the
existing history behavior remains. Vertical movement preserves a preferred
terminal-cell column. Use `cl-tty-kit:string-graphemes` and the existing
presentation helper `%grapheme-visible-width` from
`src/presentation/prompt-display.lisp` to measure each grapheme; this helper
accounts for the project's VS16 and regional-indicator width correction. A
tab advances to the next 8-cell boundary. If the preferred column falls
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

WP-C06 maps scanner cursor roles into the existing completion-context fields
`command`, `argument-prefix`, `argument-words`, `command-position-p`, and
`redirection-target-p` as follows:

| `cursor-role` | `command` | `argument-prefix` and `argument-words` | `command-position-p` | `redirection-target-p` |
|---|---|---|---|---|
| `:command-head` | The command prefix through the cursor | Empty string and empty list | `t` | `nil` |
| `:argument` | The command in the current command segment | Prefix analysis supplies the argument prefix and words; an unfinished command prefix leaves them empty | `t` when prefix analysis still identifies the command prefix; otherwise `nil` | `nil`, unless prefix analysis identifies a redirection target |
| `:redirect-target` | The command in the current command segment | The target prefix through the cursor, included in `argument-words` | `nil` | `t` |
| `:host-form`, `:comment`, `:none` | Empty string | Empty string and empty list | `nil` | `nil` |

At the end of a bare command line, the scanner can report `:argument` after its
command head. Prefix analysis keeps `command-position-p` true while that word is
still the unfinished command prefix, so command candidates remain available.

When the cursor is inside a redirection-target token, the scanner reports
`:argument`; C06 preserves the target flag from the completion-prefix analysis.
At the gap after a redirection operator, the scanner reports
`:redirect-target` directly.

The projection uses the scanner's cursor from the current buffer. Prefix fields
stop at that cursor even when the token continues to its right. Candidate
replacement still uses the full token span: the candidate replaces the whole
token, including text to the right of the cursor, while text after the token
remains in the buffer. Host forms, comments, and completed top-level forms do
not produce completion candidates.

For `:argument` and `:redirect-target`, `argument-words` contains the parsed
argument values in the current command segment, in source order. It excludes
the command head and operators. When a token is under the cursor, only its
prefix through the cursor is included; when the cursor is after whitespace,
only preceding arguments are included and `argument-prefix` is empty. These
values come from the existing completion tokenizer, not from raw source
slices.

The scanner-backed APIs are
`completion-context-for-scan(scan-result cursor) => completion-context` and
`complete-in-context(kb partial-input context &key path filesystem alias-table
function-table variable-names directory home-directory) => candidates`.
`completion-context-for(partial-input)` and the legacy `complete` route remain
available for callers that still use them. The REPL completion path scans with
`:reader-context :auto` and uses the scanner-backed APIs for both bare-line and
S-expression input.

Until WP-L02 implements `classify-sexp-head`, the completion caller catches
only that interface's L02 unimplemented-contract condition. Its local fallback
recognizes package-qualified heads, Common Lisp operators, and bound user
operators as host forms; registered shell functions and other heads remain
command islands. The fallback is limited to completion and does not evaluate
the form. Other conditions propagate unchanged. Remove this fallback when the
L02 classifier is available.

For scanner-backed filesystem completion, `$VAR/` and `${VAR}/` prefixes are
expanded only while listing directories; returned candidates retain the
typed variable prefix. A `cd` query with no path separator also searches each
non-empty `CDPATH` entry and returns its explicit path in the candidate, so
inserting it does not depend on runtime `CDPATH` behavior.

### Shell-function registry

WP-L07 owns the global shell-function registry, its binding types, autoload
hook, and module loading into the existing `NSHELL.USER` package. WP-L00b owns
package creation. WP-L02 owns evaluator syntax and calls the registry API.
Registry code replaces source-line reparsing with captured callables.

`shell-function-binding` has slots `callable` (`function`), `lambda-list` (list), `display-name` (string), `source-path` (nullable pathname or string), and `source-span` (nullable source span). A callable receives `(context evaluated-command-args call-position)`, where `call-position` is `:value` or `:stream`, and returns one Lisp value; command failures use `command-failed`. The evaluator passes the argument values to the declared lambda list while retaining their spans for diagnostics. Earlier function body forms execute in stream position; the final form inherits the call position. In a stream stage, a normal callable return maps to status `0` and no signal; a `command-failed` condition maps to its `status` and `signal` slots, while its value is not serialized. L08 returns those stage results to L05, which completes the pipeline before L04 applies D-06.

`shell-function-registry` has slots `global-table` (an `equal` hash table) and `lookup-miss-hook` (a function or `nil`). A `shell-function-scope` has slots `table` (an `equal` hash table) and `parent` (a nullable `shell-function-scope`). These names and accessors belong to WP-L07.

WP-L07 exposes `context-shell-function-registry(context) =>
shell-function-registry` and
`active-shell-function-scope() => (or null shell-function-scope)` for L02.
The existing test-position dynamic variable remains independent of
`call-position`. L07 adds the registry slot to `shell-context`; the legacy
function and source tables remain unchanged through P5 and do not mirror the
new registry.

The API is:

- `register-shell-function(registry name binding &key escaped-p)` stores a binding in the global table and returns it.
- `peek-shell-function(registry name &key scope escaped-p)` checks the lexical scope chain before the global table and returns `(values binding found-p)` without running the lookup-miss hook.
- `lookup-shell-function(registry name &key scope escaped-p)` checks the lexical scope chain before the global table and returns `(values binding found-p)`; only this loading lookup may run the miss hook.
- `lookup-miss-hook`, when present, receives `(registry canonical-key)` once after a complete miss. It may autoload and register the requested function. The lookup retries the scope and global tables once after the hook; hook errors propagate.
- `define-shell-function(name lambda-list &body body)` defines a global shell function in the active shell context and records its callable, lambda list, display name, and source location.
- `with-shell-functions((name binding)...) &body body` creates a lexical scope whose bindings shadow the global table for the body.

Unescaped names use uppercase canonical keys, so `MyFn` and `myfn` refer to the same binding. Escaped names preserve exact spelling and use a separate key namespace, so `|MyFn|` does not collide with unescaped `MyFn`. Package-qualified Common Lisp symbols bypass this registry.

### Cross-WP interface skeletons

WP-L00b supplies compileable skeletons in owner-specific files for L02-L08, E04-E06, and C06, plus the shared condition and signal helper in `src/application/contracts/wp-interface-errors.lisp`. Each L00b-owned stub signals `wp-interface-not-implemented(owner-wp interface)` with its owner and interface names. A contract file holds only its owner's declarations and initial stub. The owner may replace the stub there or move the definition to an implementation file in its ownership row, removing the stub in the same change. Each owner appends only its own source entries to `nshell.asd` at the positions required by the serial load order; do not edit another owner's entries.
L01 owns `read-submission`, `scan-input`, `command-form->ast`, and their reader/scanner types. L01 places its own declarations and skeletons in its first commit. L00b does not create or edit L01-owned files. The condition accessors are `wp-interface-not-implemented-owner-wp` and
`wp-interface-not-implemented-interface`.

| Boundary | Skeleton signature and result | Owner / contract file |
|---|---|---|
| L01 reader/scanner APIs | `read-submission(source &key (reader-context :auto) source-path source-map) => list-of reader-result`; `scan-input(source &key cursor reader-context indent-width head-classifier) => scan-result`; `command-form->ast(source form form-span-map head-classifier) => (or command-node pipeline-node)`. L01-owned types include `reader-result`, `sexp-reader-error`, `scan-result`, `scan-token`, `delimiter-frame`, and `delimiter-pair`. | L01 adds its own API/type skeletons in its first commit. Consumers are E03, L02, L07, E05, C06, and E06; no other WP edits L01-owned files. |
| L02 to L03 | `register-builtin(name binding) => binding`; `lookup-builtin-binding(name) => (values binding found-p)`; `dispatch-builtin(context binding evaluated-command-args &key argv-strings) => (values result integer-status)`; `command-argv-strings(context evaluated-command-args) => list-of string`. `builtin-binding(handler argument-mode)` uses `:argv` or `:value`. | L03; `src/application/contracts/l03-builtin.lisp`. |
| L02 to L04 | `command-failed(command status stage-statuses signal)`. Dynamic variables: `*interactive-top-level-p*`, `*command-test-position-p*`, and `*errexit-p*`, all boolean. `call-with-command-failure-restarts(thunk)` returns all values from the thunk. | L04; `src/application/contracts/l04-command-failure.lisp` and `src/presentation/contracts/l04-command-failure.lisp`. |
| L02 to L07 | `peek-shell-function(registry name &key scope escaped-p) => (values binding found-p)`; `lookup-shell-function(registry name &key scope escaped-p) => (values binding found-p)`; `register-shell-function(registry name binding &key escaped-p) => binding`; `define-shell-function(name lambda-list &body body)`; `with-shell-functions((name binding)...) &body body`. Binding, registry, and scope slots are fixed. | L07; `src/application/contracts/l07-shell-functions.lisp`. L00b creates `NSHELL.USER` before L01 loads. |
| L02 to L08 | `evaluate-command-stage-in-context(context command-node) => evaluated-command-stage`; `execute-reader-ast-in-context(context ast stage-evaluator) => (values value integer-status pipeline-execution-result)`. The callback is `(function (context command-node) evaluated-command-stage)`. | L02 in `src/application/contracts/l02-evaluator.lisp`; L08 in `src/application/contracts/l08-reader-execution.lisp`. |
| E03 to L02/L04 | `classify-sexp-head(context head-source) => :host-form or :command-island`; `evaluate-reader-result-in-context(context reader-result) => (values value integer-status)`; `call-with-command-failure-restarts(thunk)` returns all values from the thunk. | L02 in `src/application/contracts/l02-evaluator.lisp`; L04 in `src/presentation/contracts/l04-command-failure.lisp`. E03 calls the wrapper once per top-level result. |
| C06 to L02 | `scan-input(source &key cursor reader-context indent-width head-classifier) => scan-result`; in `:sexp`, the callback is L02 side-effect-free `classify-sexp-head`. | L01 adds the scanner skeleton in its first commit; L02 supplies classification in `src/application/contracts/l02-evaluator.lisp`; C06 projects `cursor-role`. |
| L03/L08 to L06 | `argv-scalar-string(value &key source-span) => string`, or signals `command-argument-type-error(value source-span)`. | L06; `src/application/contracts/l06-value-conversion.lisp`. |
| L04 to L05 | `pipeline-execution-result(status stage-statuses stage-signals)`. Stage status and signal lists are source ordered; signal entries are positive integers or `nil`. | L05; `src/application/contracts/l05-pipeline.lisp`. |
| L05 to L08 and L08 to L05 | `pipeline-stage-io(descriptor-map transient-descriptors)`; `spawn-byte-stream-node-in-context(context evaluated-stages stage-io internal-stage-dispatcher) => opaque pipeline-execution-handle`; `wait-byte-stream-execution(handle) => pipeline-execution-result`; `pipeline-stage-stream(descriptor &optional stage-io) => (or stream :closed)`; `command-node-external-p(context command-node) => boolean`. The dispatcher signature is `(function (context evaluated-command-stage pipeline-stage-io argv-strings) (values integer-status nullable-signal))`. | L05 in `src/application/contracts/l05-pipeline.lisp`; L08 in `src/application/contracts/l08-reader-execution.lisp`. |
| E06 to E03/L01 diagnostics | `expand-history-input(raw-source) => (values expanded-source source-map)`; `source-span-to-origin-span(source-map expanded-span) => raw-editor-span`. `source-map` is a vector mapping each expanded character to one raw editor `[start,end)` span. | E06; `src/presentation/contracts/e06-history-expansion.lisp`. E03 passes the map to L01 and translates scanner diagnostics; L01 stores it in each reader result/error. |
| L02 to L04 failure policy | `call-with-command-failure-policy(command-ast thunk) => (values value integer-status)`. The thunk returns `(values value integer-status pipeline-execution-result)`; L04 alone constructs and signals `command-failed`. | L04; `src/application/contracts/l04-command-failure.lisp`. L02 owns the single evaluator call boundary. |
| L02 to L07 shell-function context | `context-shell-function-registry(context) => shell-function-registry`; `active-shell-function-scope() => (or null shell-function-scope)`; callables receive `(context evaluated-command-args call-position)`. | L07; `src/application/contracts/l07-shell-functions.lisp`. L02 supplies `:value` or `:stream`, independently of test position. |
| L06 user-library conversions | O09: JSON, TSV, and line converters; O10: regex and literal string helpers; O11: existing Common Lisp arithmetic functions, without wrappers. Exact signatures and representations are defined above. | L06; `src/application/contracts/l06-value-conversion.lisp`; public functions are in `NSHELL.USER`. |
| E03 to E04 structural editing | `apply-sexp-structural-edit(state scan-result action) => (updated-state output-event)` for the eight structural actions defined above. | E04; `src/presentation/contracts/e04-structural-editing.lisp`. E03 owns scanner invocation and the generic reducer; E04 owns its action-specific dispatch entries and branches. |
| E05 scanner-backed highlighting | `highlight-line(input &key scan-result cursor-position absolute-start)`; scanner offsets are whole-buffer offsets and output spans are line-relative. | E05; `src/presentation/contracts/e05-highlighting.lisp`, `src/presentation/highlight.lisp`, and renderer functions in `src/presentation/repl-rendering.lisp`. |
| C06 scanner-backed completion | `completion-context-for-scan(scan-result cursor) => completion-context`; `complete-in-context(kb partial-input context &key path filesystem alias-table function-table variable-names directory home-directory) => candidates`. | C06; `src/presentation/contracts/c06-completion-context.lisp`; `%refresh-completion-session-state` is the presentation caller. |

The condition slots are fixed here: `command-failed` has `command` (string),
`status` (integer), `stage-statuses` (integer list), and `signal` (positive
integer or `nil`); `command-execution-plan-error` has `source-span`, `operation`,
and `cause`; `byte-stream-execution-error` has `operation` (`:start` or
`:wait`) and `cause`; `command-argument-type-error` has `value` and
`source-span`; `value-conversion-error` has `operation`, `input`, and `cause`;
`command-macro-syntax-error` has `source-span`, `source-path`, and `cause`.
`wp-interface-not-implemented` has `owner-wp` and `interface`.
`evaluate-reader-result-in-context` returns the Lisp result followed by the
final integer shell status. `execute-reader-ast-in-context` returns those two
values followed by `pipeline-execution-result`. They update the active shell
context's `$status` and `pipestatus`; ordinary host forms preserve the current
shell status.

R02 owns posix_spawn infrastructure and must land before L05 changes pipeline
spawning. L05 and L08 may implement their reciprocal callback boundary in
parallel without changing the signatures above.

### WP ownership and extension rules

WP-L00b owns the shared AST definitions and this contract. The table covers
P3/P4 consumers of these shared types. WP-X01 owns the later default-reader
switch and removal of the legacy reader and its tests; it starts only after the
P5 gate passes. These ownership boundaries prevent parallel WPs from
rebuilding shared structures:

| WP | Owned files | Types or definitions it may add | Extension rule |
|---|---|---|---|
| R02 | WP-R02-owned `posix_spawn` infrastructure files and tests; that WP selects their exact paths | The NFR-03 process-spawn implementation (1,000 external commands in ≤5 s) | Land the `posix_spawn` layer before L05 changes pipeline spawning. |
| L00b | `src/domain/parsing/ast.lisp`, `src/domain/parsing/ast-arguments.lisp`, `t/unit/test-sexp-ast-contracts.lisp`, `src/package-user.lisp`, AST exports in `src/package-domain.lisp`, nshell.asd entries for L00b-owned files, and package exports for L00b-owned symbols | Shared AST types, `NSHELL.USER` package creation, and the common interface condition/helper | L00b fixes shared type names, constructor validation, and AST accessors/tests. It creates `NSHELL.USER` during package-definition loading before L01. L00b owns only `src/application/contracts/wp-interface-errors.lisp` among interface skeleton files; each other interface file belongs to the WP in its name. |
| L01 | `src/domain/parsing/sexp-reader.lisp`, `src/domain/parsing/sexp-scanner.lisp`, `src/domain/parsing/sexp-reader-prototype.lisp`, shared AST changes in `src/domain/parsing/ast.lisp` and `src/domain/parsing/ast-arguments.lisp`, the AST export in `src/package-domain.lisp`, matching reader/scanner and shared-AST tests, and `nshell.asd` entries | `reader-result` (`form`, `source`, `source-span`, `form-span-map`, `source-path`, `source-map`, `symbol-origins`), `sexp-reader-error` (`source-span`, `source-path`, `source-map`, `cause`), `scan-token`, `scan-result`, `delimiter-frame`, `delimiter-pair`, reader-private types; `command-form->ast`; `command-node.environment-assignments` | `sexp-reader.lisp` owns context-free `read-submission`, bare-line tokenization and spans, and source-backed AST construction. L01 places the reader/scanner API and type skeletons in its first commit. It preserves each unquoted island word spelling and explicitly sets `command-arg.expand-p`; it does not infer eligibility from quote-style. The caller supplies active `head-classifier`; the helper does not reclassify the already-classified outer command, evaluate arguments, or expand macros. Pipeline and process-substitution stages must be command-island forms. The scanner owns the editor full-buffer structural scan, `next-indent` calculation, and matching scanner tests; it does not construct AST. Construct shared AST values through WP-L00b accessors and constructors. L01 is the only follow-on WP allowed to amend shared AST files; it must first document any new field and accessor, including the bare-line assignment prefix. |
| L02 | `src/application/sexp-evaluator.lisp`, `src/application/contracts/l02-evaluator.lisp`, evaluator data files, evaluator tests, and `nshell.asd` entries | `evaluated-command-stage`; `evaluate-reader-result-in-context`; `evaluate-command-stage-in-context`; `classify-sexp-head`; `command-macro-syntax-error` and `sexp-evaluation-syntax-error` in `nshell.application` | Use `evaluated-command-arg`, registry accessors, and `reader-result.form-span-map` for macro origins; copy both `expand-p` and `glob-p` only from source `command-arg` values, leaving evaluated values ineligible. Pass `reader-result.source` to source-backed AST conversion. Expose the side-effect-free classifier to L01 and E03; classify via `peek-shell-function` so scanning never autoloads, and resolve again at evaluation time after earlier forms may have changed the active shell scope. Evaluate stage arguments and redirect values once, then pass a stage-evaluator closure to L08's `execute-reader-ast-in-context`; report its plan errors at their source spans. Do not evaluate forms during scanning. |
| L03 | `src/application/contracts/l03-builtin.lisp`, `src/application/builtin-runtime.lisp`, `data/application/builtin-spec-data.lisp`, `src/application/execute-pipeline-expansion.lisp`, `src/application/execute-command-substitution.lisp`, `src/application/builtins.lisp`, matching tests, and `nshell.asd` entries | `builtin-binding` and builtin dispatch types; `command-argv-strings`; C13 globbing and C14 tilde/brace expansion | Own `register-builtin`, `lookup-builtin-binding`, `dispatch-builtin`, and `command-argv-strings`. At argv conversion, expand only marked source arguments in brace, tilde, glob order using `expand-p` and `glob-p`; evaluated values and `:value` builtin arguments do not expand. Own C13 and C14. Keep legacy `+builtin-registry-specs+`, installer, and `lookup-builtin` handler semantics unchanged until WP-X01; register new bindings only in the new table. Own the command-substitution implementation while it is migrated to the new value path. Consume AST through accessors; do not edit AST definitions. |
| L04 | `src/application/contracts/l04-command-failure.lisp`, `src/application/command-failed.lisp` and failure-policy files, `src/presentation/contracts/l04-command-failure.lisp`, `src/presentation/repl-output-handlers.lisp` restart wrapper, restart-mode data and tests | `command-failed` and condition-policy types; the three special variables in `nshell.application` | Owns condition slots, policy, and `call-with-command-failure-restarts(thunk)`. The application and presentation contract files hold the initial skeletons; the presentation implementation may live in `repl-output-handlers.lisp`. Consume the pipeline result interface supplied by L05; do not change pipeline or AST structures or E03-owned submission functions. |
| L05 | `src/application/contracts/l05-pipeline.lisp`, `src/application/execute-pipeline-stage.lisp`, `src/application/execute-source-pipeline.lisp`, `src/application/execute-pipeline.lisp`, `src/infrastructure/acl/syscall-pipeline*.lisp`, streaming/value executor files, matching tests | `pipeline-execution-result`, `pipeline-stage-io`, `byte-stream-execution-error`; `pipeline-stage-stream`, `*pipeline-stage-io*`, `spawn-byte-stream-node-in-context`, `wait-byte-stream-execution`, `command-node-external-p` | R02 lands the posix_spawn infrastructure before L05 changes pipeline spawning. Consume `evaluated-command-stage` and per-stage descriptor maps. Expose per-stage status and signal metadata to L04 without changing `command-failed`. Start external stages, provide mapped streams for internal stages, and invoke L08's dispatcher for builtin and shell-function stages; do not interpret redirect entries or pipeline edges on this path. Define `byte-stream-execution-error(operation cause)` for infrastructure start/wait failures; cleanup all started stages and never return a partial result. The external-path predicate uses the same runtime dispatch as stage launch and performs no allocation or process start. |
| L06 | New `src/application/sexp-value-conversion.lisp`, `src/application/contracts/l06-value-conversion.lisp`, matching conversion tests, and its `nshell.asd` entry | JSON, TSV, line, regex, and string conversion types; `command-argument-type-error`; `argv-scalar-string` | Own the shared scalar argv converter and its source-located type error. L03 and L08 call it at their argv and redirect boundaries; they do not duplicate conversion rules. Do not add implicit conversions to AST or stream boundaries. |
| L07 | `src/application/contracts/l07-shell-functions.lisp`, `src/application/shell-context.lisp`, `src/application/builtin-source-reader.lisp`, `src/application/shell-function-registry.lisp`, matching tests, and `nshell.asd` entries | `shell-function-binding`, `shell-function-registry`, `shell-function-scope`, loader types, `define-shell-function`, `with-shell-functions` | Own the registry, module loader, and autoload path. `NSHELL.USER` package creation belongs to L00b and is already available before L01 loads. `builtin-source-reader.lisp` scans source text before `read-submission`, supplies L02's active classifier to `scan-input`, passes `:auto` to both `scan-input` and `read-submission`, and sends complete reader results to L02 for sequential evaluation under the active script policy. L02 uses the registry accessors and definition API; it does not recreate the registry. |
| L08 | `src/application/contracts/l08-reader-execution.lisp`, `src/domain/parsing/ast-redirect-split.lisp`, `src/application/execute-pipeline-control.lisp` (`%execute-reader-sequence-node-in-context` only), `src/application/execute-pipeline-redirect.lisp`, `src/application/execute-pipeline-expansion-here-doc.lisp`, `src/application/execute-pipeline-stage-background.lisp`, new `src/application/execute-pipeline-process-substitution.lisp`, `src/infrastructure/acl/syscall-process-substitution.lisp`, matching tests, and its `nshell.asd` entries | `command-execution-plan-error`; redirect execution-plan and process-substitution runtime types; `execute-reader-ast-in-context` | Own typed-reader AST dispatch, a new reader-only sequence helper, redirects, and process substitutions. The legacy `%execute-sequence-node-in-context` remains unchanged to satisfy D-02; `&&` short-circuiting is fixed only in `%execute-reader-sequence-node-in-context` on the `execute-reader-ast-in-context` path. Accept L02's stage-evaluator callback, prepare evaluated stages and final descriptor maps, then pass both to L05; read typed redirects directly and preserve the legacy splitter for legacy callers. Bind mapped standard streams and `*pipeline-stage-io*` for internal stages. Reject non-external or nested process-substitution stages, direction mismatch, and process substitution under `&` during preflight before allocation. Wrap L05 start/wait failures with the pipeline or redirect source span, clean up all resources, and do not expose partial results. Clean up and re-signal L06 conversion conditions unchanged. It does not edit shared AST types. |
| E03 | `src/presentation/input-state-core.lisp`, `src/presentation/input-state-copy.lisp`, `src/presentation/input-state-dispatch-data.lisp`, `src/presentation/input-state-dispatch.lisp`, new `src/presentation/input-state-vertical-navigation.lisp`, `src/presentation/input-state-vi-edit.lisp`, `src/presentation/input-state-words.lisp`, `src/presentation/input-state-words-scan.lisp`, `src/presentation/repl-execution.lisp` lines 28–36, REPL handling definitions in `src/presentation/repl-output-handlers.lisp` except L04's restart wrapper, `t/unit/test-input-state-navigation.lisp`, `t/unit/test-input-state-navigation-properties.lisp`, `t/unit/test-input-state-vi.lisp`, new `t/unit/test-input-state-continuation.lisp` and `t/unit/test-repl-submission.lisp`, and `nshell.asd` entries | `input-state` slot `preferred-visual-column` (`nil` or nonnegative integer); `+editor-indent-width+` set to 2; editor continuation, indentation, and vertical navigation state | Own the preferred-column slot and its copy/reset behavior, Up/Down dispatch and movement, REPL scanner/reader dispatch, and continuation over the existing `*input-state*` buffer; do not create another submission buffer. Retain invalid input and cursor; for incomplete input, insert a newline followed by `next-indent` spaces at the current cursor and leave the cursor after those spaces. Build the new submission route as a dormant path; do not make it the default until WP-X01 switches after P5 passes. Route complete submissions through `read-submission` with the `reader-context` captured from the raw buffer. Pass that same context to `scan-input`; expansion cannot switch the mode. Incremental editor scans may use `:auto`. Consume `scan-result`, pass `+editor-indent-width+` to `scan-input`, and provide the active `classify-sexp-head` callback for S-expression scans. Test scanner indentation calculation in L01; test editor insertion and cursor placement in `t/unit/test-input-state-continuation.lisp`, and REPL dispatch and buffer retention in `t/unit/test-repl-submission.lisp`. Wrap each top-level result evaluation with L04's `call-with-command-failure-restarts` and call L02's `evaluate-reader-result-in-context` once per result in order. |
| E04 | `src/presentation/contracts/e04-structural-editing.lisp`, `src/presentation/input-state-dispatch-data.lisp` (E04 action entries only), `src/presentation/input-state-dispatch.lisp` (E04 action branches only), new `src/presentation/input-state-structural-editing.lisp`, structural-editing tests, and `nshell.asd` entries | `apply-sexp-structural-edit(state scan-result action)` | Own the eight structural edit actions and their action-specific dispatch entries. Consume L01's scan result; E03 retains scanner invocation and the generic input reducer. |
| E05 | `src/presentation/contracts/e05-highlighting.lisp`, `src/presentation/highlight.lisp`, `src/presentation/repl-highlight.lisp`, `src/presentation/repl-rendering.lisp`, `src/presentation/repl-diagnostics.lisp`, diagnostic and highlighting tests | `highlight-line(input &key scan-result cursor-position absolute-start)`; highlight and diagnostic projection types | Consume scanner token kinds, spans, and `delimiter-pairs`; own matching-delimiter rendering, source-located reader diagnostics, `%render-edit-buffer-line`, and `render-edit-buffer`. Do not re-tokenize or edit scanner types. |
| C06 | `src/presentation/contracts/c06-completion-context.lisp`, `src/domain/completion/context.lisp`, `src/presentation/completion-ui-logic.lisp`, `src/presentation/completion-ui-text.lisp`, `src/presentation/repl-output-completion-help.lisp`, completion tests, and `nshell.asd` entries | `completion-context-for-scan(scan-result cursor)`; `complete-in-context(kb partial-input context &key path filesystem alias-table function-table variable-names directory home-directory)` | Keep the existing five-field `completion-context`; project scanner `cursor-role` into it. C06 owns the scanner-backed caller in `%refresh-completion-session-state`; the legacy route remains through P5. The domain completion package does not import application symbols. |
| E06 | `src/presentation/contracts/e06-history-expansion.lisp`, `src/presentation/input-state-suggestion.lisp`, abbreviation, history-expansion, and last-argument files under `src/presentation/` and `src/domain/`, with their tests | Suggestion and history projection types; `expand-history-input`, `source-span-to-origin-span` | Own history expansion and suggestion acceptance. E03 passes the history map to L01 and translates scanner diagnostics; L01 stores the map on each reader result/error. Do not add fields to scanner or completion context. |
| A01 | `packages/feature/assistant/src/domain/safety.lisp`, `packages/feature/assistant/src/domain/redaction.lisp`, assistant safety tests | Safety and redaction projection types | Consume evaluated values and source spans through accessors; preserve existing classification and redaction policy. |

Function ownership in the editor is explicit: E03 owns
`word-motion-target-left`, `word-motion-target-right`, `move-word-left`,
`move-word-right`, `word-transform-edit-at-cursor`,
`word-transform-edit-buffer`, `word-transform-edit-cursor-pos`,
`transform-word-at-cursor`, `capitalize-token-text`, `upcase-word-at-cursor`,
`downcase-word-at-cursor`, `capitalize-word-at-cursor`,
`word-transposition-at-cursor`, `word-transposition-buffer`,
`word-transposition-cursor-pos`, and `transpose-words-around-cursor` in
`src/presentation/input-state-words.lisp`. E06 owns
`suggestion-word-like-token-p`, `suggestion-first-token-at-or-after`,
`suggestion-token-accept-end`, `suggestion-redirection-operator-end`,
`%suggestion-scan-fd-digits`, `%suggestion-redirection-target-end`,
`suggestion-compact-redirection-end`, `suggestion-append-edit-for-state`,
`suggestion-append-edit-buffer`, `suggestion-append-edit-cursor-pos`,
`commit-suggestion-append-edit`, `suggestion-next-acceptance-segment`,
`next-suggestion-acceptance`, `commit-suggestion-acceptance`,
`append-suggestion-to-input-state`, `accept-suggestion-at-eol`, and
`accept-suggestion-word-at-eol` in
`src/presentation/input-state-suggestion.lisp`. E06 owns no functions in
`src/presentation/input-state-words.lisp`.

Every owner may add private value types in its owned files. A WP that needs a field on a shared type must state the field, type, reader, and consumer in this note, then ask L01 for the sole AST-file amendment. Other WPs use the resulting accessor and constructor; they do not copy, subclass, or redefine the shared struct. The same rule applies to scanner and registry types: their owner adds fields and accessors before consumers depend on them.

### Prototype and migration boundary

The prototype at `src/domain/parsing/sexp-reader-prototype.lisp` remains isolated from the default input path. Existing legacy execution tests keep their expectations; new prototype tests cover the AST fields and do not replace legacy-reader tests. WP-L00b adds AST fields with defaults that preserve old constructor behavior.

The prototype tests the command and pipeline AST boundary. It records legacy escaped-symbol glob eligibility, keeps argument-position `|` and `|&` literal, and sets `command-node.force-external-p`. It does not implement the production scanner, package resolution, command-island redirect extraction, or typed `|&` edges.

The migration order remains L01 reader/scanner, L02 evaluator, then parallel L03/L04/L06/L07, followed by L05/L08. P4 consumers can implement against the scanner and AST contracts after L01. No P3/P4 WP changes the default reader before WP-X01.

## History and abbreviation handoff

`!!` and `!$` remain pre-reader expansion on bare interactive input only.
Abbreviations expand at the input layer, and their output passes through the
shared scanner and reader. WP-E06 owns multi-line history entry, display, and
autosuggestion matching; it must settle those presentation rules before P5.
Those choices do not change the reader's one-result-per-top-level-form rule.
Reader spans index the post-expansion source; E06's source map translates them
back to the raw editor buffer when history expansion changed the input.

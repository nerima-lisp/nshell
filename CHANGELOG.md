# Changelog

All notable changes to nshell are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Mutation testing** via cl-weave's `run-mutations` / `assert-mutation-score`
  (`tests/unit/test-mutation.lisp`). Where coverage asks "did a test run this
  code?", these ask "would a test have *caught* a bug here?": each
  arithmetic/comparison/boolean/conditional site in a form is rewritten and
  re-checked against an oracle, and the suite demands a perfect 1.0 kill score
  for glob character-range membership, string-prefix length bounds, and
  arithmetic precedence. A local `assert-oracle-kills-mutations` macro keeps the
  form (data) separate from the oracle (logic). This is the effectiveness
  measure that `docs/coverage-analysis.md`'s "0 uncovered executable lines"
  cannot provide on its own.
- **cl-process-kit** now backs synchronous command-substitution capture
  (`run-external-capture`): its `run` enforces `*external-command-timeout*` by
  escalating SIGTERM to SIGKILL across the child's whole process group, so a
  timed-out `$(...)` leaves no orphaned descendants behind, and reports the
  timeout instead of the shell hand-rolling its own polling/escalation loop.
  The shell's own conventions stay in nshell: `PATH` resolution and the 127
  command-not-found code, stderr merged into the captured value (or replayed to
  a redirected `*error-output*`), the timeout message and exit 124, and the
  128+signal exit status for signaled children. Added to the ASDF system and the
  Nix flake (with its `cl-log-kit` dependency).
- Integrated the `nerima-lisp` Common Lisp toolkit family across the layers:
  - **cl-parser-kit** now backs `$((...))` arithmetic via a rule-based tokenizer
    and a Pratt (operator-precedence) parser that builds an AST evaluated
    separately. This adds exponentiation `**` (right-associative, binding tighter
    than unary minus), bitwise `& | ^ ~`, shifts `<< >>`, and the ternary `?:`,
    and fixes a short-circuit quirk where `1 || 5` and `0 && 5` previously erred.
  - **cl-dataflow** powers a new `pipeline-graph` builtin that renders a typed
    pipeline as a validated Graphviz DOT graph (or Mermaid with `--mermaid`)
    without executing it, and models the job lifecycle as an analyzable state
    machine.
  - **cl-cli** now declaratively describes the `nshell` command line
    (`--help`/`--version`/`-c COMMAND`/script dispatch), replacing the
    hand-rolled argument classifier.
  - **cl-boundary-kit** makes the REPL edge's OS effects (hostname, working
    directory, monotonic clock) explicit, swappable boundaries, making the prompt
    and command timing deterministic under test.
  - **cl-tty-kit** provides Unicode-correct display-width, truncation, and
    padding (replacing two divergent hand-rolled width tables) and the ANSI/SGR
    escape vocabulary used across rendering, prompt, and completion.
- `nshell/weave`: a cl-weave regression suite covering the completion engine.
  It exercises the cl-prolog knowledge base with property-based tests, fixtures,
  and benchmarks; runs direct Prolog queries (`findall`, negation-as-failure,
  and a Lisp foreign predicate composed with domain facts); and uses the
  `cl-prolog/weave` `deftest-queries`/`assert-query` bridge. Runnable via
  `scripts/weave.lisp`, the `weave` dev-shell alias, and the `weave` Nix check.
- `nshell.domain.completion:completion-rulebase` now publicly compiles the
  completion knowledge base into a first-class `cl-prolog:rulebase`, and the
  completion logic predicates (`completes`, `describes`, `has-flag`,
  `command-is`, `suggests-dir`, `suggests-file`) are exported so the rulebase
  answers the full cl-prolog query API.
- Vi-mode char-wise visual selection (`v`) with motion, yank, delete, change,
  and count-aware editing coverage.
- Parameter expansion now covers substring slicing (`${VAR:offset[:length]}`)
  and required-value diagnostics (`${VAR:?word}`).
- Completion help metadata now warms on demand and caches missing external
  command lookups so repeated completion requests stay responsive.

### Fixed
- Git prompt probes (`get-git-status`, run on every prompt render) are now
  bounded by a dedicated `*git-command-timeout*` (3 s) via cl-process-kit's `run`.
  Previously `%run-git` spawned git with `:wait t` and no timeout, so a slow,
  networked, or hung repository could stall the entire prompt indefinitely. On
  timeout the segment renders as if the directory were not a repository.
- `run-external-capture` now forwards standard input to the captured child only
  while `*redirected-stdin*` is bound (a here-doc, here-string, or `< file`, all
  of which are finite EOF-bearing streams). An unredirected `*standard-input*` is
  the interactive terminal, which never yields EOF; forwarding it left
  cl-process-kit's stdin pump thread blocked forever, so cleanup raised
  `process-io-error :cleanup` and the capture returned exit 1. The leaked feeder
  threads also made later PTY integration tests fail to `fork` ("Cannot fork with
  multiple threads running"), so this one change restores the process-capture,
  signal-exit, and PTY-foreground tests together. Matches real-shell semantics,
  where `$(echo hi)` does not consume the terminal.
- `%autosuggest-closed-quoted-token-p` no longer reports a lone quote character
  (`end - start = 1`) as a closed quoted token — a latent bug surfaced by a
  test that a stray missing paren had kept from ever running under FiveAM.
- Prompt command-duration tracking now records a non-negative millisecond value,
  including sub-millisecond commands.
- `source` command substitution scanning now preserves literal
  non-substitution `$` characters.

### Changed
- Replaced 20 straggler `(handler-case FORM (error () nil))` /
  `(handler-case FORM (error ()))` sites across `src/infrastructure/` and
  `src/presentation/` with `ignore-errors`, the macro the codebase already
  used 47 times elsewhere for exactly this shape — restoring consistency
  rather than introducing a new pattern. One site, `%seq-parse-args`
  (`application/builtin-commands.lisp`), was deliberately left as
  `handler-case`: it is a genuine multiple-values producer
  (`(values first step last)`), and `ignore-errors` returns a second
  `condition` value on its error path that `handler-case`'s explicit
  `(error () nil)` does not, so it is not a safe substitute for a
  values-returning function even though its sole caller only binds three
  values. Found via `docs/`-style audit of remaining macro-consolidation
  opportunities; every site was verified individually before conversion, and
  the change was applied and verified with `paredit edit replace` per site.
- Flattened `%builtin-command-path` (paren depth 14 → 9) by lifting its
  `emit-name` `labels` to a top-level `%emit-command-path`, extracting the
  `format`-inside-`format` "not found" line into `%command-path-missing-message`,
  and turning `(if args …)` into a leading `(if (null args) …)` guard so the main
  loop is no longer nested inside the branch. The per-kind output formats stay
  data on the `spec` plist; the emit is logic.
- Flattened `spawn-async`, the deepest-nested function in the tree (paren depth
  15), to depth 9 by extracting `%resolve-input-redirect`,
  `%resolve-output-redirect`, and `%spawn-in-own-process-group`. The two
  resolvers take a `register` continuation for cleanup tracking, which removes
  the three-times-repeated "open a stream, push it onto the cleanup list, return
  it" pattern and separates redirect-stream resolution (data) from the spawn
  itself (logic); `spawn-async` now reads as resolve-input, resolve-output,
  prepare-command, spawn.
- Folded eighteen near-identical tokenizer tests into four cl-weave `it-each`
  tables — word-token quoting/escaping (5 rows), redirection operators keyed by
  `(input length position value)` (5), balanced command substitution (5), and
  balanced process substitution (3). Each table separates its data (which input
  yields which token) from the shared logic (tokenize and assert), and cl-weave
  auto-generates a descriptive per-row name. A fifth table in
  `test-parser-diagnostics` folds the three leading/trailing operator-diagnostic
  tests into `(line kind start end)` rows. `it-each` blocks in the suite rose
  from 7 to 11, all clusters located with `paredit inspect duplicates`.
- Bumped every nerima-lisp dependency pin in `flake.lock` to the latest release
  its SBCL library is tested against, and pinned the `cl-weave` flake input to an
  explicit `v0.10.0` tag (was a floating default-branch ref resolving to an
  intermediate commit). All eight runtime inputs — cl-prolog, cl-parser-kit,
  cl-dataflow, cl-boundary-kit, cl-cli, cl-tty-kit, cl-log-kit, cl-process-kit —
  now lock to the exact revisions the local SBCL suite (1306 passing) validates.
- Consolidated three byte-for-byte-identical case-sensitive prefix helpers
  (`%string-prefix-p` in `builtin-string-support`, `%case-sensitive-prefix-p` in
  `candidate-ranking`, and `starts-with-p` in `expand`) into a single
  dependency-free `nshell.util:string-prefix-p`, discovered via
  `paredit inspect duplicates` and rewired with `paredit refactor
  replace-function-calls`. The completion engine's `%starts-with-p` was
  deliberately left in place: despite an identical shape it uses `string-equal`,
  not `string=`, so its prefix match is case-insensitive — folding it into the
  case-sensitive helper would have silently broken case-insensitive completion.
- Replaced git prompt probing's three-function process-adapter plist
  (`*git-process-fns*` with `:spawn`/`:output`/`:exit-code` hooks, injected via
  `with-git-process-fns`) with a single `*git-runner*` seam — a
  `(dir args) -> (values output exit-code)` function, bound via `with-git-runner`.
  Tests now supply a git result directly instead of faking a subprocess object,
  and the production path calls cl-process-kit's `run` with no adapter layer. The
  now-unused `%read-all-lines`, `%git-process-fn`, and `fake-git-process` helpers
  were removed.
- Migrated the entire test suite from FiveAM to
  [cl-weave](https://github.com/nerima-lisp/cl-weave). All ~1,290 cases now use
  `describe`/`it`/`expect`; the FiveAM dependency is removed from the ASDF
  system, the Nix flake, and the dev shell. Pass/fail parity with the previous
  FiveAM run was verified case by case.
- README and man page claims now align with the current 0.4.x status, test-count
  evidence, vi visual selection, here-document, and here-string support.
- README testing and contribution guidance now distinguishes hermetic Nix checks
  from full dev-shell integration coverage and links security reporting.
- Added an SBCL `sb-cover` coverage runner plus a dev-shell alias, and split
  control-flow sequence traversal into its own source file.
- Added `PUBLIC_READINESS.md` to make the world-level interactive-shell release
  bar, evidence requirements, and remaining public gaps explicit.
- CONTRIBUTING and the PR checklist now distinguish hermetic checks from
  non-sandboxed OS-interactive integration coverage.
- CONTRIBUTING now includes a release checklist for CI gates, binary smoke
  checks, public docs, manual tag/ref consistency, tarball contents, checksums,
  and changelog hygiene.
- README CLI usage now documents script-file execution and trailing `$argv`
  arguments consistently with `nshell --help` and the man page.
- Migrated all repository references from the `takeokunn` GitHub account to the
  `nerima-lisp` organization (ASDF `:homepage`/`:source-control`, flake metadata,
  README badges and clone URLs, SECURITY/CONTRIBUTING, and the man page). CI
  cache identities are infrastructure names and were intentionally left in place.
- Simplified the input-state copy-with-overrides machinery: the per-group value
  records (`%input-state-completion-copy`, `-transient-copy`, `-session-copy`)
  and the `%input-state-copy-spec` assembler are gone. The completion, transient,
  and session builders now resolve each override and return `make-input-state`
  initarg plists directly, which `copy-input-state-with` appends in one `apply`.
  Net ~130 fewer lines with identical behavior.
- Rewrote the `%glob-match-p-at` recursion as a two-cursor local `match` closing
  over the invariant pattern/text and their lengths, so each glob rule reads on
  its own instead of restating six arguments at every recursive call.
- Extracted `%suggestion-scan-fd-digits` and `%suggestion-redirection-target-end`
  from `suggestion-compact-redirection-end`, flattening its hand-rolled scanner.
- Replaced `glob-root`'s inline `(lambda (ch) (member ch '(#\* #\? #\[) ...))`
  with the existing `#'glob-char-p` predicate (moved above its first use), so the
  glob metacharacter set is defined once instead of duplicated.
- Extracted `%tilde-user-home` from `expand-tilde`, moving the `~USER` ->
  `/home/USER` string construction out of the `cond` so the dispatch reads as
  four plain cases (`~`, `~/`, `~USER`, literal).
- Extracted `%emit-right-prompt` from `%write-right-prompt`, separating the
  terminal-effect half (save cursor, emit the ANSI offset + colored segments,
  restore cursor) from the layout math (left width, available width, padding);
  the caller now reads as "if it fits, emit it at the computed padding."
- Flattened `%completion-help-enum-values` from a seven-level nested bail-out
  cascade into a three-level linear `let*` pipeline (locate parentheses -> take
  content -> split/trim/keep), and dropped the redundant `(when values values)`
  tail; behavior is unchanged.
- Extended the `define-value-struct` macro so more value objects can be
  generated from it instead of hand-written. The struct type may now be public
  (e.g. `prompt-segment`, whose `prompt-segment-p` predicate and type stay
  public) rather than only `%`-private; each slot accepts a `:copy` option
  (`:list`, `:seq`, or a copier symbol like `%copy-ast-list`) so accessors that
  hand back defensive copies are covered; and an `:accessor-prefix` names the
  public accessors independently of the type (e.g. `%completion-candidate` with
  `candidate-*` readers); a `:constructor` names the private constructor, keeping
  the codebase's `%allocate-*` raw-allocation convention that boundary tests pin;
  and a `:predicate` names (or suppresses) the type predicate, covering both the
  custom-named (`os-signal`'s `signal-p`) and deliberately-private
  (`%pipe-config-p`) cases. Converted 20 value structs onto the macro this cycle
  -- `prompt-model`, `prompt-segment`, `command-arg`, `case-clause`,
  `%parse-result`, `tokenization-result`, `%completion-candidate`,
  `list-selection-spec`, `variable-reference-syntax`, `parameter-binding`,
  `parameter-operator`, `fact`, `rule`, `os-signal`, `command`, `pipeline`,
  `pipe-config`, `pipeline-stage`, `pipeline-plan`, `abbreviation`,
  `abbreviation-token-range`, `sequence-node-command-separator`,
  `unquoted-field-fragment`, `whitespace-field-boundary`,
  `command-name-candidate`, `vi-visual-selection`, `vi-operator-edit`,
  `vi-visual-yank-edit`, `vi-visual-anchor-swap-edit`, `control-flow-frame`,
  `key-event`, `%domain-event`, `env-entry`, `env-binding`, `history-word`,
  `job-listing`, and `child-status` (37 value structs total) -- deleting their
  hand-written accessor/predicate boilerplate; existing `%`-private value structs
  expand identically to before. Each raw `defstruct` that remains was verified
  non-applicable with a concrete reason -- a mutable record (`job-wait-event`,
  `pty-process`), a behavior-only capsule with no public slot readers
  (`%buffer-*`, `%shell-token-range-set`), the `ast-node` `:include` hierarchy, a
  `%`-helper name clash (`arithmetic-substitution`), or accessor/type mismatches
  (`config`, `theme`). `docs/value-struct-audit.md` is a mechanically generated
  per-struct table that accounts for every one of the 139 remaining raw
  `defstruct`s with its concrete non-applicability reason (95 mutable, 28
  behavior-only capsules, 13 `ast-node` `:include` hierarchy, and one each of
  accessor mismatch, encapsulation, and helper collision) -- zero unexplained.
- Split the non-redirect parser data (separator facts and reduced-command
  projections) out of `domain/parsing/parser-data.lisp` into
  `domain/parsing/parser-separator-data.lisp` via `paredit refactor split-file`,
  leaving `parser-data.lisp` focused on redirect specs/facts/policy.
- Split the brace-expansion helpers out of `domain/expansion/expand.lisp` into a
  dedicated `domain/expansion/brace.lisp` (via `paredit refactor split-file`),
  leaving `expand.lisp` focused on tilde/glob/variable-name expansion. No symbol
  moved packages, so callers are unaffected.
- Rewrote `sequence-node-command-separators` from a mutable `copy-list` +
  `pop`-loop into a pure `mapcar` zip over the commands and the separators padded
  with a trailing `nil`, expressing the "pair each command with its following
  separator" step as data with no running mutable state.
- Rewrote the recursive glob directory walk in continuation-passing style:
  `%walk-directory-files dir continuation` applies the caller's continuation to
  each file and no longer threads an accumulator, separating the traversal
  (data) from what each file feeds (logic); `recursive-directory-files` collects
  via a pushing closure. Enumeration order — and its regression test — are
  preserved.
- Bumped every Nix flake input to its latest revision (`nix flake update`),
  which also re-pinned the transitive `cl-weave`/`paredit-cli` inputs from the
  old `takeokunn` account to `nerima-lisp`, completing the org migration at the
  lockfile level.
- Deepened property-based coverage into a cross-module invariant network of
  `check-property` laws over six domains. Expansion: glob literal-self-match and
  non-extension, `*` matching any separator-free segment, `**` crossing a
  separator `*` cannot, numeric-range and comma-group expansion sizes, no-brace
  identity, and arithmetic integer-literal identity, addition commutativity,
  add-then-subtract inverse, and multiply-by-zero. Tokenizer: determinism and
  span ordering (`0 <= start <= end`). History: consecutive duplicates keep
  size, and size never exceeds capacity. Parser: parse determinism and
  simple-word-command error-freeness. Environment: set/get round-trip, unset
  removes the binding, and exported-flag propagation. Completion: make-candidate
  text/score round-trip, and exact match out-ranking a prefix extension.
  List selection: `%argv-normalized-index` 1-based/negative index mapping, and
  `%list-range-fields` reversing under swapped bounds -- both written with the
  new `property` macro over `shrink-integer`-shrunk inputs.
- Closed real coverage gaps in the arithmetic evaluator by exercising the
  previously-untested `>=`, `<=`, and `!=` comparison operators and the unary `+`
  (`:pos`) prefix, plus a test that constructs every remaining domain-event type
  (pipeline/process/lifecycle events). `arithmetic.lisp` expression coverage rose
  from 62.2% to 67.6%.
- Added a `property` test macro that captures the recurring
  `(it NAME [DOC] (check-property (:trials 50) BINDINGS BODY))` scaffolding as one
  form, so the invariant network reads as a list of laws rather than repeated
  boilerplate -- the systematic shape behind the property suites.
- Added a `shrink-integer` shrinker (toward zero: zero, half, one step in) and
  wired greedy shrinking strategies through the property suites -- integer
  bindings shrink via `shrink-integer` and string bindings via
  `shrink-shell-word` rather than reporting the raw random counterexample -- so a
  failing law reports a minimal counterexample.
- Raised the abstraction of the input-state copy tests: the two white-box tests
  that pinned intermediate record shapes now assert `copy-input-state-with`'s
  observable field assembly through the public API (surfacing, for instance, that
  `vi-visual-anchor` is clamped to the rebuilt buffer).

### Removed
- Deleted the unused in-memory virtual-screen / cell-diff renderer
  (`infrastructure/terminal/screen.lisp`) and its tests. It had no production
  callers; terminal rendering goes through the `ansi.lisp`/cl-tty-kit path and
  direct line writes.
- Removed dead code with no callers anywhere in `src/` or `tests/`: the
  exported-but-uncalled `history-dedup` (and its export), and three unused
  property-based-testing helpers (`gen-logic-atom`, `gen-shell-pipeline`, and the
  `for-all-property` macro).

## [0.4.0] - 2026-06-21

### Added
- Script file execution: `nshell SCRIPT [ARGS...]` runs a script file, with full
  support for multiline blocks (functions, if/for/while/switch/begin) via the
  block-aware reader. Any trailing arguments are exposed to the script as
  `$argv`. An `examples/greet.nsh` script demonstrates the feature.

### Fixed
- Whole-line comments (and a leading `#!` shebang) in scripts and `source`d files
  are now skipped instead of causing a parse error.

### Added
- Man page (`man nshell`): a `nshell(1)` manual page documenting options, key
  bindings (Emacs and vi), expansions, control flow, builtins, and environment
  variables. It is installed into `share/man/man1` by the Nix package.

## [0.3.2] - 2026-06-21

### Added
- `seq` builtin: print a sequence of integers (`seq LAST`, `seq FIRST LAST`,
  `seq FIRST STEP LAST`, with negative STEP for descending) — pairs with for
  loops, e.g. `for i in (seq 1 10)`. Registered for `type` and tab-completion.

## [0.3.1] - 2026-06-21

### Added
- `count` builtin (fish-style): prints the number of arguments and exits 0 when
  there is at least one, otherwise 1 — pairs naturally with `$argv`
  (`count $argv`). Registered for `type` and tab-completion.

## [0.3.0] - 2026-06-21

### Added
- Function arguments: a called user-defined function now receives its arguments
  as the fish-style list `$argv` (a bare unquoted `$argv` forwards each argument
  as a separate word) and indexed `$argv[N]` (1-based). POSIX `$1`..`$9` remain
  literal, matching fish.

## [0.2.2] - 2026-06-21

### Changed
- CI hardening: environment-dependent integration tests (PTY round-trips,
  spawning `/bin/cat` / `stty`) are now skipped inside the hermetic Nix build
  sandbox — where those facilities don't exist — and instead run in a dedicated
  non-sandboxed CI job that has them. This makes `nix flake check` reliably green
  on Linux and macOS while preserving real integration coverage. Also removed the
  shut-down `magic-nix-cache-action` from the workflows.

## [0.2.1] - 2026-06-21

### Fixed
- External commands now inherit the real process environment (including `PATH`)
  when the shell has not exported any variables yet — previously they were
  spawned with an empty environment, so commands could not be found via `PATH`
  in batch mode and in non-REPL execution paths. This also makes the
  external-command/pipeline/PTY tests pass under the hermetic Linux CI sandbox.

## [0.2.0] - 2026-06-21

### Added
- Vi key bindings (opt-in via `NSHELL_VI_MODE=1`): `ESC` enters vi normal mode,
  with motions (`h l 0 ^ $ w b e`), insert entries (`i a I A`), edits
  (`x D C s`), operators (`dd cc dw cw d$ d0` and the `c` equivalents), and
  `j` / `k` for history. The default editor remains Emacs-style.
- File-descriptor redirections: `2>file` / `2>>file` (stderr to a file),
  `2>&1` (merge stderr into stdout), and `&>file` / `&>>file` (both streams to
  a file), plus explicit `1>` / `1>>`. Works for single commands and pipeline
  stages. The default (no stderr redirect) behavior is unchanged.
- POSIX command substitution `$(command)` in addition to the existing
  fish-style `(command)`. The tokenizer now keeps `$(...)` and `$((...))`
  attached to surrounding word characters (quote/escape aware), so
  `a$((1+2))b`, `"$(cmd)"`, and `pre$(echo ")")post` all parse and expand
  correctly. This also makes `$((expr))` arithmetic work end-to-end (previously
  it was eaten by the command-substitution scanner before the arithmetic pass).
- Brace expansion: comma lists `{a,b,c}` and ranges `{1..5}` / `{a..e}`,
  including nested and adjacent (cartesian) groups. A group with no top-level
  comma or valid range is left literal, matching shell behavior.
- Arithmetic expansion `$((expression))`: integer `+ - * / %`, parentheses,
  unary `- + ! ~`, comparisons (`== != < > <= >=`), and logical `&& ||`, with
  bare names resolved from the environment (unset → 0) and division-by-zero
  reported as an error.
- POSIX parameter-expansion operators inside `${...}`: `${VAR:-default}`,
  `${VAR-default}`, `${VAR:=default}`, `${VAR:+alt}`, `${VAR+alt}`,
  `${VAR:?msg}`, length `${#VAR}`, prefix/suffix stripping `${VAR#pat}` /
  `${VAR##pat}` / `${VAR%pat}` / `${VAR%%pat}` (glob patterns), and substitution
  `${VAR/pat/rep}` / `${VAR//pat/rep}` (literal patterns). Default, alternate,
  assignment words, and patterns are themselves variable-expanded; `${VAR:=word}`
  assigns the expanded word when its fallback branch is used.
- `CONTRIBUTING.md`, `SECURITY.md`, GitHub issue templates, and a pull-request
  template.
- `LICENSE` file (MIT) at the repository root.
- GitHub Actions CI (`nix flake check` — build + full test suite + smoke tests)
  on a Linux + macOS matrix, triggered on pushes, pull requests, and tags.
- GitHub Actions release workflow that builds per-platform binaries and uploads
  tarballs with SHA-256 checksums to GitHub Releases on `v*` tags.
- `meta` attributes (license, homepage, platforms, mainProgram) on the Nix
  package, and `:homepage` / `:source-control` to the ASDF system definition.
- This `CHANGELOG.md` and a project `README.md`.

### Changed
- Double-quoted strings now follow POSIX semantics: variables are expanded but
  globbing and word-splitting are suppressed, so `"$VAR"` expands while `"*"`
  stays literal. Arguments now carry a three-way quote style
  (unquoted / `:single` / `:double`) through the tokenizer, parser, and
  expander instead of a single "is-literal" boolean.

### Fixed
- Made the `repl-clear-screen` rendering test hermetic: it now pins the prompt
  width and terminal size so the asserted rendered-line count no longer depends
  on the ambient working directory (the default prompt renders the cwd, which is
  a long path inside the build sandbox). The full suite is green (4912 checks).

## [0.1.0]

Initial development version: fish-inspired interactive shell in Common Lisp
(SBCL) with a CPS/trampoline REPL, syntax highlighting, autosuggestions,
abbreviations, completion engine, kill-ring/undo, history search, job control,
and a Nix-based reproducible build.

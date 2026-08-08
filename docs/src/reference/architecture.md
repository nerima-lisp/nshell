# Architecture

nshell follows a domain-driven, layered design. Each layer depends only on the
layers beneath it:

```
src/
├── domain/          Pure shell logic: parsing, expansion, completion,
│                    history, prompting, job-control — no I/O.
├── application/     Use cases: builtins, pipeline execution, job management.
├── infrastructure/  ACLs over the OS: syscalls, PTY, signals, terminal I/O,
│                    persistence. SBCL-specific code is isolated here.
└── presentation/    The REPL, line editor (input-state reducer), rendering,
                     highlighting, autosuggestions, completion UI.
```

The REPL is structured as a **continuation-passing / trampoline loop**: each
keystroke runs a pure reducer over an immutable `input-state`, and rendering is
derived from that state. This keeps the interactive core deterministic and
unit-testable without a terminal. See
[Core concepts](../guide/concepts.md#the-input-state-is-a-value) for what that
buys in practice.

Confining SBCL-specific code to `infrastructure/` is what makes the layers
above it portable in principle and testable in practice: a test replaces a
boundary with a value instead of arranging for the operating system to produce
one.

## Toolkit foundation

nshell builds on the `nerima-lisp` Common Lisp toolkit family, each wired at the
layer where it fits the domain-driven design:

- **[cl-parser-kit](https://github.com/nerima-lisp/cl-parser-kit)** — its
  rule-based tokenizer and Pratt (operator-precedence) parser drive `$((...))`
  arithmetic, which parses to an AST and then evaluates, adding `**`, bitwise
  `& | ^ ~`, shifts `<< >>`, and the ternary `?:`.
- **[cl-dataflow](https://github.com/nerima-lisp/cl-dataflow)** — renders
  pipelines as validated computation graphs (`pipeline-graph`) and models the
  job lifecycle as an analyzable state machine.
- **[cl-boundary-kit](https://github.com/nerima-lisp/cl-boundary-kit)** — makes
  the REPL edge's OS effects (hostname, working directory, clock) explicit,
  swappable boundaries, so the prompt and command timing are deterministic
  under test.
- **[cl-cli](https://github.com/nerima-lisp/cl-cli)** — declaratively describes
  the `nshell` command line (`--help`/`--version`/`-c`/script dispatch).
- **[cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit)** — provides
  Unicode-correct display-width, truncation, and padding; the ANSI/SGR escape
  vocabulary used by rendering, prompt, and completion; and the
  `ioctl(TIOCGWINSZ)` window-size query behind
  `nshell.infrastructure.acl:get-terminal-size`. Raw mode is deliberately *not*
  taken from the kit: `cl-tty-kit:enable-raw-mode` is a full cfmakeraw-style
  mode that also clears `ISIG` and `OPOST`, while nshell holds raw mode for the
  whole session — including while a foreground child runs — and needs the
  terminal driver to keep turning `^C`/`^Z` into signals for that child and to
  keep mapping LF to CR-LF. See the commentary in
  `src/infrastructure/terminal/raw-mode.lisp`.
- **[cl-process-kit](https://github.com/nerima-lisp/cl-process-kit)** — backs
  timeout-guarded process launch, escalating SIGTERM to SIGKILL across a
  child's whole process group so a timed-out command substitution leaves no
  orphaned descendants.
- **[cl-prolog](https://github.com/nerima-lisp/cl-prolog)** — the logic engine
  behind the completion knowledge base.

## Test suites

Two suites run under [cl-weave](https://github.com/nerima-lisp/cl-weave), both
exposed as Nix checks:

- **`nshell/test`** — the primary regression suite, in `t/`.
- **`nshell/weave`** — a focused suite exercising the completion engine's
  cl-prolog knowledge base with property-based tests, fixtures, benchmarks, and
  direct Prolog queries (`findall`, negation-as-failure, foreign predicates)
  plus the `cl-prolog/weave` query bridge.

Cases that need a real PTY, `stty`, or external binaries cannot run in the Nix
sandbox and are covered by CI's separate `integration` job; see
[Recipes](../guide/recipes.md#the-non-sandboxed-integration-run).

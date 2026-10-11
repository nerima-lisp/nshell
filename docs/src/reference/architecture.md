# Architecture

nshell groups shell policy, use cases, operating-system adapters, and the
interactive interface into four layers:

```
src/
├── domain/          Pure shell logic: parsing, expansion, completion,
│                    history, prompting, job-control (no I/O).
├── application/     Use cases: builtins, pipeline execution, job management.
├── infrastructure/  OS adapters: syscalls, PTY, signals, terminal I/O,
│                    persistence.
└── presentation/    The REPL, line editor (input-state reducer), rendering,
                     highlighting, autosuggestions, completion UI.
```

`src/` contains the shell runtime. Features under `packages/` keep their
layers together; `<layer>` below means `domain`, `application`,
`infrastructure`, or `presentation`:

```
packages/
├── core/<name>/src/<layer>/       Shared domain and architecture primitives.
└── feature/<name>/src/<layer>/    A feature's domain, use cases, adapters, and UI.
```

The command-line feature's pure option
policy, application contract, and help presentation live in
`packages/feature/command-line/src/`. `src/main.lisp` constructs and parses
the CLI with `cl-cli`, delegates option policy and help to the feature, and
dispatches interactive, command, script, or stdin execution. `nshell.asd`
declares the runtime and feature modules and their load order.

## Assistant feature

The assistant is a vertical feature under
`packages/feature/assistant/src/<layer>/`. Its application layer assembles
context and tracks settings and usage, while the infrastructure layer isolates
the model-sidecar boundary and audit state. The sidecar is an external
assistant process; `src/infrastructure/assistant-sidecar-stream.lisp`
manages its startup, requests, events, and shutdown. Domain checks classify proposed
commands and redact sensitive payloads before the REPL approval gate allows a
proposal to execute.

`t/unit/` checks feature policy and contracts.
`t/integration/test-package-topology.lisp` checks that the layer directories
exist, not that dependencies obey the layer boundaries. `t/e2e/` checks
user-facing CLI behavior.

## Shell runtime

The REPL is structured as a **continuation-passing / trampoline loop**: each
keystroke runs a pure reducer over an immutable `input-state`, and rendering is
derived from that state. This keeps the interactive core deterministic and
unit-testable without a terminal. See
[Core concepts](../guide/concepts.md#the-input-state-is-a-value) for what that
buys in practice.

The runtime targets SBCL. OS adapters live primarily in `infrastructure/`,
but application and presentation code also use SBCL facilities, including
timeouts and process status.

Pipeline orchestration keeps process waiting and termination policy in
`infrastructure/acl/syscall-pipeline-wait.lisp`, separate from pipe topology
and stage spawning. That file implements timeout escalation, process-group
ownership, and pipefail status calculation.

## Toolkit foundation

nshell uses these `nerima-lisp` Common Lisp toolkits:

- **[cl-parser-kit](https://github.com/nerima-lisp/cl-parser-kit)**: its
  rule-based tokenizer and Pratt (operator-precedence) parser drive `$((...))`
  arithmetic, which parses to an AST and then evaluates, adding `**`, bitwise
  `& | ^ ~`, shifts `<< >>`, and the ternary `?:`.
- **[cl-dataflow-kit](https://github.com/nerima-lisp/cl-dataflow-kit)**: renders
  pipelines as validated computation graphs (`pipeline-graph`) and models the
  job lifecycle as an analyzable state machine.
- **[cl-boundary-kit](https://github.com/nerima-lisp/cl-boundary-kit)**: makes
  the REPL edge's OS effects (hostname, working directory, clock) explicit,
  swappable boundaries, so the prompt and command timing are deterministic
  under test.
- **[cl-cli](https://github.com/nerima-lisp/cl-cli)**: declaratively describes
  the `nshell` command line (`--help`/`--version`/`-c`/script dispatch).
- **[cl-tty-kit](https://github.com/nerima-lisp/cl-tty-kit)**: provides
  Unicode-correct display-width, truncation, and padding; the ANSI/SGR escape
  vocabulary used by rendering, prompt, and completion; and the
  `ioctl(TIOCGWINSZ)` window-size query behind
  `nshell.infrastructure.acl:get-terminal-size`. Raw mode is deliberately *not*
  taken from the kit: `cl-tty-kit:enable-raw-mode` is a full cfmakeraw-style
  mode that also clears `ISIG` and `OPOST`. nshell's editor preserves these
  flags so the terminal driver still generates signals and maps LF to CR-LF.
  Before running a foreground command, nshell restores the saved terminal
  settings; after the command returns, it re-enables editor mode.
  nshell snapshots the complete native terminal settings (Linux `termios2`
  or Darwin `termios`) to preserve speeds and control fields across raw-mode
  changes. See the commentary in
  `src/infrastructure/terminal/raw-mode.lisp`.
- **[cl-process-kit](https://github.com/nerima-lisp/cl-process-kit)**: backs
  timeout-guarded process launch, escalating SIGTERM to SIGKILL across a
  child's whole process group so a timed-out command substitution leaves no
  orphaned descendants.
- **[cl-prolog-kit](https://github.com/nerima-lisp/cl-prolog-kit)**: the logic engine
  behind the completion knowledge base.

## Test suites

Two suites run under [cl-weave](https://github.com/nerima-lisp/cl-weave), both
exposed as Nix checks:

- **`nshell/test`**: the primary regression suite, in `t/`.
- **`nshell/weave`**: a focused suite exercising the completion engine's
  cl-prolog-kit knowledge base with property-based tests, fixtures, benchmarks, and
  direct Prolog queries (`findall`, negation-as-failure, foreign predicates)
  plus the `cl-prolog-kit/weave` query bridge.

Cases that need a real PTY, `stty`, or external binaries cannot run in the Nix
sandbox and are covered by CI's separate `integration` job; see
[Recipes](../guide/recipes.md#the-non-sandboxed-integration-run).

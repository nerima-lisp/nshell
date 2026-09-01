;;; This form comes FIRST, before any defsystem. ASDF binds *package* to
;;; ASDF-USER only for a file it loads itself; read any other way — a REPL
;;; `load`, an editor evaluating the buffer, flake.nix parsing :version — the
;;; file is read in whatever package happens to be current, and an unqualified
;;; `defsystem` then fails to read at all. Saying it makes the file
;;; self-contained. See PACKAGE_STANDARD.md "asd の書き方".
(in-package #:asdf-user)

;;; Metadata keys follow the org's canonical order:
;;;   :description :long-description :author :maintainer :license :version
;;;   :homepage :bug-tracker :source-control :depends-on :pathname :serial
;;;   :components :in-order-to
;;; so a diff between two sibling repositories shows what actually differs and
;;; a missing key is visible by position.
(asdf:defsystem "nshell"
  :description "Modern interactive shell in Common Lisp"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  ;; Single source of truth for the version. flake.nix reads this form
  ;; line-by-line, and release.yml refuses a tag that disagrees with it.
  :version "0.4.0"
  :homepage "https://github.com/nerima-lisp/nshell"
  :bug-tracker "https://github.com/nerima-lisp/nshell/issues"
  :source-control (:git "https://github.com/nerima-lisp/nshell.git")
  :depends-on ("cl-prolog-kit"
               "cl-parser-kit"
               "cl-dataflow-kit"
               "cl-host-kit"
               "cl-boundary-kit"
               "cl-cli"
               "cl-tty-kit"
               "cl-process-kit"
               "cl-history-kit"
               "cl-concurrent-kit")
  :pathname "src"
  :serial t
  :components
  ((:file "package")
   (:module "core-kernel"
    :pathname "../packages/core/kernel/src"
    :serial t
    :components ((:file "package")
                 (:file "domain/feature-registry")))
   (:file "package-domain")
   (:file "package-application")
   (:file "package-infrastructure")
   (:file "package-presentation")
   (:module "feature-command-line"
    :pathname "../packages/feature/command-line/src"
    :serial t
    :components ((:file "package")
                 (:file "feature")
                 (:file "domain/options")
                 (:file "application/contract")
                 (:file "presentation/help")))
   (:file "util/struct-macros")
   (:file "util/strings")
   (:file "domain/signals/signal")
   (:file "domain/input/key-event")
   (:file "domain/execution/command")
   (:file "domain/execution/pipeline")
   (:file "domain/execution/job")
     (:file "domain/parsing/ast")
     (:file "domain/parsing/ast-arguments")
     (:file "domain/parsing/ast-redirect-split")
     (:file "domain/parsing/tokenizer-data")
     (:file "domain/parsing/tokenizer-readers")
     (:file "domain/parsing/tokenizer-handlers")
   (:file "domain/parsing/parse-result")
   (:file "domain/parsing/control-flow-data")
   (:file "domain/parsing/control-flow")
   (:file "domain/parsing/control-flow-sequence")
   (:file "domain/parsing/parser-data-definitions")
   (:file "domain/parsing/parser-data")
   (:file "domain/parsing/parser-shell-redirect")
   (:file "domain/parsing/parser-redirect-data"
          :pathname "../data/domain/parsing/parser-redirect-data")
   (:file "domain/parsing/parser-separator-static-data"
          :pathname "../data/domain/parsing/parser-separator-data")
   (:file "domain/parsing/parser-separator-data")
   (:file "domain/parsing/parser-assembly")
   (:file "domain/parsing/parser-here-doc-data")
   (:file "domain/parsing/parser-here-doc")
   (:file "domain/parsing/parser-here-doc-targets")
   (:file "domain/parsing/parser-reduction-data")
   (:file "domain/parsing/parser-reduction")
   (:file "domain/parsing/parser")
    (:file "domain/environment/env")
    (:file "domain/filesystem")
     (:file "domain/expansion/expand")
     (:file "domain/expansion/brace")
     (:file "domain/expansion/parameter-data")
     (:file "domain/expansion/parameter-selection")
     (:file "domain/expansion/parameter-braced")
     (:file "domain/expansion/parameter")
     (:file "domain/expansion/arithmetic-operator-data"
            :pathname "../data/domain/expansion/arithmetic-operator-data")
     (:file "domain/expansion/arithmetic")
     (:file "domain/expansion/fields")
     (:file "domain/abbreviation/expansion")
   (:file "domain/completion/candidate")
   (:file "domain/completion/catalog-build")
   (:file "domain/completion/catalog-command-data"
          :pathname "../data/domain/completion/catalog-command-data")
   (:file "domain/completion/catalog-display-data"
          :pathname "../data/domain/completion/catalog-display-data")
   (:file "domain/completion/catalog-data")
   (:file "domain/completion/rule-data")
   (:file "domain/completion/knowledge-base")
   (:file "domain/completion/knowledge-base-help")
   (:file "domain/completion/context")
   (:file "domain/completion/filesystem")
   (:file "domain/completion/filesystem-path-command")
   (:file "domain/completion/filesystem-file-completion")
   (:file "domain/completion/knowledge-base-candidates")
   (:file "domain/completion/candidate-ranking")
   (:file "domain/completion/engine")
   (:file "domain/history/last-argument")
   (:file "domain/history/expansion")
   (:file "domain/job-control/monitor")
   (:file "domain/configuration/theme")
   (:file "domain/configuration/config")
   (:file "domain/prompting/prompt")
   (:file "application/shell-context")
	   (:file "application/execute-pipeline-fragment-expansion")
	   (:file "application/execute-pipeline-expansion-data")
	   (:file "application/execute-pipeline-expansion")
	   (:file "application/execute-pipeline-expansion-here-doc")
	   (:file "application/execute-pipeline-redirect")
	   (:file "application/execute-pipeline-stage-external-data")
	   (:file "application/execute-pipeline-stage-external-output")
	   (:file "application/execute-pipeline-stage-external")
	   (:file "application/execute-pipeline-stage-background")
	   (:file "application/execute-pipeline-stage")
	   (:file "application/execute-pipeline")
	   (:file "application/execute-pipeline-control")
   (:file "application/manage-job")
   (:file "application/pipeline-diagram")
   (:file "application/builtin-spec-data"
          :pathname "../data/application/builtin-spec-data")
   (:file "application/builtin-spec")
   (:file "application/builtin-runtime")
   (:file "application/builtin-type-helpers")
   (:file "application/builtin-macros")
   (:file "application/builtin-string-support")
   (:file "application/builtin-string-repeat")
   (:file "application/builtin-string")
   (:file "application/builtin-source-reader")
   (:file "application/builtin-source")
   (:file "application/builtin-printf-format-support")
   (:file "application/builtin-printf")
   (:file "application/builtin-commands")
   (:file "application/builtin-commands-history")
   (:file "application/builtin-job-signal-data"
          :pathname "../data/application/builtin-job-signal-data")
   (:file "application/builtin-jobs")
   (:file "application/builtin-state-env")
   (:file "application/builtin-state-tables")
   (:file "application/builtin-state-functions")
   (:file "application/builtin-complete")
   (:file "application/builtin-test")
   (:file "application/builtins")
   (:file "application/search-history")
   (:file "infrastructure/acl/syscall")
   (:file "infrastructure/acl/syscall-foreign")
   (:file "infrastructure/acl/syscall-environment")
   (:file "infrastructure/acl/syscall-redirection")
   (:file "infrastructure/acl/syscall-job-control")
   (:file "infrastructure/acl/syscall-process-resolution")
   (:file "infrastructure/acl/syscall-process-io")
   (:file "infrastructure/acl/syscall-process")
   (:file "infrastructure/acl/filesystem")
   (:file "infrastructure/acl/syscall-pipeline-streams")
   (:file "infrastructure/acl/syscall-pipeline-wait")
   (:file "infrastructure/acl/syscall-pipeline")
   (:file "infrastructure/acl/syscall-process-substitution")
   (:file "infrastructure/acl/syscall-terminal")
   (:file "infrastructure/acl/git")
   (:file "infrastructure/acl/pty")
   (:file "infrastructure/acl/pty-spawn")
   (:file "infrastructure/acl/signal-acl")
   (:file "infrastructure/persistence/file-history")
   (:file "infrastructure/persistence/file-config")
   (:file "infrastructure/terminal/detection")
   (:file "infrastructure/terminal/raw-mode")
   (:file "infrastructure/terminal/ansi")
   (:file "infrastructure/terminal/input-core")
   (:file "infrastructure/terminal/input-decode")
   (:file "infrastructure/terminal/input-read")
   (:file "presentation/input-state-static-data"
          :pathname "../data/presentation/input-state-data")
   (:file "presentation/input-state-core")
   (:file "presentation/input-state-copy-plist")
   (:file "presentation/input-state-copy")
   (:file "presentation/input-state-helpers")
   (:file "presentation/input-state-buffer")
   (:file "presentation/input-state-buffer-ops")
   (:file "presentation/input-state-buffer-transforms")
   (:file "presentation/input-state-words-scan")
   (:file "presentation/input-state-words")
   (:file "presentation/input-state-undo")
   (:file "presentation/input-state-suggestion")
   (:file "presentation/completion-ui-logic")
   (:file "presentation/input-state-completion")
   (:file "presentation/input-state-kill-yank")
   (:file "presentation/input-state-history-search")
   (:file "presentation/input-state-dispatch")
	   (:file "presentation/input-state-vi-data")
	   (:file "presentation/input-state-vi")
	   (:file "presentation/input-state-vi-edit")
   (:file "presentation/input-state-session")
   (:file "presentation/repl-boundaries")
   (:file "presentation/terminal-size")
   (:file "presentation/prompt-display")
   (:file "presentation/completion-ui")
   (:file "presentation/autosuggest")
   (:file "presentation/highlight-data"
          :pathname "../data/presentation/highlight-data")
   (:file "presentation/highlight")
	   (:file "presentation/cps")
	   (:file "presentation/repl-state")
		   (:file "presentation/repl-input-state")
		   (:file "presentation/repl-completion-seed")
		   (:file "presentation/repl-environment")
		   (:file "presentation/repl-session-init")
		   (:file "presentation/repl-process")
   (:file "presentation/repl-execution-context")
   (:file "presentation/repl-execution-command")
   (:file "presentation/repl-execution")
   (:file "presentation/repl-rendering-cursor")
   (:file "presentation/repl-rendering")
   (:file "presentation/repl-diagnostics")
   (:file "presentation/repl-output-completion-help")
   (:file "presentation/repl-output-completion")
   (:file "presentation/editor")
   (:file "presentation/repl-output-handlers")
   (:file "presentation/repl-output-event-handlers")
   (:file "presentation/repl-output")
	   (:file "presentation/repl-session")
	   (:file "presentation/repl-batch")
	   (:file "presentation/repl")
	   (:file "main"))
  ;; The three build keys and the :perform below are exempt from the metadata
  ;; order above -- PACKAGE_STANDARD.md names cl-weave's identical trio and
  ;; cl-tty-kit's :perform as "はどこに書いても構いません" -- and they sit here,
  ;; together, because they are one statement: how this system becomes a
  ;; binary. They are also the ONLY statement of it, so `nix build` and a plain
  ;; `(asdf:operate 'asdf:program-op "nshell")` in a REPL produce the same
  ;; executable; flake.nix no longer repeats the entry point in a hand-written
  ;; save-lisp-and-die of its own.
  :build-operation "program-op"
  :build-pathname "nshell"
  :entry-point "nshell:main"
  ;; Why this method exists at all: ASDF's own `perform ((o image-op) (c
  ;; system))` calls `uiop:dump-image` and never passes :compression, and SBCL
  ;; offers no global that would add it, so a system that wants a compressed
  ;; core must dump it itself. nshell has shipped a compressed image since
  ;; before this file declared an entry point (flake.nix dumped it by hand);
  ;; performing the dump here is what let that Nix code be replaced by
  ;; cl-nix-forge's mkExecutable, which drives program-op and documents
  ;; :compression as the one thing it cannot express.
  ;;
  ;; ASDF:OUTPUT-FILE rather than a literal "nshell": it resolves
  ;; :build-pathname through whatever output translations are configured, so
  ;; the image lands exactly where the default method would have put it --
  ;; which is the path mkExecutable then goes looking for.
  ;;
  ;; The toplevel function is read back out of :entry-point above instead of
  ;; being named a second time, so the two cannot drift apart; this is the
  ;; same idiom cl-nix-forge's own Darwin delivery path uses. UIOP and
  ;; ASDF/SYSTEM are safe to name at read time for the reason spelled out at
  ;; the nshell/test :perform below: ASDF ships both, so they are in the image
  ;; before this file is read. `#'nshell:main` would NOT be -- it is a
  ;; read-time error, which is why the entry point is a string.
  :perform (asdf:program-op (o c)
             (sb-ext:save-lisp-and-die
              (asdf:output-file o c)
              :executable t
              :compression t
              ;; Stop the SBCL C runtime from intercepting --version/--help and
              ;; other runtime flags before nshell:main runs.
              :save-runtime-options t
              :toplevel (uiop:ensure-function
                         (asdf/system:component-entry-point c))))
  :in-order-to ((test-op (test-op "nshell/test"))))

(asdf:defsystem "nshell/test"
  :version "0.4.0"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/nshell"
  :bug-tracker "https://github.com/nerima-lisp/nshell/issues"
  :source-control (:git "https://github.com/nerima-lisp/nshell.git")
  :description "Test system for nshell"
  :depends-on ("nshell" "cl-weave")
  :pathname "t"
  :serial t
  :components
  ((:file "package")
   (:file "support/assertions")
   (:file "helpers-runner")
               (:file "support/pbt")
               (:file "support/pbt-shell")
               (:file "support/input-state")
               (:file "support/input-state-assertions")
   (:file "support/repl")
   (:file "support/builtins")
   (:file "support/completion")
               (:file "support/prompt")
               (:file "support/history")
               (:file "support/matchers")
   (:file "unit/test-package-by-feature")
   (:file "unit/test-signals")
   (:file "unit/test-execution-domain")
   (:file "unit/test-last-argument")
   (:file "unit/test-history-expansion")
   (:file "unit/test-configuration")
   (:file "unit/test-tokenizer")
   (:file "unit/test-environment")
   (:file "unit/test-expansion")
   (:file "unit/test-expansion-parameter")
   (:file "unit/test-expansion-arithmetic-glob")
   (:file "unit/test-mutation")
   (:file "unit/test-expansion-abbreviation")
   (:file "unit/test-completion-rules")
   (:file "unit/test-completion-rule-prover-boundaries")
    (:file "unit/test-completion-rule-prover")
    (:file "unit/test-completion-builtins")
    (:file "unit/test-completion-knowledge-base")
    (:file "unit/test-completion-path-reducer")
    (:file "unit/test-completion-knowledge-base-behavior")
    (:file "unit/test-completion-properties")
    (:file "unit/test-completion-context")
   (:file "unit/test-repl")
   (:file "unit/test-repl-completion-data")
   (:file "unit/test-repl-background")
   (:file "unit/test-repl-state")
   (:file "unit/test-repl-execution")
   (:file "unit/test-repl-rendering")
   (:file "unit/test-repl-rendering-layout")
   (:file "unit/test-parser")
   (:file "unit/test-parser-basic")
   (:file "unit/test-parser-basic-redirects")
   (:file "unit/test-parser-basic-here-doc")
   (:file "unit/test-parser-diagnostics")
   (:file "unit/test-parser-control-flow")
   (:file "unit/test-parser-control-flow-sequence")
   (:file "unit/test-parser-properties")
   (:file "unit/test-cps")
   (:file "unit/test-input-state")
   (:file "unit/test-input-state-session")
   (:file "unit/test-input-state-insertion")
   (:file "unit/test-input-state-navigation")
   (:file "unit/test-input-state-kill-yank")
   (:file "unit/test-input-state-commands")
   (:file "unit/test-input-state-case-undo")
   (:file "unit/test-input-state-completion")
   (:file "unit/test-input-state-completion-rendering")
   (:file "unit/test-input-state-completion-session")
   (:file "unit/test-input-state-suggestion")
   (:file "unit/test-input-state-vi")
   (:file "unit/test-input-state-search")
   (:file "unit/test-input-state-search-results")
   (:file "unit/test-input-state-core-properties")
   (:file "unit/test-input-state-navigation-properties")
   (:file "unit/test-input-state-kill-yank-properties")
   (:file "unit/test-input-state-completion-properties")
   (:file "unit/test-input-state-completion-cycling")
   (:file "unit/test-input-state-search-properties")
   (:file "unit/test-job-control-domain")
   (:file "unit/test-builtins-job-parsing")
   (:file "unit/test-pipeline-plan")
   (:file "unit/test-pipeline-diagram")
   (:file "unit/test-shell-context")
   (:file "unit/test-repl-boundaries")
   (:file "unit/test-builtins")
   (:file "unit/test-builtins-test")
   (:file "unit/test-builtins-core")
   (:file "unit/test-terminal-detection")
   (:file "unit/test-builtins-core-io")
   (:file "unit/test-builtins-counting")
   (:file "unit/test-builtins-core-string")
   (:file "unit/test-builtins-string-pbt")
   (:file "unit/test-builtins-core-shell")
   (:file "unit/test-builtins-core-complete")
   (:file "unit/test-builtins-source")
   (:file "unit/test-builtins-source-control-flow")
   (:file "unit/test-builtins-source-loops")
   (:file "unit/test-builtins-source-pipeline")
   (:file "unit/test-execute-pipeline-support")
   (:file "unit/test-execute-pipeline")
   (:file "unit/test-execute-pipeline-expansion")
   (:file "unit/test-manage-job")
   (:file "unit/test-search-history")
   (:file "unit/test-autosuggest")
   (:file "unit/test-prompt")
   (:file "unit/test-prompt-domain")
   (:file "unit/test-prompt-truncation")
   (:file "unit/test-prompt-rendering")
   (:file "unit/test-prompt-properties")
   (:file "integration/test-pipeline")
   (:file "integration/test-process")
   (:file "integration/test-pty")
   (:file "integration/test-pty-integration")
   (:file "integration/test-signal-handling")
   (:file "integration/test-job-control")
   (:file "integration/test-terminal")
   (:file "integration/test-terminal-stream")
   (:file "integration/test-terminal-presentation")
   (:file "integration/test-terminal-ansi")
   (:file "integration/test-file-config")
   (:file "integration/test-file-history")
   (:file "integration/test-package-topology")
   (:file "e2e/test-smoke")
   (:file "e2e/test-smoke-script")
   (:file "e2e/test-smoke-input")
   (:file "e2e/test-smoke-editing")
   (:file "e2e/test-smoke-pipeline")
   (:file "e2e/test-history")
   (:file "e2e/test-signals")
   (:file "e2e/test-job-control")
   (:file "e2e/test-package-route")
   (:file "perf/test-startup")
   ;; Appended rather than inserted next to helpers-runner: :serial t makes the
   ;; order load order, and every existing entry must keep its position.
   (:file "main-test"))
   ;; Not HOST-KIT:SYMBOL-CALL, and no longer UIOP:SYMBOL-CALL either: a .asd is
   ;; read by the plain CL reader before :depends-on is ever consulted, so any
   ;; PKG:SYMBOL token here must resolve against a package already in the image.
   ;; UIOP happens to be safe because ASDF ships it; CL-HOST-KIT is not loaded
   ;; at read time no matter what this system depends on, so a HOST-KIT: prefix
   ;; would be a read-time PACKAGE-DOES-NOT-EXIST error that takes the whole
   ;; file -- including the "nshell" system above -- down with it.
   ;; FIND-SYMBOL/FIND-PACKAGE/FUNCALL are CL, always present, and are what
   ;; SYMBOL-CALL boils down to anyway.
   :perform (asdf:test-op (o s)
              (declare (ignore o s))
              (unless (funcall (find-symbol "RUN-TESTS" (find-package "NSHELL/TEST")))
                (error "cl-weave tests failed"))))

(asdf:defsystem "nshell/weave"
  :version "0.4.0"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/nshell"
  :bug-tracker "https://github.com/nerima-lisp/nshell/issues"
  :source-control (:git "https://github.com/nerima-lisp/nshell.git")
  :description
  "cl-weave regression suite for nshell: property-based, fixture, benchmark,
and cl-prolog-kit-query coverage of the completion engine, complementing the
primary suite in nshell/test."
  :depends-on ("nshell" "cl-weave" "cl-prolog-kit" "cl-prolog-kit/weave")
  :pathname "t"
  :serial t
  :components
  ((:file "weave/package")
   (:file "weave/support")
   (:file "weave/completion-logic")
   (:file "weave/completion-advanced")
   (:file "weave/completion-properties")
   (:file "weave/logic-crosscheck")
   (:file "weave/entry"))
  ;; See the "nshell/test" :perform above for why this is FIND-SYMBOL rather
  ;; than any PKG:SYMBOL-CALL form.
  :perform (asdf:test-op (o s)
             (declare (ignore o s))
             (unless (funcall (find-symbol "RUN" (find-package "NSHELL/WEAVE"))
                              :reporter :spec)
               (error "cl-weave suite failed"))))
(asdf:defsystem "nshell/benchmark"
  :version "0.4.0"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :description "Reproducible public completion API benchmarks for nshell."
  :depends-on ("nshell" "cl-host-kit")
  :pathname "bench"
  :serial t
  :components ((:file "package")
               (:file "completion")
               (:file "process")))

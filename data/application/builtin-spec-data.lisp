(in-package #:nshell.application)

(defparameter +abbr-position-specs+
  '(("command" . :command)
    ("anywhere" . :anywhere)))

(defparameter +builtin-registry-specs+
  '(("alias" . %builtin-alias)
    ("abbr" . %builtin-abbr)
    ("bg" . %builtin-bg)
    ("break" . %builtin-break)
    ("cd" . %builtin-cd)
    ("command" . %builtin-command)
    ("complete" . %builtin-complete)
    ("contains" . %builtin-contains)
    ("continue" . %builtin-continue)
    ("count" . %builtin-count)
    ("disown" . %builtin-disown)
    ("eval" . %builtin-eval)
    ("exec" . %builtin-exec)
    ("export" . %builtin-export)
    ("false" . %builtin-false)
    ("fg" . %builtin-fg)
    ("function" . %builtin-function)
    ("help" . %builtin-help)
    ("history" . %builtin-history)
    ("jobs" . %builtin-jobs)
    ("kill" . %builtin-kill)
    ("pipeline-graph" . %builtin-pipeline-graph)
    ("echo" . %builtin-echo)
    ("printf" . %builtin-printf)
    ("exit" . %builtin-exit)
    ("not" . %builtin-not)
    ("pwd" . %builtin-pwd)
    ("read" . %builtin-read)
    ("seq" . %builtin-seq)
    ("set" . %builtin-set)
    ("unset" . %builtin-unset)
    ("source" . %builtin-source)
    ("." . %builtin-source)
    ("string" . %builtin-string-dispatch)
    ("test" . %builtin-test)
    ("[" . %builtin-bracket)
    ("true" . %builtin-true)
    ("type" . %builtin-type)
    ("wait" . %builtin-wait)
    ("which" . %builtin-which)))

(defparameter +complete-option-specs+
  '(("-c" :kind :command :requirement "command")
    ("--command" :kind :command :requirement "command")
    ("-f" :kind :flag :requirement "flag")
    ("--flag" :kind :flag :requirement "flag")
    ("-l" :kind :long-option :requirement "option")
    ("--long-option" :kind :long-option :requirement "option")
    ("-s" :kind :short-option :requirement "option")
    ("--short-option" :kind :short-option :requirement "option")
    ("-a" :kind :arguments :requirement "arguments")
    ("--arguments" :kind :arguments :requirement "arguments")
    ("-d" :kind :description :requirement "description")
    ("--description" :kind :description :requirement "description")
    ("-e" :kind :erase)
    ("--erase" :kind :erase)))

(defparameter +builtin-string-subcommand-specs+
  '((:name "collect" :handler %builtin-string-collect :manipulation-p t)
    (:name "length" :handler %builtin-string-length)
    (:name "lower" :handler %builtin-string-lower)
    (:name "upper" :handler %builtin-string-upper)
    (:name "join" :handler %builtin-string-join)
    (:name "split" :handler %builtin-string-split)
    (:name "replace" :handler %builtin-string-replace :manipulation-p t)
    (:name "match" :handler %builtin-string-match :manipulation-p t)
    (:name "repeat" :handler %builtin-string-repeat :manipulation-p t)
    (:name "sub" :handler %builtin-string-sub :manipulation-p t)
    (:name "trim" :handler %builtin-string-trim)))

(defparameter +string-replace-flag-option-specs+
  '((:name quiet :short "-q" :long "--quiet")
    (:name all :short "-a" :long "--all")
    (:name ignore-case :short "-i" :long "--ignore-case")))

(defparameter +string-match-flag-option-specs+
  '((:name quiet :short "-q" :long "--quiet")
    (:name ignore-case :short "-i" :long "--ignore-case")))

(defparameter +string-collect-flag-option-specs+
  '((:name allow-empty :short "--allow-empty" :long "--allow-empty")
    (:name no-newline :short "-N" :long "--no-newline")))

(defparameter +string-repeat-flag-option-specs+
  '((:name quiet :short "-q" :long "--quiet")
    (:name no-newline :short "-N" :long "--no-newline")))

(defparameter +string-sub-flag-option-specs+
  '((:name quiet :short "-q" :long "--quiet")))

(defparameter +string-repeat-integer-option-specs+
  '((:name count
       :short "-n"
       :long "--count"
       :kind :required
       :short-prefix-length 2
       :long-prefix-length 8)
    (:name max
       :short "-m"
       :long "--max"
       :kind :prefixed
       :short-prefix-length 2
       :long-prefix-length 6)))

(defparameter +string-sub-integer-option-specs+
  '((:name start
     :short "-s"
     :long "--start"
     :kind :prefixed
     :short-prefix-length 2
     :long-prefix-length 8)
    (:name length
     :short "-l"
     :long "--length"
     :kind :prefixed
     :short-prefix-length 2
     :long-prefix-length 9)
    (:name end
     :short "-e"
     :long "--end"
     :kind :prefixed
     :short-prefix-length 2
     :long-prefix-length 6)))

(defparameter +builtin-contains-usage-clauses+
  '("contains [-i|--index] string [values...]"))

(defparameter +contains-option-specs+
  '(("-i" :index-p t)
    ("--index" :index-p t)))

(defparameter +builtin-history-usage-clauses+
  ;; One clause, assembled rather than written as a literal inside a quoted
  ;; list: it is longer than 100 columns and a string cannot be split across
  ;; source lines.
  (list (concatenate 'string
                     "history [search [--prefix|--contains|--exact|--case-sensitive] query"
                     " | delete command | clear | size]")))

(defparameter +history-search-option-specs+
  '(("--prefix" :mode :prefix)
    ("--contains" :mode :contains)
    ("--exact" :mode :exact)
    ("--case-sensitive" :case-sensitive t)))

(defparameter +history-subcommand-specs+
  '(("search" :handler %history-search)
    ("delete" :handler %history-delete)
    ("clear" :handler %history-clear)
    ("size" :handler %history-size)))

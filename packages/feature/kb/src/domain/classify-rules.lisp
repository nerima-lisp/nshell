(in-package #:nshell.feature.kb)

;;; Built-in safety rules (proposal/06 A) and the command effect model
;;; (proposal/06 B), as one data file.  The PROLOG macro compiles these
;;; clauses into the image at build time (D-65).
;;;
;;; classify(Subject, Level, Rule, Text) holds for every rule that applies;
;;; the evaluator collects them all with findall, takes the highest level, and
;;; reports every rule at that level (D-79).  Levels are :SAFE < :CONFIRM <
;;; :BLOCK.  Only this rulebase may produce :BLOCK; user rules are evaluated in
;;; a separate rulebase and capped at :CONFIRM (D-80).
;;;
;;; The evaluator describes one simple command as facts about SUBJECT:
;;;   command(S, Basename)     invoked-as(S, Word)    arguments(S, List)
;;;   argument(S, Word)        subcommand(S, Word)    option(S, Word)
;;;   operand(S, Word)         word(S, Word)
;;; ARGUMENTS are argv after the command word, with the redirects split off.
;;; WORD holds every word as written, redirect targets included.  From the
;;; redirects in the AST it adds
;;;   redirect(S, Target)               an output redirect target
;;;   redirect-not-allowed(S, Text)     a redirect outside the safe forms
;;; and from matching the arguments against +safe-command-specs+ (2.2)
;;;   spec-command(S)                   the command word has a spec row
;;;   spec-match(S)                     every argument matched it
;;;   argument-not-allowed(S, Text)     the words that did not match
;;; and the results it obtained by classifying embedded command text:
;;;   wraps(S)                       S runs another command (2.4)
;;;   opaque-wrapper(S)              ... and what that command sees is opaque
;;;   shell-function(S)              the executor resolves S to a function
;;;   nested(S, Level, Rule, Text)   from that command or a substitution
;;;   embedded(S, Level, Rule, Text) from a known command name in the operands
;;;   unparsable(S, Text)            text that could not be read as a command
;;; S-expression proposals add form-redirect(S), sexp-unforced(S), and
;;; unclassifiable(S, Text).  A command run with environment assignments
;;; (`NAME=value cmd', `env NAME=value cmd') adds assignment(S, Name) per
;;; name and wrapper-option(S, Option) per option given to env.

(defparameter +safe-command-specs+
  '(;; --- read-only commands (D-P1-5 2.6) -----------------------------------
    ;; A row matches the command word exactly (a path such as /bin/ls does
    ;; not).  Keys: :flags (short options without a value), :value-flags,
    ;; :long, :value-long, :exact (whole words), :positionals (:any or a
    ;; maximum), :listing-options (options that allow any operands),
    ;; :plus-options (reject + words as unsupported options before --),
    ;; :subcommands, and :grammar for find and echo/printf.  :resolution
    ;; :builtin marks a row that describes the nshell builtin of that name;
    ;; it applies only when the executor resolves the name to the builtin,
    ;; never to a forced (^name) command.  Other rows describe external
    ;; programs.
    ("ls" :flags "1aAlhdFRtSrin" :long ("--all" "--color")
          :exact ("--color=auto" "--color=never" "--color=always")
          :positionals :any)
    ("cat" :flags "nbvets" :positionals :any)
    ("pwd" :positionals 0 :resolution :builtin)
    ("which" :positionals :any :resolution :builtin)
    ("type" :positionals :any :resolution :builtin)
    ("command" :flags "vV" :positionals :any :resolution :builtin)
    ("head" :value-flags (("n" :count) ("c" :count)) :positionals :any)
    ("tail" :value-flags (("n" :count) ("c" :count))
            :plus-options t :positionals :any)
    ("wc" :flags "lwcm" :positionals :any)
    ("stat" :flags "L" :positionals :any)
    ("du" :flags "shkacx" :value-flags (("d" :count)) :positionals :any)
    ("df" :flags "hkliP" :positionals :any)
    ("file" :flags "bLhks" :long ("--mime-type" "--mime-encoding")
            :positionals :any)
    ("grep" :flags "ivnclLrREFwxohHsqz"
            :value-flags (("A" :count) ("B" :count) ("C" :count) ("e" :any)
                          ("f" :any))
            :long ("--color")
            :exact ("--color=auto" "--color=never" "--color=always")
            :value-long (("--include" :any) ("--exclude" :any))
            :positionals :any)
    ("rg" :flags "iSsvnNclLwxFoHu."
          :value-flags (("e" :any) ("g" :any) ("t" :any) ("T" :any)
                        ("A" :count) ("B" :count) ("C" :count) ("m" :count))
          :long ("--hidden" "--no-ignore" "--files" "--json")
          :exact ("--color=auto" "--color=never" "--color=always")
          :value-long (("--glob" :any) ("--type" :any))
          :positionals :any)
    ("find" :grammar :find
            :leading-options ("-H" "-L" "-P" "-x")
            :primaries ("-empty" "-prune" "-print" "-print0" "-ls" "-not" "!"
                        "-o" "-a" "(" ")")
            :value-primaries ("-name" "-iname" "-path" "-ipath" "-type"
                              "-maxdepth" "-mindepth" "-mtime" "-mmin" "-newer"
                              "-size" "-perm" "-user"))
    ;; The echo and printf builtins (2.1 item 8); a forced (^echo) runs the
    ;; external program, which no row describes.
    ("echo" :grammar :echo :resolution :builtin)
    ("printf" :grammar :echo :resolution :builtin)
    ("git" :subcommands
           (("status" :flags "sbv"
                      :exact ("-u" "-uno" "-unormal" "-uall"
                              "--porcelain=v1" "--porcelain=v2")
                      :long ("--short" "--branch" "--porcelain" "--long"
                             "--verbose" "--ignored")
                      :positionals :any)
            ("log" :flags "p" :value-flags (("n" :count))
                   :long ("--oneline" "--decorate" "--stat" "--name-only"
                          "--name-status" "--graph" "--all" "--follow"
                          "--no-merges")
                   :value-long (("--pretty" :git-format) ("--format" :git-format))
                   :positionals :any)
            ("show" :flags "p"
                    :long ("--stat" "--patch" "--name-only" "--name-status"
                           "--no-patch")
                    :value-long (("--pretty" :git-format) ("--format" :git-format))
                    :positionals :any)
            ("diff" :flags "p"
                    :long ("--stat" "--shortstat" "--numstat" "--cached"
                           "--staged" "--name-only" "--name-status" "--patch"
                           "--no-ext-diff" "--no-textconv")
                    :positionals :any)
            ;; An operand creates a branch unless --list makes it a pattern.
            ("branch" :flags "arv" :long ("--list" "--show-current")
                      :positionals 0 :listing-options ("--list"))
            ("remote" :flags "v" :long ("--verbose") :positionals 0)))
    ;; --- wrappers (2.4) ----------------------------------------------------
    ;; A transparent wrapper written as a bare name reads its own options
    ;; with the row; its command is then classified as argv.  Written as a
    ;; path it is opaque.  An opaque wrapper is confirm at least; its command
    ;; is classified only to find a block.  :skip-values names the short
    ;; options whose value follows them when the wrapper's command is looked
    ;; for; :operands counts the wrapper's own operands before the command.
    ;; :runs :by-name says the wrapper resolves its command like a typed
    ;; one (builtin first); otherwise the command it runs is external.
    ("nice" :wrapper :transparent :value-flags (("n" :count)))
    ("timeout" :wrapper :transparent :value-flags (("s" :any) ("k" :any))
               :operands 1)
    ("time" :wrapper :transparent :flags "p" :skip-values "of")
    ;; env with any option is opaque.
    ("env" :wrapper :transparent :assignments t :opaque-on-options t
           :skip-values "uCS")
    ;; Builtins that run their first argument by name, like a typed command.
    ("and" :wrapper :transparent :resolution :builtin :runs :by-name)
    ("or" :wrapper :transparent :resolution :builtin :runs :by-name)
    ("not" :wrapper :transparent :resolution :builtin :runs :by-name)
    ("sudo" :wrapper :opaque :assignments t :skip-values "ugCDhpRrTUt")
    ("doas" :wrapper :opaque :skip-values "uC")
    ("xargs" :wrapper :opaque :skip-values "ILnPsdEa")
    ("nohup" :wrapper :opaque)
    ;; The exec builtin runs the external program; builtin runs a builtin.
    ("exec" :wrapper :opaque :skip-values "a" :resolution :builtin)
    ("builtin" :wrapper :opaque :resolution :builtin :runs :by-name)
    ;; Queries may autoload a function; the classifier checks each target first.
    ("command" :wrapper :opaque :query-options ("-v" "-V") :resolution :builtin
               :runs :by-name)
    ;; The command is source text: eval with one argument, or sh -c SCRIPT.
    ("eval" :wrapper :opaque :source :eval :resolution :builtin)
    ("sh" :wrapper :opaque :source :dash-c)
    ("bash" :wrapper :opaque :source :dash-c)
    ("zsh" :wrapper :opaque :source :dash-c)
    ("fish" :wrapper :opaque :source :dash-c))
  "The closed-world allow list (D-P1-5 2.2).  A command is safe only when
its row matches every argument; anything else is confirm.  Adding a row
changes no other command.")

(defparameter *builtin-classify-rulebase*
  (cl-prolog-kit:prolog
    ;; --- vocabulary ---------------------------------------------------------
    ;; Names matched as typed.  Read-only commands are the spec table above.
    ((known-command-name "source"))
    ;; Basenames whose own rules always decide them.
    ((covered-command "rm")) ((covered-command "curl"))
    ((network-command "curl")) ((network-command "wget")) ((network-command "ssh"))

    ;; --- effect model (B) ---------------------------------------------------
    ((effect ?c (deletes ?p)) (command ?c "rm") (operand ?c ?p))
    ((effect ?c (writes ?p)) (redirect ?c ?p))
    ((effect ?c :network) (command ?c ?n) (network-command ?n))

    ;; --- derived facts ------------------------------------------------------
    ((flag ?c :recursive)
     (command ?c "rm") (option ?c ?o) (:when (recursive-option-p ?o)))
    ((root-path ?p) (:when (root-path-p ?p)))
    ((harmless-environment-name ?n) (:when (harmless-environment-name-p ?n)))
    ((deletes-root ?c) (effect ?c (deletes ?p)) (root-path ?p))
    ;; The only way to safe: every argument matched the spec (2.1 item 1).
    ((read-only-command ?c) (spec-match ?c))
    ((known-command ?c) (wraps ?c))
    ((known-command ?c) (spec-command ?c))
    ((known-command ?c) (shell-function ?c))
    ((known-command ?c) (invoked-as ?c ?n) (known-command-name ?n))
    ((known-command ?c) (command ?c ?n) (covered-command ?n))

    ;; --- block --------------------------------------------------------------
    ((classify ?c :block "classify/root-recursive-delete"
               "recursive deletion of the filesystem root is blocked")
     (flag ?c :recursive) (deletes-root ?c))
    ((classify ?c :block "classify/unparsable" ?text)
     (unparsable ?c ?text))

    ;; --- confirm ------------------------------------------------------------
    ((classify ?c :confirm "classify/delete-dir" "deletes a directory")
     (flag ?c :recursive) (not (deletes-root ?c)))
    ((classify ?c :confirm "classify/delete" "deletes files")
     (command ?c "rm") (not (flag ?c :recursive)))
    ((classify ?c :confirm "classify/force-push"
               "a force push can rewrite the remote history")
     (command ?c "git") (subcommand ?c "push")
     (argument ?c ?a) (:when (force-push-option-p ?a)))
    ((classify ?c :confirm "classify/git-not-read-only"
               "writing, external command execution, or configuration injection requires confirmation")
     (invoked-as ?c "git") (not (read-only-command ?c)))
    ((classify ?c :confirm "classify/argument-not-allowed" ?text)
     (argument-not-allowed ?c ?text) (not (invoked-as ?c "git")))
    ;; A shell function's body runs under its own gate and cannot use the
    ;; line's approval (D-P1-5 3.1 item 5); the call itself is opaque.
    ((classify ?c :confirm "classify/shell-function"
               "a shell function runs commands this line does not show")
     (shell-function ?c))
    ((classify ?c :confirm "classify/opaque-wrapper"
               "the command this wrapper runs cannot be checked")
     (opaque-wrapper ?c))
    ((classify ?c :confirm "classify/device-write"
               "writing a device can destroy data")
     (command ?c "dd") (argument ?c ?a) (:when (string-prefix-p "of=/dev/" ?a)))
    ((classify ?c :confirm "classify/network"
               "network retrieval requires confirmation before it can feed a shell")
     (effect ?c :network))
    ((classify ?c :confirm "classify/source"
               "sourcing a file can execute commands and requires confirmation")
     (invoked-as ?c "source"))
    ((classify ?c :confirm "classify/unknown-command" "unknown command")
     (command ?c ?n) (not (known-command ?c)))
    ((classify ?c :confirm "classify/backtick"
               "backtick command substitution requires confirmation")
     (invoked-as ?c ?w) (:when (contains-p "`" ?w)))
    ((classify ?c :confirm "classify/backtick"
               "backtick command substitution requires confirmation")
     (word ?c ?w) (:when (contains-p "`" ?w)))
    ((classify ?c :confirm "classify/output-redirect"
               "output redirection or process substitution requires confirmation")
     (redirect-not-allowed ?c ?text))
    ((classify ?c :confirm "classify/environment-assignment"
               "assigning this environment variable can change what the command runs")
     (assignment ?c ?n) (not (harmless-environment-name ?n)))
    ((classify ?c :confirm "classify/env-option"
               "env options can change the environment the command runs in")
     (wrapper-option ?c ?o))
    ((classify ?c :confirm "classify/form-redirect"
               "Reader-result redirects require confirmation")
     (form-redirect ?c))
    ((classify ?c :confirm "classify/sexp-not-forced"
               "S-expression command requires explicit force and has no redirects")
     (sexp-unforced ?c))
    ((classify ?c :confirm "classify/unclassifiable-form" ?text)
     (unclassifiable ?c ?text))

    ;; --- safe ---------------------------------------------------------------
    ((classify ?c :safe "classify/read-only" "read-only known command")
     (read-only-command ?c))
    ;; A line of assignments only runs no command; the names decide (2.4), and
    ;; any name outside the harmless table raises it to confirm above.
    ((classify ?c :safe "classify/harmless-assignment"
               "assigns only harmless environment names")
     (assignment ?c ?n) (not (command ?c ?m)))

    ;; --- embedded commands keep the rule that classified them ---------------
    ((classify ?c ?level ?rule ?text) (nested ?c ?level ?rule ?text))
    ((classify ?c ?level ?rule ?text)
     (embedded ?c ?level ?rule ?text) (not (known-command ?c)))))

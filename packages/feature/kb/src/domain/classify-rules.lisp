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
;;;   operand(S, Word)         redirect(S, Target)
;;; and the results it obtained by classifying embedded command text:
;;;   wraps(S)                       a wrapper, eval, or sh -c target was read
;;;   nested(S, Level, Rule, Text)   from that target or a substitution
;;;   embedded(S, Level, Rule, Text) from a known command name in the operands
;;;   unparsable(S, Text)            text that could not be read as a command
;;; S-expression proposals add form-redirect(S), sexp-unforced(S), and
;;; unclassifiable(S, Text).  A command run with environment assignments
;;; (`NAME=value cmd', `env NAME=value cmd') adds assignment(S, Name) per
;;; name and wrapper-option(S, Option) per option given to env.

(defparameter *builtin-classify-rulebase*
  (cl-prolog-kit:prolog
    ;; --- vocabulary ---------------------------------------------------------
    ((read-only-name "ls")) ((read-only-name "pwd")) ((read-only-name "cat"))
    ((read-only-name "head")) ((read-only-name "tail")) ((read-only-name "wc"))
    ((read-only-name "stat")) ((read-only-name "file")) ((read-only-name "du"))
    ((read-only-name "df")) ((read-only-name "which")) ((read-only-name "type"))
    ((read-only-name "grep")) ((read-only-name "rg")) ((read-only-name "find"))
    ((read-only-name "echo")) ((read-only-name "printf"))
    ;; Names matched as typed (a path such as /tmp/x/ls is not read-only).
    ((known-command-name "git")) ((known-command-name "source"))
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
    ((read-only-command ?c) (invoked-as ?c ?n) (read-only-name ?n))
    ((read-only-command ?c)
     (invoked-as ?c "git") (arguments ?c ?args)
     (:when (read-only-git-arguments-p ?args)))
    ((known-command ?c) (wraps ?c))
    ((known-command ?c) (read-only-command ?c))
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
     (argument ?c ?w) (:when (contains-p "`" ?w)))
    ((classify ?c :confirm "classify/output-redirect"
               "output redirection or process substitution requires confirmation")
     (argument ?c ?w) (:when (contains-p ">" ?w)))
    ((classify ?c :confirm "classify/find-exec"
               "find actions can execute commands and require confirmation")
     (invoked-as ?c "find") (argument ?c ?w) (:when (find-exec-action-p ?w)))
    ((classify ?c :confirm "classify/find-write"
               "find actions can write files and require confirmation")
     (invoked-as ?c "find") (argument ?c ?w) (:when (find-write-action-p ?w)))
    ((classify ?c :confirm "classify/ripgrep-preprocessor"
               "ripgrep can execute external preprocessors and requires confirmation")
     (invoked-as ?c "rg") (argument ?c ?w) (:when (ripgrep-preprocessor-option-p ?w)))
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

    ;; --- embedded commands keep the rule that classified them ---------------
    ((classify ?c ?level ?rule ?text) (nested ?c ?level ?rule ?text))
    ((classify ?c ?level ?rule ?text)
     (embedded ?c ?level ?rule ?text) (not (known-command ?c)))))

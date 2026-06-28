(in-package #:nshell.domain.completion)

(defstruct fact
  (predicate nil :type symbol :read-only t)
  (args '() :type list :read-only t))

(defstruct rule
  (head '() :type list :read-only t)
  (body '() :type list :read-only t))

(defstruct (rule-knowledge-base (:constructor make-rule-knowledge-base (&key (facts nil) (rules nil))))
  (facts nil :type list)
  (rules nil :type list))

(defun make-fact-from-spec (spec)
  (make-fact :predicate (first spec) :args (rest spec)))

(defun make-rule-from-spec (spec)
  (make-rule :head (first spec) :body (rest spec)))

(defparameter *max-proof-depth* 32
  "Maximum rule-expansion depth for completion proof search.")

(defparameter +builtin-command-catalog+
  (list
   (list :command "echo"
         :synopsis "echo [string ...]"
         :description "print arguments")
   (list :command "pwd"
         :synopsis "pwd"
         :description "print working directory")
   (list :command "ls"
         :synopsis "ls"
         :description "list directory contents"
         :flags '("-l" "-a" "-h" "-R" "--help"))
   (list :command "cd"
         :synopsis "cd [dir]"
         :description "change directory")
   (list :command "exit"
         :synopsis "exit"
         :description "exit the shell")
   (list :command "fg"
         :synopsis "fg [job-id]"
         :description "bring job to foreground")
   (list :command "bg"
         :synopsis "bg [job-id]"
         :description "resume job in background")
   (list :command "jobs"
         :synopsis "jobs"
         :description "list jobs")
   (list :command "disown"
         :synopsis "disown [job-id]"
         :description "remove job from job list")
   (list :command "set"
         :synopsis "set [-x|--export] name value... | set [-e|--erase] name... | set [-q|--query] name..."
         :description "manage variables"
         :flags '("-x" "--export" "-e" "--erase" "-q" "--query"))
   (list :command "export"
         :synopsis "export name"
         :description "export variable to environment")
   (list :command "alias"
         :synopsis "alias [name expansion...] | alias -e name... | alias -q name..."
         :description "manage aliases")
   (list :command "abbr"
         :synopsis "abbr [-a [-p command|anywhere] name expansion...] [-e name...] [-q name...] [-l] [-s]"
         :description "manage abbreviations"
         :flags '("-a" "--add" "-p" "--position" "command" "anywhere"
                  "-e" "--erase" "-q" "--query" "-l" "--list" "-s" "--show"))
   (list :command "complete"
         :synopsis "complete -c command [-f flag ...] [-l option ...] [-s option ...] [-a arguments] [-d description] [-e]"
         :description "define completions"
         :flags '("-c" "--command" "-f" "--flag" "-l" "--long-option"
                  "-s" "--short-option" "-a" "--arguments" "-d" "--description"
                  "-e" "--erase"))
   (list :command "type"
         :synopsis "type [OPTIONS] NAME [...]"
         :description "show command type"
         :flags '("-a" "--all" "-s" "--short" "-f" "--no-functions"
                  "--color" "-q" "--query" "--quiet" "-p" "--path" "-P" "--force-path"
                  "-t" "--type" "-h" "--help"))
   (list :command "which"
         :synopsis "which NAME [...]"
         :description "show command path")
   (list :command "test"
         :synopsis "test expression"
         :description "evaluate conditional")
   (list :command "["
         :synopsis "[ expression ]"
         :description "evaluate conditional")
   (list :command "string"
         :synopsis "string collect|length|lower|upper|join|split|replace|match|repeat|sub|trim ...; string replace|match|repeat|sub|trim ..."
         :description "manipulate strings"
         :flags '("length" "lower" "upper" "join" "split" "replace" "match"
                  "trim" "-a" "--all" "-q" "--quiet" "-i" "--ignore-case"
                  "--"))
   (list :command "source"
         :synopsis "source file"
         :description "execute commands from file")
   (list :command "."
         :synopsis ". file"
         :description "execute commands from file")
   (list :command "read"
         :synopsis "read [-p prompt] variable"
         :description "read line of input"
         :flags '("-p"))
   (list :command "function"
         :synopsis "function [name body... end] | function -e name... | function -q name..."
         :description "manage functions"
         :flags '("-e" "-q"))
   (list :command "history"
         :synopsis "history [search [--prefix|--contains|--exact|--case-sensitive] query | delete command | clear | size]"
         :description "show and manage command history"
         :flags '("search" "delete" "clear" "size" "--prefix" "--contains" "--exact"
                  "--case-sensitive"))
   (list :command "help"
         :synopsis "help [command]"
         :description "show help")
   (list :command "exec"
         :synopsis "exec command [args...]"
         :description "replace shell with command")
   (list :command "true"
         :synopsis "true"
         :description "return success")
   (list :command "false"
         :synopsis "false"
         :description "return failure")
   (list :command "contains"
         :synopsis "contains [-i|--index] string [values...]"
         :description "test whether a value is present"
         :flags '("-i" "--index" "--"))
   (list :command "count"
         :synopsis "count [values...]"
         :description "print the number of arguments"
         :flags '())
   (list :command "seq"
         :synopsis "seq [FIRST [STEP]] LAST"
         :description "print a sequence of integers"
         :flags '())
   (list :command "not"
         :synopsis "not command [args...]"
         :description "invert command status")))

(defparameter +external-command-catalog+
  (list
   (list :command "git"
         :description "distributed version control"
         :subcommands '((:name "add" :description "stage changes")
                        "branch"
                        (:name "checkout" :description "switch branches or restore paths")
                        "clone"
                        (:name "commit" :description "record changes")
                        "diff" "fetch" "log" "merge" "pull" "push" "rebase"
                        "restore"
                        (:name "status" :description "show working tree status")
                        "switch" "tag")
         :flags '("-C" "-c" "--help" "--version" "--no-pager" "--paginate"))
   (list :command "docker"
         :description "manage containers and images"
         :subcommands '("build" "compose" "exec" "images" "logs" "ps" "pull"
                        "push" "run" "stop")
         :flags '("--config" "--context" "--debug" "--help" "--host" "--log-level"
                  "--tls" "--tlscacert" "--tlscert" "--tlskey" "--version")
         :option-values '(("--log-level" "debug" "info" "warn" "error" "fatal")))
   (list :command "kubectl"
         :description "control Kubernetes clusters"
         :subcommands '("apply" "config" "create" "delete" "describe" "exec" "get"
                        "logs" "patch" "port-forward" "rollout" "scale")
         :flags '("--all-namespaces" "--context" "--help" "--kubeconfig"
                  "--namespace" "-n" "--output" "-o")
         :option-values '(("--output" "json" "yaml" "wide" "name")
                          ("-o" "json" "yaml" "wide" "name"))
         :exclusive-options '(("--all-namespaces" "--namespace" "-n")))
   (list :command "nix"
         :description "Nix package manager"
         :subcommands '("build" "develop" "flake" "fmt" "profile" "repl" "run"
                        "search" "shell" "store")
         :flags '("--accept-flake-config" "--extra-experimental-features" "--help"
                  "--impure" "--print-build-logs" "-L" "--version"))
   (list :command "cargo"
         :description "Rust package manager"
         :subcommands '("build" "check" "clean" "clippy" "doc" "fmt" "run" "test"
                        "update")
         :flags '("--color" "--help" "--manifest-path" "--offline" "--quiet" "-q"
                  "--verbose" "-v" "--version")
         :option-values '(("--color" "auto" "always" "never"))
         :exclusive-options '(("--quiet" "-q" "--verbose" "-v")))
   (list :command "npm"
         :description "JavaScript package manager"
         :subcommands '("ci" "install" "link" "publish" "run" "test" "update"
                        "version")
         :flags '("--help" "--global" "-g" "--prefix" "--silent" "--verbose"
                  "--version"))
   (list :command "grep"
         :description "search text by pattern"
         :flags '("-E" "-F" "-H" "-I" "-R" "-i" "-n" "-q" "-r" "-v" "--color"
                  "--exclude" "--exclude-dir" "--help")
         :option-values '(("--color" "auto" "always" "never"))
         :exclusive-options '(("-E" "-F")))
   (list :command "find"
         :description "walk files matching expressions"
         :flags '("-L" "-H" "-P" "-name" "-iname" "-type" "-maxdepth" "-mindepth"
                  "-print" "-exec" "-delete"))
   (list :command "tar"
         :description "archive files"
         :flags '("-c" "-x" "-t" "-f" "-v" "-z" "-j" "-J" "--create" "--extract"
                  "--file" "--gzip" "--help"))
   (list :command "ssh"
         :description "OpenSSH remote login"
         :flags '("-A" "-F" "-J" "-L" "-N" "-R" "-T" "-V" "-i" "-l" "-p" "-v"))))

(defun builtin-command-flag-facts ()
  "Return static flag facts derived from the builtin command catalog."
  (mapcan (lambda (entry)
            (let ((command (getf entry :command))
                  (flags (getf entry :flags)))
              (mapcar (lambda (flag)
                        (list 'has-flag command flag))
                      flags)))
          +builtin-command-catalog+))

(defun catalog-subcommand-name (subcommand)
  (if (consp subcommand)
      (getf subcommand :name)
      subcommand))

(defun catalog-subcommand-description (subcommand)
  (when (consp subcommand)
    (getf subcommand :description)))

(defun external-command-rule-facts ()
  "Return static command, subcommand, and flag facts for common external commands."
  (mapcan (lambda (entry)
            (let ((command (getf entry :command))
                  (description (getf entry :description))
                  (subcommands (getf entry :subcommands))
                  (flags (getf entry :flags)))
              (append (list (list 'completes command command)
                            (list 'describes command description))
                      (mapcar (lambda (subcommand)
                                (list 'completes command
                                      (catalog-subcommand-name subcommand)))
                              subcommands)
                      (mapcan (lambda (subcommand)
                                (let ((name (catalog-subcommand-name subcommand))
                                      (description (catalog-subcommand-description subcommand)))
                                  (when description
                                    (list (list 'describes name description)))))
                              subcommands)
                      (mapcar (lambda (flag)
                                (list 'has-flag command flag))
                              flags))))
          +external-command-catalog+))

(defparameter +command-path-builtin-specs+
  '(("type"
     :builtin-format "~a is a shell builtin~%"
     :path-format "~a is ~a~%"
     :missing-prefix "type"
     :missing-format "~a: not found~%"
     :usage "type [OPTIONS] NAME [...]")
    ("which"
     :builtin-format "~a: shell built-in command~%"
     :path-format "~a~%"
     :missing-prefix "which"
     :missing-format "no ~a in PATH"
     :usage "which NAME [NAME ...]")))

(defparameter +type-builtin-spec+
  '(:alias-format "~a is an alias for ~a~%"
    :function-format "~a is a function~%"
    :abbreviation-format "~a is an abbreviation for ~a~%"
    :builtin-format "~a is a shell builtin~%"
    :path-builtin-format "~a is a builtin~%"
    :path-format "~a is ~a~%"
    :path-only-format "~a~%"
    :missing-format "~a: not found~%"
    :usage "type [OPTIONS] NAME [...]"))

(defun builtin-help-entries ()
  "Return the canonical builtin help entries."
  (mapcar (lambda (entry)
            (list :command (getf entry :command)
                  :synopsis (getf entry :synopsis)
                  :description (getf entry :description)))
          +builtin-command-catalog+))

(defun completion-command-specs-from-catalog (catalog)
  (mapcar (lambda (entry)
            (let ((command (getf entry :command))
                  (subcommands (getf entry :subcommands))
                  (flags (getf entry :flags))
                  (option-values (getf entry :option-values))
                  (exclusive-options (getf entry :exclusive-options))
                  (description (getf entry :description)))
              (append (list command)
                      (when subcommands
                        (list :subcommands
                              (mapcar #'catalog-subcommand-name subcommands)))
                      (when flags (list :flags flags))
                      (when option-values (list :option-values option-values))
                      (when exclusive-options
                        (list :exclusive-options exclusive-options))
                      (when description (list :description description)))))
          catalog))

(defun builtin-completion-command-specs ()
  "Return the canonical REPL completion seed derived from builtin help entries."
  (completion-command-specs-from-catalog +builtin-command-catalog+))

(defun external-completion-command-specs ()
  "Return completion-only seed data for common external commands."
  (completion-command-specs-from-catalog +external-command-catalog+))

(defun builtin-rule-facts ()
  "Return the static facts used to seed builtin completion knowledge."
  (append
   '((command-is "cd" "cd")
     (command-is "source" "source")
     (command-is "." "source"))
   (mapcan (lambda (entry)
             (let ((command (getf entry :command))
                   (description (getf entry :description)))
               (list (list 'completes command command)
                     (list 'describes command description))))
           +builtin-command-catalog+)
   (builtin-command-flag-facts)
   (external-command-rule-facts)
   '((describes "--help" "show command help"))))

(defun builtin-rule-rules ()
  "Return the static rule forms used by the builtin completion knowledge base."
  '(((suggests-dir ?input)
     (command-is ?input "cd"))
    ((completes ?cmd "--help")
     (has-flag ?cmd "--help"))
    ((completes ?cmd ?flag)
     (has-flag ?cmd ?flag))
    ((suggests-file ?input)
     (command-is ?input "source"))))

(defgeneric predicate-true-p (predicate args bindings)
  (:documentation "Return true when PREDICATE with walked ARGS is true in the current environment."))

(defmethod predicate-true-p ((predicate symbol) args bindings)
  (declare (ignore predicate args bindings))
  nil)

(defun assert-fact! (kb fact)
  (push fact (rule-knowledge-base-facts kb))
  kb)

(defun assert-rule! (kb rule)
  (push rule (rule-knowledge-base-rules kb))
  kb)

(defun logic-variable-symbol-p (x)
  (and (symbolp x)
       (< 0 (length (symbol-name x)))
       (char= #\? (char (symbol-name x) 0))))

(defun variable-name (symbol)
  (subseq (symbol-name symbol) 1))

(defun convert-logic-variables (form env)
  (cond
    ((logic-variable-symbol-p form)
     (or (gethash form env)
         (setf (gethash form env)
               (nshell.domain.parsing:make-var (variable-name form)))))
    ((consp form)
     (cons (convert-logic-variables (car form) env)
           (convert-logic-variables (cdr form) env)))
    (t form)))

(defun fact-head (fact env)
  (convert-logic-variables (cons (fact-predicate fact) (fact-args fact)) env))

(defun rule-head-term (rule env)
  (convert-logic-variables (rule-head rule) env))

(defun rule-body-terms (rule env)
  (mapcar (lambda (goal) (convert-logic-variables goal env))
          (rule-body rule)))

(defun prove-body (kb goals bindings depth)
  (if (null goals)
      (list bindings)
      (loop for solution in (prove-internal kb (first goals) bindings depth)
            append (prove-body kb (rest goals) solution depth))))

(defun prove-built-in-solutions (goal bindings)
  (let* ((predicate (first goal))
         (args (mapcar (lambda (arg) (nshell.domain.parsing:walk arg bindings))
                       (rest goal))))
    (when (predicate-true-p predicate args bindings)
      (list bindings))))

(defun prove-internal (kb goal bindings depth)
  (let ((solutions '()))
    (dolist (fact (rule-knowledge-base-facts kb))
      (let ((candidate (nshell.domain.parsing:unify goal (fact-head fact (make-hash-table :test #'eq)) bindings)))
        (when (nshell.domain.parsing:unify-p candidate)
          (push candidate solutions))))
    (when (plusp depth)
      (dolist (rule (rule-knowledge-base-rules kb))
        (let* ((env (make-hash-table :test #'eq))
               (head (rule-head-term rule env))
               (body (rule-body-terms rule env))
               (head-bindings (nshell.domain.parsing:unify goal head bindings)))
          (when (nshell.domain.parsing:unify-p head-bindings)
            (setf solutions
                  (append (prove-body kb body head-bindings (1- depth))
                          solutions))))))
    (append (nreverse solutions)
            (prove-built-in-solutions goal bindings))))

(defun externalize-bindings (env bindings)
  (let ((result '()))
    (maphash (lambda (symbol var)
               (let ((value (nshell.domain.parsing:walk var bindings)))
                 (unless (nshell.domain.parsing:var-p value)
                   (push (cons symbol value) result))))
             env)
    (nreverse result)))

(defun prove (kb goal &optional (bindings '()) (max-depth *max-proof-depth*))
  (let* ((env (make-hash-table :test #'eq))
         (internal-goal (convert-logic-variables goal env)))
    (mapcar (lambda (solution)
              (externalize-bindings env solution))
            (prove-internal kb internal-goal bindings max-depth))))

(defun prove-all (kb goal &key (max-depth *max-proof-depth*))
  (prove kb goal '() max-depth))

(defparameter *built-in-rule-knowledge-base*
  (make-rule-knowledge-base
   :facts (mapcar #'make-fact-from-spec
                  (builtin-rule-facts))
   :rules (mapcar #'make-rule-from-spec
                  (builtin-rule-rules))))

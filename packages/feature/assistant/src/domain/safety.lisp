(in-package #:nshell.feature.assistant)

(defstruct (assistant-safety-rule
            (:constructor make-assistant-safety-rule
                (&key name classification command condition reason)))
  name
  classification
  command
  condition
  reason)

(defstruct (assistant-safety-result
            (:constructor make-assistant-safety-result
                (&key classification reason command rule-name)))
  classification
  reason
  command
  rule-name)

;; These are data expressions, not model output. New static rules belong here so
;; adding a safety decision does not require changing the classifier algorithm.
(defparameter +assistant-safety-rules+
  (list
   (make-assistant-safety-rule
    :name :root-recursive-delete
    :classification :block
    :command "rm"
    :condition '(:all (:any (:arg-equals "/")
                            (:arg-equals "/*")
                            (:arg-equals "~")
                            (:arg-equals "$HOME")
                            (:arg-equals "."))
                 (:any (:arg-prefix "-r") (:arg-equals "--recursive")))
    :reason "recursive deletion of the filesystem root is blocked")
   (make-assistant-safety-rule
    :name :destructive-delete
    :classification :confirm
    :command "rm"
    :condition :always
    :reason "deletion requires confirmation")
   (make-assistant-safety-rule
    :name :force-git-push
    :classification :confirm
    :command "git"
    :condition '(:all (:subcommand-equals "push")
                 (:any (:arg-equals "-f") (:arg-prefix "--force")))
    :reason "a force push can rewrite the remote history")
   (make-assistant-safety-rule
    :name :device-write
    :classification :confirm
    :command "dd"
    :condition '(:arg-prefix "of=/dev/")
    :reason "writing a device can destroy data")
   (make-assistant-safety-rule
    :name :network-to-shell
    :classification :confirm
    :command "curl"
    :condition :always
    :reason "network retrieval requires confirmation before it can feed a shell")
   (make-assistant-safety-rule
    :name :safe-list
    :classification :safe
    :command "pwd"
    :condition :always
    :reason "listing files does not write to the filesystem")
   (make-assistant-safety-rule
    :name :safe-search
    :classification :safe
    :command "cat"
    :condition :always
    :reason "searching text does not write to the filesystem")
   )
  "Static AST safety rules, ordered from specific dangerous cases to safe cases.")

(defparameter +assistant-safe-command-names+
  '("ls" "pwd" "cat" "head" "tail" "wc" "stat" "file" "du" "df"
    "which" "type" "grep" "rg" "find" "echo" "printf")
  "Commands that may be classified safe when no output-producing escape hatch is present.")

(defun %assistant-string-prefix-p (prefix string)
  (and (stringp string)
       (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun %assistant-condition-p (condition args)
  (cond
    ((eq condition :always) t)
    ((and (consp condition) (eq (first condition) :all))
     (every (lambda (part) (%assistant-condition-p part args)) (rest condition)))
    ((and (consp condition) (eq (first condition) :any))
     (some (lambda (part) (%assistant-condition-p part args)) (rest condition)))
    ((and (consp condition) (eq (first condition) :arg-equals))
     (member (second condition) args :test #'string=))
    ((and (consp condition) (eq (first condition) :arg-prefix))
     (some (lambda (arg)
             (%assistant-string-prefix-p (second condition) arg))
           args))
    ((and (consp condition) (eq (first condition) :subcommand-equals))
     (and (first args) (string= (second condition) (first args))))
    (t nil)))

(defun %assistant-rule-for (command args)
  (find-if (lambda (rule)
             (and (string= command (assistant-safety-rule-command rule))
                  (%assistant-condition-p
                   (assistant-safety-rule-condition rule)
                   args)))
           +assistant-safety-rules+))

(defun %assistant-unsafe-argument-reason (command args)
  (cond
    ((or (search "`" command)
         (some (lambda (arg) (search "`" arg)) args))
     "backtick command substitution requires confirmation")
    ((some (lambda (arg) (search ">" arg)) args)
     "output redirection or process substitution requires confirmation")
    ((and (string= command "find")
          (some (lambda (arg)
                  (or (member arg '("-delete" "-exec" "-ok" "-execdir" "-okdir")
                              :test #'string=)
                      (some (lambda (prefix)
                              (%assistant-string-prefix-p prefix arg))
                            '("-fprint" "-fprintf" "-fls"))))
                args))
     (if (some (lambda (arg)
                 (member arg '("-exec" "-ok" "-execdir" "-okdir")
                         :test #'string=))
               args)
         "find actions can execute commands and require confirmation"
         "find actions can write files and require confirmation"))
    ((and (string= command "rg")
          (some (lambda (arg)
                  (or (%assistant-string-prefix-p "--pre" arg)
                      (string= arg "--search-zip")))
                args))
     "ripgrep can execute external preprocessors and requires confirmation")
    (t nil)))

(defun %assistant-unsafe-argument-p (command args)
  (not (null (%assistant-unsafe-argument-reason command args))))

(defun %assistant-parenthesized-substitution-texts (value marker)
  (let ((results nil)
        (start 0))
    (loop
      (let ((opening (search marker value :start2 start)))
        (unless opening
          (return (nreverse results)))
        (let ((depth 1)
              (position (+ opening (length marker))))
          (loop while (and (< position (length value)) (plusp depth))
                do (let ((character (char value position)))
                     (cond
                       ((char= character (code-char 40)) (incf depth))
                       ((char= character (code-char 41)) (decf depth)))
                     (incf position)))
          (if (zerop depth)
              (progn
                (push (subseq value (+ opening (length marker)) (1- position)) results)
                (setf start position))
              (return (nreverse (cons :incomplete results)))))))))

(defun %assistant-command-substitution-result (command args)
  (let ((results nil))
    (dolist (arg (cons command args))
      (dolist (marker '("$(" "<(" ">(" "("))
        (dolist (text (%assistant-parenthesized-substitution-texts arg marker))
          (push (if (eq text :incomplete)
                    (make-assistant-safety-result
                     :classification :block
                     :reason "an incomplete command substitution cannot be classified safely")
                    (%assistant-parse-and-classify-text text))
                results))))
    (when results
      (%assistant-most-restrictive-result results))))

(defun %assistant-wrapper-index-and-kind (command args)
  (let* ((separator (position (code-char 47) command :from-end t))
         (name (if separator (subseq command (1+ separator)) command))
        (value-options '("-u" "--user" "-g" "--group" "-C" "--chdir"
                         "-n" "--adjustment" "-f" "--format" "-I" "--replace")))
    (labels ((target-index (start env-p)
               (loop with index = start
                     while (< index (length args))
                     for arg = (nth index args)
                     do (cond
                          ((string= arg "--") (return (1+ index)))
                          ((and env-p (search "=" arg)) (incf index))
                          ((and (plusp (length arg))
                                (char= (char arg 0) (code-char 45)))
                           (incf index)
                           (when (and (< index (length args))
                                      (member arg value-options :test #'string=))
                             (incf index)))
                          (t (return index))))))
      (cond
        ((member name '("command" "builtin" "exec" "and" "or" "not")
                 :test #'string=)
         (values (target-index 0 nil) :command))
        ((member name '("env" "sudo" "doas" "nice" "time" "nohup" "xargs")
                 :test #'string=)
         (values (target-index 0 (string= name "env")) :command))
        (t (values nil nil))))))

(defun %assistant-safe-git-command-p (args)
  (let ((subcommand (first args)))
    (and (member subcommand '("log" "show" "branch" "remote")
                 :test #'string=)
         (every
          (lambda (arg)
            (or (not (%assistant-string-prefix-p "-" arg))
                (member arg
                        (cond
                          ((string= subcommand "log")
                           '("--oneline" "--decorate" "--stat" "--name-only"
                             "--name-status" "--graph" "--all" "--follow"
                             "--no-merges" "-p" "-n" "--"))
                          ((string= subcommand "show")
                           '("--stat" "--patch" "-p" "--name-only"
                             "--name-status" "--pretty" "--format"
                             "--no-patch" "--"))
                          ((string= subcommand "branch") '("--list" "-l" "--"))
                          ((string= subcommand "remote") '("-v" "--verbose" "--")))
                        :test #'string=)
                (some (lambda (prefix)
                        (%assistant-string-prefix-p prefix arg))
                      (cond
                        ((string= subcommand "log") '("--pretty=" "--format="))
                        ((string= subcommand "show") '("--pretty=" "--format="))
                        (t nil)))))
          (rest args)))))

(defun %assistant-parse-and-classify-text (text)
  (let ((parsed (nshell.domain.parsing:parse-command-line text)))
    (if (nshell.domain.parsing:parse-complete-p parsed)
        (classify-ast (nshell.domain.parsing:parse-result-ast parsed))
        (make-assistant-safety-result
         :classification :block
         :reason "the wrapped command could not be parsed"))))

(defun %assistant-unknown-command-result (command)
  (make-assistant-safety-result
   :classification :confirm
   :command command
   :reason "no static safety rule matched; confirmation is required"))

(defun %assistant-unknown-wrapper-result (command args)
  (loop for index from 0 below (length args)
        for candidate = (nth index args)
        for name = (let ((separator (position (code-char 47) candidate :from-end t)))
                     (if separator (subseq candidate (1+ separator)) candidate))
        when (member name '("rm" "mkfs" "dd" "chmod" "git" "curl" "wget"
                            "sh" "bash" "zsh" "fish")
                      :test #'string=)
          return
            (let ((inner (%assistant-parse-and-classify-text
                          (format nil "~{~a~^ ~}" (nthcdr index args)))))
              (make-assistant-safety-result
               :classification (if (eq :safe
                                        (assistant-safety-result-classification inner))
                                    :confirm
                                    (assistant-safety-result-classification inner))
               :command command
               :reason "an unknown wrapper around a command requires fail-closed handling"))))

(defun classify-command (node)
  "Classify a command-node using its effective command and arguments."
  (if (nshell.domain.parsing:command-node-p node)
      (let* ((command (nshell.domain.parsing:command-node-command node))
             (args (nshell.domain.parsing:command-node-arg-values node))
             (rule (%assistant-rule-for command args))
             (substitution-result (%assistant-command-substitution-result command args)))
        (cond
          ((and substitution-result
                (eq :block
                    (assistant-safety-result-classification substitution-result)))
           substitution-result)
          ((and substitution-result
                (eq :confirm
                    (assistant-safety-result-classification substitution-result)))
           substitution-result)
          ((%assistant-unsafe-argument-p command args)
           (make-assistant-safety-result
            :classification :confirm
            :command command
            :reason (%assistant-unsafe-argument-reason command args)))
          ((and (string= command "git")
                (not (%assistant-safe-git-command-p args)))
           (make-assistant-safety-result
            :classification :confirm
            :command command
            :reason "writing, external command execution, or configuration injection requires confirmation"))
          ((or (member command +assistant-safe-command-names+ :test #'string=)
               (and (string= command "git")
                    (%assistant-safe-git-command-p args)))
           (make-assistant-safety-result
            :classification :safe
            :command command
            :rule-name :safe-allowlist
            :reason "command is on the built-in read-only allowlist"))
          ((multiple-value-bind (index kind)
               (%assistant-wrapper-index-and-kind command args)
             (declare (ignore kind))
             (when index
               (%assistant-parse-and-classify-text
                (format nil "~{~a~^ ~}" (nthcdr (1+ index) (cons command args)))))))
          ((member command '("eval" "source") :test #'string=)
           (%assistant-parse-and-classify-text (format nil "~{~a~^ ~}" args)))
          ((member command '("sh" "bash" "zsh" "fish") :test #'string=)
           (let ((index (position "-c" args :test #'string=)))
             (if (and index (nth (1+ index) args))
                 (%assistant-parse-and-classify-text (nth (1+ index) args))
                 (%assistant-unknown-command-result command))))
          ((and rule
                (eq (assistant-safety-rule-classification rule) :block))
           (make-assistant-safety-result
            :classification :block
            :command command
            :rule-name (assistant-safety-rule-name rule)
            :reason (assistant-safety-rule-reason rule)))
          (rule
           (make-assistant-safety-result
            :classification (assistant-safety-rule-classification rule)
            :command command
            :rule-name (assistant-safety-rule-name rule)
            :reason (assistant-safety-rule-reason rule)))
          (t (or (%assistant-unknown-wrapper-result command args)
                 (%assistant-unknown-command-result command)))))
      (make-assistant-safety-result
       :classification :block
       :reason "the value is not a command AST node")))

(defun %assistant-classification-rank (classification)
  (case classification
    (:safe 0)
    (:confirm 1)
    (:block 2)
    (otherwise 2)))

(defun %assistant-most-restrictive-result (results)
  (if results
      (reduce (lambda (left right)
                (if (> (%assistant-classification-rank
                       (assistant-safety-result-classification right))
                       (%assistant-classification-rank
                        (assistant-safety-result-classification left)))
                    right
                    left))
              results)
      (make-assistant-safety-result
       :classification :block
       :reason "an empty compound command cannot be classified safely")))

(defun classify-pipeline (node)
  "Classify a pipeline by its most restrictive stage."
  (if (nshell.domain.parsing:pipeline-node-p node)
      (%assistant-most-restrictive-result
       (mapcar #'classify-ast
               (nshell.domain.parsing:pipeline-node-commands node)))
      (make-assistant-safety-result
       :classification :block
       :reason "the value is not a pipeline AST node")))

(defun %assistant-classify-sequence (node)
  (if (nshell.domain.parsing:sequence-node-p node)
      (%assistant-most-restrictive-result
       (mapcar #'classify-ast
               (nshell.domain.parsing:sequence-node-commands node)))
      (make-assistant-safety-result
       :classification :block
       :reason "the value is not a sequence AST node")))

(defun classify-ast (node)
  "Classify a shell AST value without inspecting raw text."
  (cond
    ((nshell.domain.parsing:command-node-p node) (classify-command node))
    ((nshell.domain.parsing:pipeline-node-p node) (classify-pipeline node))
    ((nshell.domain.parsing:sequence-node-p node)
     (%assistant-classify-sequence node))
    (t (make-assistant-safety-result
        :classification :block
        :reason "unsupported AST node"))))

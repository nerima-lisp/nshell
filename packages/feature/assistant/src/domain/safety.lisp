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
    :condition '(:all (:arg-equals "/")
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
    :command "ls"
    :condition :always
    :reason "listing files does not write to the filesystem")
   (make-assistant-safety-rule
    :name :safe-search
    :classification :safe
    :command "grep"
    :condition :always
    :reason "searching text does not write to the filesystem")
   (make-assistant-safety-rule
    :name :safe-git-status
    :classification :safe
    :command "git"
    :condition '(:subcommand-equals "status")
    :reason "git status only reads repository state"))
  "Static AST safety rules, ordered from specific dangerous cases to safe cases.")

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

(defun %assistant-unknown-command-result (command)
  (make-assistant-safety-result
   :classification :confirm
   :command command
   :reason "no static safety rule matched; confirmation is required"))

(defun classify-command (node)
  "Classify a command-node using only its parsed command and arguments."
  (if (nshell.domain.parsing:command-node-p node)
      (let* ((command (nshell.domain.parsing:command-node-command node))
             (args (nshell.domain.parsing:command-node-arg-values node))
             (rule (%assistant-rule-for command args)))
        (if rule
            (make-assistant-safety-result
             :classification (assistant-safety-rule-classification rule)
             :command command
             :rule-name (assistant-safety-rule-name rule)
             :reason (assistant-safety-rule-reason rule))
            (%assistant-unknown-command-result command)))
      (make-assistant-safety-result
       :classification :block
       :reason "the value is not a command AST node")))

(defun %assistant-classification-rank (classification)
  (case classification
    (:safe 0)
    (:confirm 1)
    (:block 2)
    (otherwise 2)))

(defun classify-pipeline (node)
  "Classify a pipeline by its most restrictive stage."
  (if (nshell.domain.parsing:pipeline-node-p node)
      (let ((results
              (mapcar #'classify-ast
                      (nshell.domain.parsing:pipeline-node-commands node))))
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
             :reason "an empty pipeline cannot be classified safely")))
      (make-assistant-safety-result
       :classification :block
       :reason "the value is not a pipeline AST node")))

(defun classify-ast (node)
  "Classify a command or pipeline AST value without inspecting raw text."
  (cond
    ((nshell.domain.parsing:command-node-p node) (classify-command node))
    ((nshell.domain.parsing:pipeline-node-p node) (classify-pipeline node))
    (t (make-assistant-safety-result
        :classification :block
        :reason "unsupported AST node"))))

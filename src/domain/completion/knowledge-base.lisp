(in-package #:nshell.domain.completion)

;;; Command completion data lives in a CL-PROLOG-KIT rulebase: KB-ADD-COMMAND and
;;; friends assert COMMAND-REGISTERED/SUBCOMMAND-OF/HAS-FLAG/OPTION-VALUE/
;;; EXCLUSIVE-GROUP/DESCRIBES facts, and three small rules derive COMPLETES
;;; from them so COMPLETE (engine.lisp) answers command, subcommand, and flag
;;; candidates the same way the static catalog's rule-knowledge-base does.

;;; KNOWLEDGE-BASE is a RULE-KNOWLEDGE-BASE subtype so %COMPLETION-CANDIDATES
;;; (engine.lisp) can TYPECASE it ahead of the plain RULE-KNOWLEDGE-BASE that
;;; *BUILT-IN-RULE-KNOWLEDGE-BASE* uses -- both are CL-PROLOG-KIT rulebases under
;;; the hood, but they answer completion queries through different rule sets.
(defstruct (knowledge-base (:include rule-knowledge-base))
  (command-description-facts (make-hash-table :test #'equal))
  (flag-description-facts (make-hash-table :test #'equal)))

(defun make-empty-knowledge-base ()
  (let ((kb (make-knowledge-base)))
    (assert-rule! kb (make-rule :head '(completes ?cmd ?cmd)
                                :body '((command-registered ?cmd))))
    (assert-rule! kb (make-rule :head '(completes ?cmd ?name)
                                :body '((subcommand-of ?cmd ?name))))
    (assert-rule! kb (make-rule :head '(completes ?cmd ?flag)
                                :body '((has-flag ?cmd ?flag))))
    kb))

(defun %kb-solution-values (kb goal variable)
  (mapcar (lambda (solution) (cl-prolog-kit:solution-binding variable solution))
          (prove-all kb goal)))

(defun %unique-string-values (values)
  (let ((seen nil)
        (result nil))
    (dolist (value values (nreverse result))
      (when (and (stringp value)
                 (not (member value seen :test #'string=)))
        (push value seen)
        (push value result)))))

(defun %kb-option-value-spec-option (spec)
  (and (consp spec)
       (first spec)))

(defun %kb-option-value-spec-values (spec)
  (if (consp spec)
      (rest spec)
      nil))

(defun %valid-kb-option-value-spec-p (spec)
  (stringp (%kb-option-value-spec-option spec)))

(defun %kb-option-value-kind-spec-option (spec)
  (and (consp spec)
       (first spec)))

(defun %kb-option-value-kind-spec-kind (spec)
  (and (consp (rest spec))
       (second spec)))

(defun %valid-kb-option-value-kind-spec-p (spec)
  (and (stringp (%kb-option-value-kind-spec-option spec))
       (member (%kb-option-value-kind-spec-kind spec)
               '(:file :directory)
               :test #'eq)))

(defun %make-kb-option-value-spec (opt-name values)
  (cons opt-name values))

(defun %merge-string-values (existing incoming)
  (%unique-string-values (append existing incoming)))

(defun %normalize-kb-exclusive-option-groups (groups)
  (let ((normalized nil))
    (dolist (group groups (nreverse normalized))
      (let ((options (%unique-string-values group)))
        (when (rest options)
          (push options normalized))))))

(defun kb-command-present-p (kb cmd-name)
  (and (prove-all kb (list 'command-registered cmd-name)) t))

(defun kb-command-subcommands (kb cmd-name)
  (%unique-string-values
   (%kb-solution-values kb (list 'subcommand-of cmd-name '?name) '?name)))

(defun kb-command-flags (kb cmd-name)
  (%unique-string-values
   (%kb-solution-values kb (list 'has-flag cmd-name '?flag) '?flag)))

(defun kb-command-option-values (kb cmd-name)
  (let ((values-by-option (make-hash-table :test #'equal))
        (options nil))
    (dolist (solution (prove-all kb (list 'option-value cmd-name '?option '?value)))
      (let ((option (cl-prolog-kit:solution-binding '?option solution))
            (value (cl-prolog-kit:solution-binding '?value solution)))
        (unless (nth-value 1 (gethash option values-by-option))
          (push option options))
        (push value (gethash option values-by-option))))
    (sort (mapcar (lambda (option)
                    (%make-kb-option-value-spec
                     option
                     (%unique-string-values (nreverse (gethash option values-by-option)))))
                  options)
          #'string< :key #'%kb-option-value-spec-option)))

(defun kb-command-option-value-kinds (kb cmd-name)
  (sort
   (remove-duplicates
    (loop for solution in
            (prove-all kb (list 'option-value-kind cmd-name '?option '?kind))
          for option = (cl-prolog-kit:solution-binding '?option solution)
          for kind = (cl-prolog-kit:solution-binding '?kind solution)
          when (and (stringp option)
                    (member kind '(:file :directory) :test #'eq))
            collect (list option kind))
    :test #'equal)
   #'string<
   :key #'first))

(defun kb-command-exclusive-options (kb cmd-name)
  (remove-duplicates
   (%kb-solution-values kb (list 'exclusive-group cmd-name '?members) '?members)
   :test #'equal :from-end t))

(defun kb-command-description (kb cmd-name)
  (let ((fact (gethash cmd-name (knowledge-base-command-description-facts kb))))
    (if fact
        (second (fact-args fact))
        (first (%kb-solution-values kb
                                    (list 'describes cmd-name '?description)
                                    '?description)))))

(defun kb-registered-commands (kb)
  (sort (%unique-string-values (%kb-solution-values kb '(command-registered ?cmd) '?cmd))
        #'string<))

(defun %retract-command-facts! (kb cmd-name)
  (setf (rule-knowledge-base-facts kb)
        (remove-if (lambda (fact)
                     (and (member (fact-predicate fact)
                                  '(command-registered subcommand-of has-flag
                                    option-value option-value-kind
                                    exclusive-group describes flag-describes))
                          (equal (first (fact-args fact)) cmd-name)))
                   (rule-knowledge-base-facts kb)))
  (remhash cmd-name (knowledge-base-command-description-facts kb))
  (remhash cmd-name (knowledge-base-flag-description-facts kb))
  (%invalidate-rule-knowledge-base! kb))

(defun %set-command-description! (kb cmd-name description)
  (let* ((descriptions (knowledge-base-command-description-facts kb))
         (fact (gethash cmd-name descriptions)))
    (if fact
        (progn
          (setf (fact-args fact) (list cmd-name description))
          (%invalidate-rule-knowledge-base! kb))
        (let ((new-fact
                (make-fact :predicate 'describes :args (list cmd-name description))))
          (setf (gethash cmd-name descriptions) new-fact)
          (assert-fact! kb new-fact))))
  kb)
(defun %set-flag-description! (kb cmd-name option description)
  (let* ((command-facts
           (or (gethash cmd-name (knowledge-base-flag-description-facts kb))
               (setf (gethash cmd-name (knowledge-base-flag-description-facts kb))
                     (make-hash-table :test #'equal))))
         (fact (gethash option command-facts)))
    (if fact
        (progn
          (setf (fact-args fact) (list cmd-name option description))
          (%invalidate-rule-knowledge-base! kb))
        (let ((new-fact
                (make-fact :predicate 'flag-describes
                           :args (list cmd-name option description))))
          (setf (gethash option command-facts) new-fact)
          (assert-fact! kb new-fact))))
  kb)

(defun kb-add-command
    (kb cmd-name &key subcommands flags option-values option-descriptions
             option-value-kinds exclusive-options description)
  (assert-fact! kb (make-fact :predicate 'command-registered :args (list cmd-name)))
  (dolist (name (remove-if-not #'stringp subcommands))
    (assert-fact! kb (make-fact :predicate 'subcommand-of :args (list cmd-name name))))
  (dolist (flag (remove-if-not #'stringp flags))
    (assert-fact! kb (make-fact :predicate 'has-flag :args (list cmd-name flag))))
  (dolist (spec option-values)
    (when (%valid-kb-option-value-spec-p spec)
      (let ((option (%kb-option-value-spec-option spec)))
        (dolist (value (%kb-option-value-spec-values spec))
          (when (stringp value)
            (assert-fact! kb (make-fact :predicate 'option-value
                                        :args (list cmd-name option value))))))))
  (dolist (spec option-descriptions)
    (when (and (consp spec)
               (stringp (first spec))
               (consp (rest spec))
               (stringp (second spec))
               (null (cddr spec)))
      (%set-flag-description! kb cmd-name (first spec) (second spec))))
  (dolist (spec option-value-kinds)
    (when (%valid-kb-option-value-kind-spec-p spec)
      (assert-fact!
       kb
       (make-fact
        :predicate 'option-value-kind
        :args (list cmd-name
                    (%kb-option-value-kind-spec-option spec)
                    (%kb-option-value-kind-spec-kind spec))))))
  (dolist (group (%normalize-kb-exclusive-option-groups exclusive-options))
    (assert-fact! kb (make-fact :predicate 'exclusive-group :args (list cmd-name group))))
  (when description
    (%set-command-description! kb cmd-name description))
  kb)

(defun kb-add-option (kb cmd-name opt-name &key values)
  (kb-add-command kb cmd-name
                  :flags (list opt-name)
                  :option-values (when values
                                   (list (%make-kb-option-value-spec opt-name values)))))

(defun kb-remove-command (kb cmd-name)
  (%retract-command-facts! kb cmd-name))

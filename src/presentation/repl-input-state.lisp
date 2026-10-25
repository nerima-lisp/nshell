;;; REPL input-state helpers
(in-package #:nshell.presentation)

(progn
  (defvar *repl-abbreviation-function-invoker* nil)

  (defun %repl-abbreviation-for-token (token)
    (let ((best nil)
          (best-order -1)
          (best-exact-p nil))
      (maphash
       (lambda (name value)
         (when (nshell.domain.abbreviation:abbreviation-matches-token-p
                value name token)
           (let* ((record-p
                    (nshell.domain.abbreviation:abbreviation-p value))
                  (order
                    (if record-p
                        (nshell.domain.abbreviation:abbreviation-order value)
                        0))
                  (exact-p (string= name token)))
             (when (or (> order best-order)
                       (and (= order best-order)
                            exact-p
                            (not best-exact-p)))
               (setf best value
                     best-order order
                     best-exact-p exact-p)))))
       *abbreviations*)
      best))

  (defun %invoke-repl-abbreviation-function (function-name token)
    (let* ((context (%make-repl-shell-context))
           (function-body
             (gethash function-name
                      (nshell.application:shell-context-function-table context))))
      (multiple-value-bind (output code)
          (cond
            (function-body
             (nshell.application::%execute-function-command-in-context
              context function-body (list token)))
            (t
             (multiple-value-bind (binding found-p)
                 (nshell.application:lookup-shell-function
                  (nshell.application:context-shell-function-registry context)
                  function-name
                  :scope (nshell.application:active-shell-function-scope))
               (if found-p
                   (let* ((output-stream (make-string-output-stream))
                          (nshell.application::*current-evaluation-status* 0)
                          (value
                            (let ((*standard-output* output-stream)
                                  (*error-output* output-stream))
                              (funcall
                               (nshell.application:shell-function-binding-callable
                                binding)
                               context
                               (list
                                (nshell.domain.parsing:make-evaluated-command-arg
                                 token))
                               :stream))))
                     (values
                      (or (and (stringp value) value)
                          (get-output-stream-string output-stream))
                      nshell.application::*current-evaluation-status*))
                   (values nil 127)))))
        (%sync-repl-shell-context context code)
        (values output (zerop code)))))

  (defun %resolve-repl-abbreviation (token)
    (let ((entry (%repl-abbreviation-for-token token)))
      (if (and (nshell.domain.abbreviation:abbreviation-p entry)
               (nshell.domain.abbreviation:abbreviation-function-name entry))
          (multiple-value-bind (expansion success-p)
              (funcall (or *repl-abbreviation-function-invoker*
                           #'%invoke-repl-abbreviation-function)
                       (nshell.domain.abbreviation:abbreviation-function-name
                        entry)
                       token)
            (when (and success-p (stringp expansion))
              (nshell.domain.abbreviation:make-abbreviation
               :expansion expansion
               :position
               (nshell.domain.abbreviation:abbreviation-position entry)
               :regex (nshell.domain.abbreviation:abbreviation-regex entry)
               :set-cursor-marker
               (nshell.domain.abbreviation:abbreviation-set-cursor-marker entry)
               :order
               (nshell.domain.abbreviation:abbreviation-order entry))))
          entry)))

  (defun make-repl-input-state (&key (buffer "") cursor-pos)
    (make-input-state :buffer buffer
                      :cursor-pos (or cursor-pos (length buffer))
                      :abbreviation-expander #'%resolve-repl-abbreviation)))

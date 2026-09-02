(in-package #:nshell.domain.parsing)

(defstruct (%token-reduction-state
             (:constructor %make-token-reduction-state
                 (&key (all-cmds '())
                       (current-args '())
                       current-cmd
                       current-cmd-token
                       current-cmd-fragments
                       last-word-token
                       pending-redirect-token
                       pending-sep
                       pending-sep-token
                       (errors '())))
             (:copier nil))
  (all-cmds '() :type list)
  (current-args '() :type list)
  current-cmd
  current-cmd-token
  current-cmd-fragments
  last-word-token
  pending-redirect-token
  pending-sep
  pending-sep-token
  (errors '() :type list))

(defmacro %update-token-reduction-state (state &body slot-updates)
  "Apply named reducer-state updates and return STATE for threaded folds."
  (let ((accessor (lambda (slot)
                    (intern (format nil "%TOKEN-REDUCTION-STATE-~A" slot)
                            (symbol-package '%update-token-reduction-state)))))
    `(progn
       (setf ,@(mapcan (lambda (update)
                         (destructuring-bind (slot value) update
                           (list `(,(funcall accessor slot) ,state) value)))
                       slot-updates))
       ,state)))

(define-value-struct %token-reduction-result
  ((commands '() :type list)
   (errors '() :type list)))

(define-value-struct %token-reduction-argument
  ((value "" :type string)
   (quote-style nil)
   (syntactic-p nil :type boolean)
   (fragments nil :type list)))

(define-value-struct %token-reduction-diagnostic-policy
  ((kind nil :type keyword)
   (message "" :type string)))

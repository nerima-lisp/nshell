(in-package #:nshell.application)

(defvar *bind-table-handler* nil
  "NIL, or a function of one OPERATION keyword and further arguments that the
interactive session installs so the bind builtin can reach the live
key-dispatch table. OPERATION is :LIST, :GET, :SET, :ERASE, :RESET,
:VALID-KEYS, or :VALID-ACTIONS, matching BIND-DISPATCH-HANDLER in
src/presentation/input-state-dispatch.lisp.")

(defun %builtin-bind-usage ()
  (%builtin-usage "bind" "bind [-e KEY] [--reset] [KEY [ACTION]]"))

(defun %bind-list-output ()
  (let* ((bindings (funcall *bind-table-handler* :list))
         (width (reduce #'max bindings
                        :key (lambda (row) (length (car row)))
                        :initial-value 0)))
    (with-output-to-string (stream)
      (dolist (row bindings)
        (format stream "~va  ~a~%" width (car row) (cdr row))))))

(defun %bind-unknown-key-error (key-name)
  (values (format nil "bind: unknown key ~a (try: ~{~a~^, ~})~%"
                  key-name (funcall *bind-table-handler* :valid-keys))
          2))

(defun %bind-unknown-action-error (action-name)
  (values (format nil "bind: unknown action ~a (try: ~{~a~^, ~})~%"
                  action-name (funcall *bind-table-handler* :valid-actions))
          2))

(defun %bind-show-one (key-name)
  (multiple-value-bind (action-name found-p)
      (funcall *bind-table-handler* :get key-name)
    (if found-p
        (values (format nil "~a  ~a~%" key-name action-name) 0)
        (%bind-unknown-key-error key-name))))

(defun %bind-set (key-name action-name)
  (ecase (funcall *bind-table-handler* :set key-name action-name)
    (:ok (values nil 0))
    (:unknown-key (%bind-unknown-key-error key-name))
    (:unknown-action (%bind-unknown-action-error action-name))))

(defun %bind-erase (key-name)
  (ecase (funcall *bind-table-handler* :erase key-name)
    (:ok (values nil 0))
    (:unknown-key (%bind-unknown-key-error key-name))))

(defun %bind-reset ()
  (funcall *bind-table-handler* :reset)
  (values nil 0))

(define-builtin %builtin-bind (context args) (context)
  (cond
    ((not (functionp *bind-table-handler*))
     (values (format nil "bind: interactive mode is unavailable~%") 2))
    ((null args) (values (%bind-list-output) 0))
    ((and (string= (first args) "--reset") (null (rest args)))
     (%bind-reset))
    ((string= (first args) "-e")
     (if (and (second args) (null (cddr args)))
         (%bind-erase (second args))
         (%builtin-bind-usage)))
    ((null (rest args)) (%bind-show-one (first args)))
    ((null (cddr args)) (%bind-set (first args) (second args)))
    (t (%builtin-bind-usage))))

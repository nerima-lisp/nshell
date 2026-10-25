(in-package #:nshell.application)

(defparameter *shell-hook-names*
  '(:preexec :postexec :prompt :cd :command-not-found))

(defvar *shell-hook-table* (make-hash-table :test #'eq))

(defun %shell-hook-key (name)
  (let ((key (etypecase name
               (symbol (intern (symbol-name name) :keyword))
               (string (intern (string-upcase name) :keyword)))))
    (unless (member key *shell-hook-names* :test #'eq)
      (error "Unknown shell hook: ~a" name))
    key))

(defun register-shell-hook (name function)
  "Register FUNCTION for NAME and return FUNCTION. Duplicate registrations are ignored."
  (check-type function function)
  (let* ((key (%shell-hook-key name))
         (hooks (gethash key *shell-hook-table*)))
    (unless (member function hooks :test #'eq)
      (setf (gethash key *shell-hook-table*)
            (append hooks (list function))))
    function))

(defun remove-shell-hook (name function)
  "Remove FUNCTION from NAME and return true when it was registered."
  (check-type function function)
  (let* ((key (%shell-hook-key name))
         (hooks (gethash key *shell-hook-table*)))
    (when (member function hooks :test #'eq)
      (setf (gethash key *shell-hook-table*)
            (remove function hooks :test #'eq))
      t)))

(defun clear-shell-hooks (&optional name)
  "Clear all hooks, or only those registered for NAME."
  (if name
      (remhash (%shell-hook-key name) *shell-hook-table*)
      (clrhash *shell-hook-table*)))

(defun run-shell-hooks (name &rest arguments)
  "Call NAME's hooks in registration order with ARGUMENTS; report and isolate hook errors."
  (let* ((key (%shell-hook-key name))
         (hooks (copy-list (gethash key *shell-hook-table*))))
    (dolist (function hooks)
      (handler-case
          (apply function arguments)
        (error (condition)
          (format *error-output* "nshell: ~a hook failed: ~a~%"
                  (string-downcase (symbol-name key)) condition))))
    nil))

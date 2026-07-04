(in-package #:nshell.application)

;;; Pipeline redirect handling
;;; Functions for extracting, applying, and restoring I/O redirections.
;;; Redirect data is represented as an alist: ((kind . target) ...) where
;;; kind is a keyword (:>, :>>, :&>, :2>, :2>&1, :<, :<<, :<<<) and
;;; target is the file path string (or NIL for fd-dup redirects).

;; -- Logic: redirect extraction from command node args ----------------

(defun %extract-command-redirects (cmd-node)
  "Split CMD-NODE args into a command redirect split result.
Redirect args (and their targets) are removed from the args list."
  (nshell.domain.parsing:split-command-node-redirects cmd-node))

(defun %extract-pipeline-redirects (commands)
  "Split COMMANDS into a command-list redirect split result."
  (nshell.domain.parsing:split-command-nodes-redirects commands))

(defun %write-redirected-stage-output (redirects output)
  "Write OUTPUT to the redirect file if REDIRECTS contains an output redirect.
Returns T when a file was written (suppressing stdout capture), NIL otherwise."
  (multiple-value-bind (target mode)
      (nshell.domain.parsing:redirect-output-spec redirects)
    (when target
      (with-open-file (stream target
                              :direction :output
                              :if-exists mode
                              :if-does-not-exist :create)
      (write-string (or output "") stream))
      t)))

;; -- Logic: context-level redirect application ----------------------

(defun %redirect-fn (context key)
  (getf (shell-context-redirect-fns context) key))

(defun %apply-context-redirects (context redirects)
  "Apply REDIRECTS to the current shell CONTEXT's I/O streams."
  (nshell.domain.parsing:map-redirect-entries
   (lambda (kind target)
     (case kind
       (:>    (funcall (%redirect-fn context :redirect-output) target :supersede))
       (:>>   (funcall (%redirect-fn context :redirect-output) target :append))
       (:&>   (let ((fn (%redirect-fn context :redirect-output-error)))
                (when fn (funcall fn target :supersede))))
       (:&>>  (let ((fn (%redirect-fn context :redirect-output-error)))
                (when fn (funcall fn target :append))))
       (:2>   (let ((fn (%redirect-fn context :redirect-error)))
                (when fn (funcall fn target :supersede))))
       (:2>>  (let ((fn (%redirect-fn context :redirect-error)))
                (when fn (funcall fn target :append))))
       (:2>&1 (let ((fn (%redirect-fn context :redirect-error-to-output)))
                (when fn (funcall fn))))
       (:<    (funcall (%redirect-fn context :redirect-input) target))
       (:<<<  (let ((fn (%redirect-fn context :redirect-input-string)))
                (when fn (funcall fn target))))
       (:<<   (let ((fn (%redirect-fn context :redirect-input-document)))
                (when fn (funcall fn target))))
       (t nil)))
   redirects))

(defun %restore-context-redirects (context)
  "Restore I/O streams to their pre-redirect state."
  (let ((restore (%redirect-fn context :restore)))
    (when restore (funcall restore))))

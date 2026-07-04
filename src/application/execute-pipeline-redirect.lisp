(in-package #:nshell.application)

;;; Pipeline redirect handling
;;; Functions for extracting, applying, and restoring I/O redirections.
;;; Redirect data is represented as an alist: ((kind . target) ...) where
;;; kind is a keyword (:>, :>>, :&>, :2>, :2>&1, :<, :<<, :<<<) and
;;; target is the file path string (or NIL for fd-dup redirects).

;; -- Data: redirect classification predicates -------------------------

(defparameter +input-redirect-kinds+ '(:< :<< :<<<)
  "Redirect kinds that provide input to a command stage.")

(defparameter +output-redirect-kinds+ '(:> :>> :&> :&>>)
  "Redirect kinds that capture output from a command stage.")

(defparameter +stderr-redirect-kinds+ '(:2> :2>> :2>&1 :&> :&>>)
  "Redirect kinds that affect the standard error stream.")

;; -- Logic: redirect extraction from command node args ----------------

(defun %extract-command-redirects (cmd-node)
  "Split CMD-NODE args into (clean-command-node redirects).
Redirect args (and their targets) are removed from the args list."
  (nshell.domain.parsing:split-command-node-redirects cmd-node))

(defun %extract-pipeline-redirects (commands)
  "Split each command in COMMANDS into (clean-commands per-stage-redirects)."
  (nshell.domain.parsing:split-command-nodes-redirects commands))

;; -- Logic: redirect spec lookup -------------------------------------

(defun %input-redirect-spec (redirects)
  "Return the last input redirect from REDIRECTS, or NIL."
  (find-if (lambda (r) (member (car r) +input-redirect-kinds+))
           redirects :from-end t))

(defun %input-redirect-target (redirects)
  "Return the file path for a :< redirect, or NIL."
  (let ((redirect (%input-redirect-spec redirects)))
    (when (and redirect (eq (car redirect) :<))
      (cdr redirect))))

(defun %output-redirect-spec (redirects)
  "Return (target mode) for the last output redirect, or NIL."
  (let ((redirect (find-if (lambda (r) (member (car r) +output-redirect-kinds+))
                           redirects :from-end t)))
    (when redirect
      (values (cdr redirect)
              (if (member (car redirect) '(:>> :&>>)) :append :supersede)))))

(defun %write-redirected-stage-output (redirects output)
  "Write OUTPUT to the redirect file if REDIRECTS contains an output redirect.
Returns T when a file was written (suppressing stdout capture), NIL otherwise."
  (multiple-value-bind (target mode)
      (%output-redirect-spec redirects)
    (when target
      (with-open-file (stream target
                              :direction :output
                              :if-exists mode
                              :if-does-not-exist :create)
        (write-string (or output "") stream))
      t)))

(defun %pipeline-stderr-spec (redirects)
  "Return (kind target mode) for stderr handling: :MERGE, :FILE, or NIL."
  (let ((redirect (find-if (lambda (r) (member (car r) +stderr-redirect-kinds+))
                           redirects :from-end t)))
    (when redirect
      (case (car redirect)
        (:2>&1 (values :merge nil nil))
        (:2>   (values :file (cdr redirect) :supersede))
        (:2>>  (values :file (cdr redirect) :append))
        (:&>   (values :file (cdr redirect) :supersede))
        (:&>>  (values :file (cdr redirect) :append))))))

;; -- Logic: context-level redirect application ----------------------

(defun %redirect-fn (context key)
  (getf (shell-context-redirect-fns context) key))

(defun %output-redirect-p (redirects)
  (find-if (lambda (r) (member (car r) +output-redirect-kinds+)) redirects))

(defun %apply-context-redirects (context redirects)
  "Apply REDIRECTS to the current shell CONTEXT's I/O streams."
  (dolist (redirect redirects)
    (let ((target (cdr redirect)))
      (case (car redirect)
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
        (t nil)))))

(defun %restore-context-redirects (context)
  "Restore I/O streams to their pre-redirect state."
  (let ((restore (%redirect-fn context :restore)))
    (when restore (funcall restore))))

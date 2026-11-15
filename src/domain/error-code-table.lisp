(in-package #:nshell.domain.error-codes)

;;; Uses only CL, so scripts/generate-error-codes-doc.lisp can load this file
;;; and read the table without loading nshell or its dependencies. The unit
;;; test reads the table the same way, so both see the same entries.

(defun error-code-name (entry) (first entry))
(defun error-code-kind (entry) (second entry))
(defun error-code-exit-code (entry) (third entry))
(defun %error-code-summary-en (entry) (fourth entry))
(defun %error-code-fix-en (entry) (sixth entry))

(defun read-error-code-table (pathname)
  "Return the quoted entry list of the +ERROR-CODES+ DEFPARAMETER in PATHNAME,
read with READ and never evaluated."
  (let ((*package* (find-package '#:nshell.domain.error-codes))
        (*read-eval* nil))
    (with-open-file (in pathname :external-format :utf-8)
      (loop for form = (read in nil in)
            until (eq form in)
            when (and (consp form)
                      (eq (first form) 'defparameter)
                      (eq (second form) '+error-codes+))
              do (destructuring-bind (quote-operator entries) (third form)
                   (assert (eq quote-operator 'quote))
                   (return entries))
            finally (error "No +ERROR-CODES+ DEFPARAMETER in ~A" pathname)))))

(defun %markdown-cell (text)
  (if text
      (with-output-to-string (out)
        (loop for char across text
              do (when (char= char #\|)
                   (write-char #\\ out))
                 (write-char char out)))
      "-"))

(defun %exit-status-cell (exit-code)
  (if (eq exit-code :child)
      "child's exit status"
      (princ-to-string exit-code)))

(defun render-error-codes-markdown (entries)
  (with-output-to-string (out)
    (format out "<!-- Generated from data/domain/error-codes-data.lisp by ~
scripts/generate-error-codes-doc.lisp. Do not edit by hand. -->~%~
# Error codes~%~%~
nshell names each error and warning with a stable code. Errors start with~%~
`E_` and each one has the exit status listed below. Warnings start with `W_`~%~
and flag input that still runs but may not do what you meant; its behaviour~%~
changes in a later release, and some of it becomes an error. Messages do not~%~
show these codes yet.~%~%~
## Errors~%~%~
| Code | Exit status | Meaning | How to fix |~%~
|---|---|---|---|~%")
    (dolist (entry entries)
      (when (eq (error-code-kind entry) :error)
        (format out "| `~A` | ~A | ~A | ~A |~%"
                (error-code-name entry)
                (%exit-status-cell (error-code-exit-code entry))
                (%markdown-cell (%error-code-summary-en entry))
                (%markdown-cell (%error-code-fix-en entry)))))
    (format out "~%## Warnings~%~%~
| Code | Meaning | How to fix |~%~
|---|---|---|~%")
    (dolist (entry entries)
      (when (eq (error-code-kind entry) :warning)
        (format out "| `~A` | ~A | ~A |~%"
                (error-code-name entry)
                (%markdown-cell (%error-code-summary-en entry))
                (%markdown-cell (%error-code-fix-en entry)))))))

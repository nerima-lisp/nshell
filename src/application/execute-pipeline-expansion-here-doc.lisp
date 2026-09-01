(in-package #:nshell.application)

;;; Here-document escape protection and expansion.

(defun %here-doc-escape-at (input position)
  "Return the protected token and consumed width for an escape at POSITION."
  (when (and (char= (char input position) #\\)
             (< (1+ position) (length input)))
    (let ((next (char input (1+ position))))
      (cond
        ((char= next #\Newline) (values nil 2))
        ((char= next #\$)
         (if (and (< (+ position 2) (length input))
                  (char= (char input (+ position 2)) #\())
             (values +here-doc-escaped-command-open+ 3)
             (values +here-doc-escaped-dollar+ 2)))
        ((char= next #\`) (values +here-doc-escaped-backtick+ 2))
        ((char= next #\\) (values +here-doc-escaped-backslash+ 2))))))

(defun %protect-here-doc-escapes (input)
  "Protect heredoc escapes from the ordinary parameter expander."
  (let ((length (length input)))
    (with-output-to-string (out)
      (loop with pos = 0
            while (< pos length)
            do (multiple-value-bind (token consumed) (%here-doc-escape-at input pos)
                 (if consumed
                     (progn
                       (when token (write-char token out))
                       (incf pos consumed))
                     (progn
                       (write-char (char input pos) out)
                       (incf pos))))))))

(defun %restore-here-doc-escapes (input)
  (with-output-to-string (out)
    (loop for ch across input
          do (let ((replacement
                     (cond
                       ((char= ch +here-doc-escaped-dollar+) #\$)
                       ((char= ch +here-doc-escaped-backtick+) #\`)
                       ((char= ch +here-doc-escaped-backslash+) #\\)
                       ((char= ch +here-doc-escaped-command-open+) "$(")
                       (t ch))))
               (if (characterp replacement)
                   (write-char replacement out)
                   (write-string replacement out))))))

(defun %expand-here-doc-body-in-context (context value)
  "Expand an unquoted heredoc body without splitting or pathname expansion."
  (let* ((environment (shell-context-environment context))
         (protected (%protect-here-doc-escapes value))
         (parts (%expand-command-substitutions context protected t)))
    (%restore-here-doc-escapes
     (with-output-to-string (out)
       (dolist (part parts)
         (write-string (nshell.domain.expansion:expand-double-quoted part environment)
                       out))))))

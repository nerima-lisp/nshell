(in-package #:nshell.application)

;;; Command substitution scanning and execution.

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro %try-substitution-match (&body forms)
    "Try each form in turn and return the first successful match."
    (if (null (rest forms))
        (first forms)
        (let ((parts (gensym "PARTS")) (pos (gensym "POS")))
          `(multiple-value-bind (,parts ,pos) ,(first forms)
             (if ,pos
                 (values ,parts ,pos)
                 (%try-substitution-match ,@(rest forms))))))))

(defun %paren-balanced-end (value start)
  "Return the index just past the closing paren that returns depth to zero, or NIL."
  (let ((depth 0))
    (loop for index from start below (length value)
          for ch = (char value index)
          do (cond ((char= ch #\() (incf depth))
                   ((char= ch #\)) (decf depth)
                    (when (zerop depth) (return (1+ index))))))))

(defun %command-substitution-source-text (value)
  ;; Re-parsing must retain escape syntax, while data tokens decode only once.
  (with-output-to-string (out)
    (loop for character across value
          for code = (char-code character)
          do (when (and nshell.domain.expansion::*fragment-escape-context*
                        (<= +command-fragment-escape-base+ code
                            (1- +command-fragment-escape-limit+)))
               (write-char #\\ out))
             (write-char (nshell.domain.expansion::%decode-fragment-character character) out))))

(defun %command-sub-fields-at (context value open-paren &optional preserve-newlines-p)
  "Run the command substitution at OPEN-PAREN, if balanced and non-empty."
  (let ((end (nshell.domain.parsing:%balanced-substitution-end value open-paren)))
    (when (and end (> end (1+ open-paren)))
      (let* ((text (%command-substitution-source-text (subseq value (1+ open-paren) end)))
             (replacement
               (let ((nshell.domain.expansion::*fragment-escape-context* nil))
                 (if preserve-newlines-p
                     (%execute-command-substitution-output context text)
                     (%execute-command-substitution-fields context text)))))
        (values (if preserve-newlines-p
                    (nshell.domain.expansion::%encode-fragment-data replacement)
                    (mapcar #'nshell.domain.expansion::%encode-fragment-data replacement))
                (1+ end))))))

(defun %expand-arithmetic-command-substitution-at (value pos parts len)
  (when (and (char= (char value pos) #\$)
             (< (+ pos 2) len)
             (char= (char value (1+ pos)) #\()
             (char= (char value (+ pos 2)) #\())
    (let ((end (%paren-balanced-end value (1+ pos))))
      (if end
          (values (%append-command-substitution-string parts (subseq value pos end)) end)
          (values (%append-command-substitution-char parts #\$) (1+ pos))))))

(defun %expand-posix-command-substitution-at
    (context value pos parts len &optional preserve-newlines-p)
  (when (and (char= (char value pos) #\$)
             (< (1+ pos) len)
             (char= (char value (1+ pos)) #\())
    (multiple-value-bind (replacement next)
        (%command-sub-fields-at context value (1+ pos) preserve-newlines-p)
      (if next
          (values (if preserve-newlines-p
                      (%append-command-substitution-string parts (or replacement ""))
                      (%append-command-substitution-fields parts replacement)) next)
          (values (%append-command-substitution-char parts #\$) (1+ pos))))))

(defun %expand-bare-command-substitution-at
    (context value pos parts &optional preserve-newlines-p)
  (when (char= (char value pos) #\()
    (multiple-value-bind (replacement next)
        (%command-sub-fields-at context value pos preserve-newlines-p)
      (if next
          (values (if preserve-newlines-p
                      (%append-command-substitution-string parts (or replacement ""))
                      (%append-command-substitution-fields parts replacement)) next)
          (values (%append-command-substitution-char parts #\() (1+ pos))))))

(defun %expand-command-substitution-at
    (context value pos parts len &optional preserve-newlines-p (allow-bare-p t))
  (if allow-bare-p
      (%try-substitution-match
       (%expand-arithmetic-command-substitution-at value pos parts len)
       (%expand-posix-command-substitution-at context value pos parts len preserve-newlines-p)
       (%expand-bare-command-substitution-at context value pos parts preserve-newlines-p)
       (values (%append-command-substitution-char parts (char value pos)) (1+ pos)))
      (%try-substitution-match
       (%expand-arithmetic-command-substitution-at value pos parts len)
       (%expand-posix-command-substitution-at context value pos parts len preserve-newlines-p)
       (values (%append-command-substitution-char parts (char value pos)) (1+ pos)))))

(defun %expand-command-substitutions
    (context value &optional preserve-newlines-p (allow-bare-p t))
  "Expand fish-style and POSIX command substitutions in VALUE."
  (loop with pos = 0
        with parts = (list "")
        with len = (length value)
        while (< pos len)
        do (multiple-value-bind (next-parts next-pos)
               (%expand-command-substitution-at
                context value pos parts len preserve-newlines-p allow-bare-p)
             (setf parts next-parts pos next-pos))
        finally (return parts)))

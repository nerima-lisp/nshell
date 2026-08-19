(in-package #:nshell.application)

;;; Argument expansion and command substitution
;;; All functions deal with expanding shell arguments and running command substitutions.
;;; %execute-command-substitution-fields is forward-referenced here; it lives in
;;; execute-pipeline-control.lisp (after execute-ast-in-context is defined).

(defvar *command-substitution-timeout* 30
  "Maximum seconds for a command substitution to complete before signalling an error.")

(defparameter +here-doc-escaped-dollar+ (code-char #xe000))
(defparameter +here-doc-escaped-backtick+ (code-char #xe001))
(defparameter +here-doc-escaped-backslash+ (code-char #xe002))
(defparameter +here-doc-escaped-command-open+ (code-char #xe003))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro %try-substitution-match (&body forms)
    "Try each form in turn; return the first that produces a non-NIL second value (position).
This macro encodes the Prolog-style rule ordering for command substitution kinds:
arithmetic $((..)) > POSIX $(..) > bare (..) > literal character."
    (if (null (rest forms))
        (first forms)
        (let ((parts (gensym "PARTS")) (pos (gensym "POS")))
          `(multiple-value-bind (,parts ,pos) ,(first forms)
            (if ,pos
                (values ,parts ,pos)
                (%try-substitution-match ,@(rest forms))))))))

(defun %make-pipeline-shell-context (process-fns)
  (make-shell-context
   :environment (nshell.domain.environment:inject-os-environment
                 (nshell.domain.environment:make-default-environment))
   :process-fns process-fns))

(defun execute-command-line (line history dispatcher)
  (nshell.domain.parsing:with-complete-command-line (result ast line)
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-command-entered-event line)))
    (history-kit:history-add history line)
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-command-appended-to-history-event line)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-command-parsed-event ast)))
    (values ast result)))

(defparameter +command-fragment-escape-base+ #xe100)
(defparameter +command-fragment-escape-limit+
  (+ +command-fragment-escape-base+ 256))

(defun %protect-command-fragment-escapes (value positions)
  (let ((protected (copy-seq value)))
    (dolist (position positions protected)
      (when (and (<= 0 position)
                 (< position (length protected)))
        (let ((code (char-code (char protected position))))
          (when (< code 256)
            (setf (char protected position)
                  (code-char (+ +command-fragment-escape-base+ code)))))))))

(defun %restore-command-fragment-escapes (value)
  (with-output-to-string (out)
    (loop for character across value
          for code = (char-code character)
          do (if (and (>= code +command-fragment-escape-base+)
                      (< code +command-fragment-escape-limit+))
                 (write-char
                  (code-char (- code +command-fragment-escape-base+))
                  out)
                 (write-char character out)))))

(defun %append-expanded-fragment-fields (prefixes fields)
  (loop for prefix in prefixes
        append (loop for field in (or fields (list ""))
                     collect (concatenate 'string prefix field))))

(defun %expand-source-fragment-fields (fragment environment)
  (let* ((value (nshell.domain.parsing:command-fragment-value fragment))
         (protected
           (%protect-command-fragment-escapes
            value
            (nshell.domain.parsing:command-fragment-escaped-positions
             fragment))))
    (nshell.domain.expansion:expand-by-quote-style
     (nshell.domain.parsing:command-fragment-quote-style fragment)
     (if environment
         (nshell.domain.expansion:expand-all protected environment)
         (list protected))
     (list protected)
     (if environment
         (list
          (nshell.domain.expansion:expand-double-quoted
           protected environment))
         (list protected)))))

(defun %source-arg-fragments (arg)
  (or (nshell.domain.parsing:command-arg-fragments arg)
      (list
       (nshell.domain.parsing:make-command-fragment
        (nshell.domain.parsing:arg-value arg)
        (nshell.domain.parsing:arg-quote-style arg)))))

(defun %expand-source-arg (arg &optional environment)
  (let ((value (nshell.domain.parsing:arg-value arg)))
    (if (nshell.domain.parsing:arg-here-doc-literal-p arg)
        (list value)
        (let ((fields (list "")))
          (dolist (fragment (%source-arg-fragments arg)
                    (mapcar #'%restore-command-fragment-escapes fields))
            (setf fields
                  (%append-expanded-fragment-fields
                   fields
                   (%expand-source-fragment-fields fragment environment))))))))

(defun %command-node-command-fragments (command-node)
  (or (nshell.domain.parsing:command-node-command-fragments command-node)
      (list
       (nshell.domain.parsing:make-command-fragment
        (nshell.domain.parsing:command-node-command command-node)
        (nshell.domain.parsing:command-node-command-quote-style
         command-node)))))

(defun %expand-command-name-fields-from-fragments (command-node environment)
  (let ((fields (list "")))
    (dolist (fragment (%command-node-command-fragments command-node) fields)
      (let* ((value (nshell.domain.parsing:command-fragment-value fragment))
             (protected
               (%protect-command-fragment-escapes
                value
                (nshell.domain.parsing:command-fragment-escaped-positions
                 fragment)))
             (fragment-fields
               (nshell.domain.expansion:expand-command-name-fields-by-quote-style
                protected
                (nshell.domain.parsing:command-fragment-quote-style
                 fragment)
                environment)))
        (setf fields
              (%append-expanded-fragment-fields fields fragment-fields))))))

(defun %expand-command-name-from-fragments (command-node environment)
  (nshell.domain.expansion:single-command-name-or-error
   (nshell.domain.parsing:command-node-command command-node)
   (%expand-command-name-fields-from-fragments command-node environment)))

(defun %expand-unquoted-source-arg-in-context (context value environment)
  (multiple-value-bind (fields argv-reference-p)
      (nshell.domain.expansion:argv-reference-fields value)
    (if argv-reference-p
        fields
        (loop for expanded in (%expand-command-substitutions context value)
              append (nshell.domain.expansion:expand-all expanded environment)))))

(defun %expand-double-quoted-source-arg-in-context (context value environment)
  (list (apply #'concatenate 'string
               (loop for expanded in
                         (%expand-command-substitutions context value nil nil)
                     collect (nshell.domain.expansion:expand-double-quoted
                              expanded environment)))))

(defun %trim-command-substitution-output (output)
  (let* ((text (or output ""))
         (end (length text)))
    (loop while (and (> end 0)
                     (member (char text (1- end)) '(#\Newline #\Return)))
          do (decf end))
    (subseq text 0 end)))

(defun %command-substitution-fields (output)
  (let ((text (%trim-command-substitution-output output))
        (fields nil)
        (start 0))
    (unless (string= text "")
      (loop for newline = (position #\Newline text :start start)
            do (push (subseq text start newline) fields)
            if newline
              do (setf start (1+ newline))
            else
              do (return)))
    (nreverse fields)))

(defun %append-command-substitution-char (parts ch)
  (mapcar (lambda (part) (concatenate 'string part (string ch))) parts))

(defun %append-command-substitution-fields (parts fields)
  (let ((result nil)
        (values (or fields '(""))))
    (dolist (part parts (nreverse result))
      (dolist (field values)
        (push (concatenate 'string part field) result)))))

(defun %append-command-substitution-string (parts string)
  (mapcar (lambda (part) (concatenate 'string part string)) parts))

(defun %paren-balanced-end (value start)
  "Return the index just past the closing paren that returns depth to zero, or NIL."
  (let ((depth 0))
    (loop for index from start below (length value)
          for ch = (char value index)
          do (cond ((char= ch #\() (incf depth))
                   ((char= ch #\)) (decf depth)
                    (when (zerop depth) (return (1+ index))))))))

(defun %command-sub-fields-at (context value open-paren &optional preserve-newlines-p)
  "Run the command substitution whose opening #\( is at OPEN-PAREN.
Returns (replacement next-pos) on success, or NIL when parens are empty/unbalanced.
%execute-command-substitution-fields is defined later in execute-pipeline-control.lisp."
  (let ((end (nshell.domain.parsing:balanced-substitution-end value open-paren)))
    (when (and end (> end (1+ open-paren)))
      (values (if preserve-newlines-p
                  (%execute-command-substitution-output
                   context (subseq value (1+ open-paren) end))
                  (%execute-command-substitution-fields
                   context (subseq value (1+ open-paren) end)))
              (1+ end)))))

(defun %expand-arithmetic-command-substitution-at (value pos parts len)
  "Match $((expr)) at POS. Returns (parts next-pos) or (nil nil)."
  (when (and (char= (char value pos) #\$)
             (< (+ pos 2) len)
             (char= (char value (1+ pos)) #\()
             (char= (char value (+ pos 2)) #\())
    (let ((end (%paren-balanced-end value (1+ pos))))
      (if end
          (values (%append-command-substitution-string parts (subseq value pos end))
                  end)
          (values (%append-command-substitution-char parts #\$)
                  (1+ pos))))))

(defun %expand-posix-command-substitution-at
    (context value pos parts len &optional preserve-newlines-p)
  "Match $(cmd) at POS. Returns (parts next-pos) or (nil nil)."
  (when (and (char= (char value pos) #\$)
             (< (1+ pos) len)
             (char= (char value (1+ pos)) #\())
    (multiple-value-bind (replacement next)
        (%command-sub-fields-at context value (1+ pos) preserve-newlines-p)
      (if next
          (values (if preserve-newlines-p
                      (%append-command-substitution-string
                       parts (or replacement ""))
                      (%append-command-substitution-fields parts replacement))
                  next)
          (values (%append-command-substitution-char parts #\$) (1+ pos))))))

(defun %expand-bare-command-substitution-at
    (context value pos parts &optional preserve-newlines-p)
  "Match fish-style (cmd) at POS. Returns (parts next-pos) or (nil nil)."
  (when (char= (char value pos) #\()
    (multiple-value-bind (replacement next)
        (%command-sub-fields-at context value pos preserve-newlines-p)
      (if next
          (values (if preserve-newlines-p
                      (%append-command-substitution-string
                       parts (or replacement ""))
                      (%append-command-substitution-fields parts replacement))
                  next)
          (values (%append-command-substitution-char parts #\() (1+ pos))))))

(defun %expand-command-substitution-at
    (context value pos parts len &optional preserve-newlines-p (allow-bare-p t))
  "Try substitution rules in priority order: arithmetic > POSIX > bare > literal."
  (if allow-bare-p
      (%try-substitution-match
       (%expand-arithmetic-command-substitution-at value pos parts len)
       (%expand-posix-command-substitution-at
        context value pos parts len preserve-newlines-p)
       (%expand-bare-command-substitution-at
        context value pos parts preserve-newlines-p)
       (values (%append-command-substitution-char parts (char value pos))
               (1+ pos)))
      (%try-substitution-match
       (%expand-arithmetic-command-substitution-at value pos parts len)
       (%expand-posix-command-substitution-at
        context value pos parts len preserve-newlines-p)
       (values (%append-command-substitution-char parts (char value pos))
               (1+ pos)))))

(defun %expand-command-substitutions
    (context value &optional preserve-newlines-p (allow-bare-p t))
  "Expand command substitutions in VALUE: fish-style (cmd) and POSIX $(cmd).
When ALLOW-BARE-P is false, only POSIX $(cmd) substitutions are executed.
Arithmetic $((expr)) is passed through untouched for the arithmetic expander.
Uses an iterative loop instead of tail-recursion to avoid stack depth limits."
  (loop with pos = 0
        with parts = (list "")
        with len = (length value)
        while (< pos len)
        do (multiple-value-bind (next-parts next-pos)
               (%expand-command-substitution-at
                context value pos parts len preserve-newlines-p allow-bare-p)
             (setf parts next-parts
                   pos next-pos))
        finally (return parts)))

(defun %protect-here-doc-escapes (input)
  "Protect heredoc escapes from the ordinary parameter expander.

Only backslash-dollar, backslash-backtick, backslash-backslash, and
backslash-newline have special meaning in an unquoted heredoc."
  (let ((length (length input)))
    (with-output-to-string (out)
      (loop with pos = 0
            while (< pos length)
            do (let ((ch (char input pos)))
                 (if (and (char= ch #\\)
                          (< (1+ pos) length))
                     (let ((next (char input (1+ pos))))
                       (cond
                         ((char= next #\Newline)
                          (incf pos 2))
                         ((char= next #\$)
                          (if (and (< (+ pos 2) length)
                                   (char= (char input (+ pos 2)) #\())
                              (progn
                                (write-char +here-doc-escaped-command-open+ out)
                                (incf pos 3))
                              (progn
                                (write-char +here-doc-escaped-dollar+ out)
                                (incf pos 2))))
                         ((char= next #\`)
                          (write-char +here-doc-escaped-backtick+ out)
                          (incf pos 2))
                         ((char= next #\\)
                          (write-char +here-doc-escaped-backslash+ out)
                          (incf pos 2))
                         (t
                          (write-char ch out)
                          (incf pos))))
                     (progn
                       (write-char ch out)
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
         (write-string
          (nshell.domain.expansion:expand-double-quoted part environment)
          out))))))

(defun %expand-source-fragment-fields-in-context (context fragment)
  (let* ((value (nshell.domain.parsing:command-fragment-value fragment))
         (protected
           (%protect-command-fragment-escapes
            value
            (nshell.domain.parsing:command-fragment-escaped-positions
             fragment)))
         (environment (shell-context-environment context)))
    (nshell.domain.expansion:expand-by-quote-style
     (nshell.domain.parsing:command-fragment-quote-style fragment)
     (%expand-unquoted-source-arg-in-context context protected environment)
     (list protected)
     (%expand-double-quoted-source-arg-in-context context protected environment))))

(defun %expand-source-arg-in-context (context arg)
  (let ((value (nshell.domain.parsing:arg-value arg)))
    (if (nshell.domain.parsing:arg-here-doc-literal-p arg)
        (list value)
        (let ((fields (list "")))
          (dolist (fragment (%source-arg-fragments arg)
                    (mapcar #'%restore-command-fragment-escapes fields))
            (setf fields
                  (%append-expanded-fragment-fields
                   fields
                   (%expand-source-fragment-fields-in-context
                    context fragment))))))))

(defun %line-command-args (command-node &optional environment)
  (loop for arg in (nshell.domain.parsing:command-node-args command-node)
        append (%expand-source-arg arg environment)))

(defun %line-command-args-in-context (context command-node)
  (loop for arg in (nshell.domain.parsing:command-node-args command-node)
        append (%expand-source-arg-in-context context arg)))

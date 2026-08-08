(in-package #:nshell.application)

;;; Argument expansion and command substitution
;;; All functions deal with expanding shell arguments and running command substitutions.
;;; %execute-command-substitution-fields is forward-referenced here; it lives in
;;; execute-pipeline-control.lisp (after execute-ast-in-context is defined).

(defvar *command-substitution-timeout* 30
  "Maximum seconds for a command substitution to complete before signalling an error.")

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

(defun %make-pipeline-shell-context ()
  (make-shell-context
   :environment (nshell.domain.environment:inject-os-environment
                 (nshell.domain.environment:make-default-environment))))

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

(defun %expand-source-arg (arg &optional environment)
  (let ((value (nshell.domain.parsing:arg-value arg)))
    (if (nshell.domain.parsing:arg-here-doc-literal-p arg)
        (list value)
        (nshell.domain.expansion:expand-by-quote-style
         (nshell.domain.parsing:arg-quote-style arg)
         (if environment
             (nshell.domain.expansion:expand-all value environment)
             (list value))
         (list value)
         (if environment
             (list (nshell.domain.expansion:expand-double-quoted value environment))
             (list value))))))

(defun %expand-unquoted-source-arg-in-context (context value environment)
  (multiple-value-bind (fields argv-reference-p)
      (nshell.domain.expansion:argv-reference-fields value)
    (if argv-reference-p
        fields
        (loop for expanded in (%expand-command-substitutions context value)
              append (nshell.domain.expansion:expand-all expanded environment)))))

(defun %expand-double-quoted-source-arg-in-context (context value environment)
  (list (apply #'concatenate 'string
               (loop for expanded in (%expand-command-substitutions context value)
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

(defun %command-sub-fields-at (context value open-paren)
  "Run the command substitution whose opening #\( is at OPEN-PAREN.
Returns (fields next-pos) on success, or NIL when parens are empty/unbalanced.
%execute-command-substitution-fields is defined later in execute-pipeline-control.lisp."
  (let ((end (nshell.domain.parsing::%balanced-substitution-end value open-paren)))
    (when (and end (> end (1+ open-paren)))
      (values (%execute-command-substitution-fields
               context (subseq value (1+ open-paren) end))
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

(defun %expand-posix-command-substitution-at (context value pos parts len)
  "Match $(cmd) at POS. Returns (parts next-pos) or (nil nil)."
  (when (and (char= (char value pos) #\$)
             (< (1+ pos) len)
             (char= (char value (1+ pos)) #\())
    (multiple-value-bind (fields next)
        (%command-sub-fields-at context value (1+ pos))
      (if next
          (values (%append-command-substitution-fields parts fields) next)
          (values (%append-command-substitution-char parts #\$) (1+ pos))))))

(defun %expand-bare-command-substitution-at (context value pos parts)
  "Match fish-style (cmd) at POS. Returns (parts next-pos) or (nil nil)."
  (when (char= (char value pos) #\()
    (multiple-value-bind (fields next)
        (%command-sub-fields-at context value pos)
      (if next
          (values (%append-command-substitution-fields parts fields) next)
          (values (%append-command-substitution-char parts #\() (1+ pos))))))

(defun %expand-command-substitution-at (context value pos parts len)
  "Try substitution rules in priority order: arithmetic > POSIX > bare > literal."
  (%try-substitution-match
   (%expand-arithmetic-command-substitution-at value pos parts len)
   (%expand-posix-command-substitution-at context value pos parts len)
   (%expand-bare-command-substitution-at context value pos parts)
   (values (%append-command-substitution-char parts (char value pos)) (1+ pos))))

(defun %expand-command-substitutions (context value)
  "Expand command substitutions in VALUE: fish-style (cmd) and POSIX $(cmd).
Arithmetic $((expr)) is passed through untouched for the arithmetic expander.
Uses an iterative loop instead of tail-recursion to avoid stack depth limits."
  (loop with pos = 0
        with parts = (list "")
        with len = (length value)
        while (< pos len)
        do (multiple-value-bind (next-parts next-pos)
               (%expand-command-substitution-at context value pos parts len)
             (setf parts next-parts
                   pos next-pos))
        finally (return parts)))

(defun %expand-source-arg-in-context (context arg)
  (let ((value (nshell.domain.parsing:arg-value arg))
        (environment (shell-context-environment context)))
    (if (nshell.domain.parsing:arg-here-doc-literal-p arg)
        (list value)
        (nshell.domain.expansion:expand-by-quote-style
         (nshell.domain.parsing:arg-quote-style arg)
         (%expand-unquoted-source-arg-in-context context value environment)
         (list value)
         (%expand-double-quoted-source-arg-in-context context value environment)))))

(defun %line-command-args (command-node &optional environment)
  (loop for arg in (nshell.domain.parsing:command-node-args command-node)
        append (%expand-source-arg arg environment)))

(defun %line-command-args-in-context (context command-node)
  (loop for arg in (nshell.domain.parsing:command-node-args command-node)
        append (%expand-source-arg-in-context context arg)))

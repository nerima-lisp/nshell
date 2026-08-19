(in-package #:nshell.application)


(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro define-builtin (name lambda-list ignore-variables &body body)
    `(defun ,name ,lambda-list
       ,@(when ignore-variables
           `((declare (ignore ,@ignore-variables))))
       ,@body)))

(define-builtin %builtin-echo (context args) (context)
  (values (format nil "~{~a~^ ~}~%" args) 0))

(defun %printf-pad (text width left-p &optional (pad-character #\Space))
  (let ((padding (max 0 (- (or width 0) (length text)))))
    (if (zerop padding)
        text
        (let ((padding-text (make-string padding :initial-element pad-character)))
          (if left-p
              (concatenate 'string text padding-text)
              (concatenate 'string padding-text text))))))

(defun %printf-flag-p (flags flag)
  (find flag flags :test #'char=))

(defun %printf-read-escape (text index)
  (if (>= index (length text))
      (values "\\" index nil)
      (let ((character (char text index)))
        (case character
          (#\a (values (string (code-char 7)) (1+ index) nil))
          (#\b (values (string #\Backspace) (1+ index) nil))
          (#\c (values "" (1+ index) t))
          (#\e (values (string (code-char 27)) (1+ index) nil))
          (#\f (values (string #\Page) (1+ index) nil))
          (#\n (values (string #\Newline) (1+ index) nil))
          (#\r (values (string #\Return) (1+ index) nil))
          (#\t (values (string #\Tab) (1+ index) nil))
          (#\v (values (string (code-char 11)) (1+ index) nil))
          (#\\ (values (string #\\) (1+ index) nil))
          (#\0
           (let ((cursor (1+ index))
                 (value 0)
                 (digits 0))
             (loop while (and (< cursor (length text))
                              (< digits 3)
                              (find (char text cursor) "01234567" :test #'char=))
                   do (setf value (+ (* value 8)
                                      (- (char-code (char text cursor))
                                         (char-code #\0)))
                          cursor (1+ cursor)
                          digits (1+ digits)))
             (values (string (or (code-char value) #\Null)) cursor nil)))
          (otherwise (values (string character) (1+ index) nil))))))

(defun %printf-expand-escapes (text)
  (let* ((stop nil)
        (result
          (with-output-to-string (out)
            (loop with index = 0
                  while (< index (length text))
                  do (if (char= (char text index) #\\)
                         (multiple-value-bind (replacement next-index stop-p)
                             (%printf-read-escape text (1+ index))
                           (write-string replacement out)
                           (setf index next-index
                                 stop stop-p)
                           (when stop
                             (return)))
                         (progn
                           (write-char (char text index) out)
                           (incf index)))))))
    (values result stop)))

(defun %printf-parse-integer (argument)
  (handler-case
      (values (parse-integer argument :junk-allowed nil) t)
    (error () (values 0 nil))))

(defun %printf-parse-real (argument)
  (handler-case
      (let ((*read-eval* nil))
        (multiple-value-bind (value position)
            (read-from-string argument nil nil)
          (if (and (realp value)
                   (= position (length argument)))
              (values (coerce value 'double-float) t)
              (values 0d0 nil))))
    (error () (values 0d0 nil))))

(defun %printf-integer-text (number conversion flags precision)
  (let* ((negative (minusp number))
         (unsigned (if negative (abs number) number))
         (base (case conversion
                 ((#\x #\X) 16)
                 (#\o 8)
                 (otherwise 10)))
         (digits (case base
                   (16 (format nil "~x" unsigned))
                   (8 (format nil "~o" unsigned))
                   (otherwise (format nil "~d" unsigned))))
         (digits (if (char= conversion #\X)
                     (string-upcase digits)
                     digits))
         (digits (if precision
                     (concatenate 'string
                                  (make-string (max 0 (- precision (length digits)))
                                               :initial-element #\0)
                                  digits)
                     digits))
         (prefix (if (and (%printf-flag-p flags #\#)
                         (not (zerop unsigned)))
                     (case conversion
                       (#\x "0x")
                       (#\X "0X")
                       (#\o "0")
                       (otherwise ""))
                     ""))
         (sign (cond
                 (negative "-")
                 ((%printf-flag-p flags #\+) "+")
                 ((%printf-flag-p flags #\Space) " ")
                 (t ""))))
    (concatenate 'string sign prefix digits)))

(defun %printf-format-value (argument conversion flags width precision)
  (case conversion
    (#\s
     (values (%printf-pad (if precision
                              (subseq argument 0 (min precision (length argument)))
                              argument)
                          width
                          (%printf-flag-p flags #\-))
             t
             nil))
    (#\b
     (multiple-value-bind (text stop-p) (%printf-expand-escapes argument)
       (values (%printf-pad (if precision
                              (subseq text 0 (min precision (length text)))
                              text)
                          width
                          (%printf-flag-p flags #\-))
               t
               stop-p)))
    (#\c
     (values (%printf-pad (if (plusp (length argument))
                              (string (char argument 0))
                              (string #\Null))
                          width
                          (%printf-flag-p flags #\-))
             t
             nil))
    ((#\d #\i #\u #\o #\x #\X)
     (multiple-value-bind (number valid-p) (%printf-parse-integer argument)
       (values (%printf-pad (%printf-integer-text number conversion flags precision)
                            width
                            (%printf-flag-p flags #\-)
                            (if (and (%printf-flag-p flags #\0)
                                     (not (%printf-flag-p flags #\-))
                                     (null precision))
                                #\0
                                #\Space))
               valid-p
               nil)))
    ((#\e #\E #\f #\g #\G)
     (multiple-value-bind (number valid-p) (%printf-parse-real argument)
       (let* ((digits (or precision 6))
              (directive (case conversion
                           ((#\e #\E) "e")
                           ((#\g #\G) "g")
                           (otherwise "f")))
              (text (format nil
                            (concatenate 'string "~," (princ-to-string digits) directive)
                            number))
              (text (if (and (member conversion '(#\E #\G))
                             (position #\e text))
                        (substitute #\E #\e text)
                        text))
              (text (if (and (not (minusp number))
                             (%printf-flag-p flags #\+))
                        (concatenate 'string "+" text)
                        (if (and (not (minusp number))
                                 (%printf-flag-p flags #\Space))
                            (concatenate 'string " " text)
                            text))))
         (values (%printf-pad text width (%printf-flag-p flags #\-)
                              (if (and (%printf-flag-p flags #\0)
                                       (not (%printf-flag-p flags #\-)))
                                  #\0
                                  #\Space))
                 valid-p
                 nil))))
    (otherwise (values "" nil nil))))

(defun %printf-format-once (format-string arguments)
  (let ((format-index 0)
        (argument-index 0)
        (argument-conversion-p nil)
        (valid-p t)
        (stop-p nil))
    (values
     (with-output-to-string (out)
       (loop while (< format-index (length format-string))
             do (let ((character (char format-string format-index)))
                  (if (char/= character #\%)
                      (if (char= character #\\)
                          (multiple-value-bind (replacement next-index escape-stop-p)
                              (%printf-read-escape format-string (1+ format-index))
                            (write-string replacement out)
                            (setf format-index next-index
                                  stop-p escape-stop-p)
                            (when stop-p
                              (return)))
                          (progn
                            (write-char character out)
                            (incf format-index)))
                      (progn
                        (incf format-index)
                        (if (>= format-index (length format-string))
                            (progn
                              (setf valid-p nil)
                              (return))
                            (if (char= (char format-string format-index) #\%)
                                (progn
                                  (write-char #\% out)
                                  (incf format-index))
                                (let ((flags ""))
                                  (loop while (and (< format-index (length format-string))
                                                   (find (char format-string format-index)
                                                         "-+0# "
                                                         :test #'char=))
                                        do (setf flags
                                                 (concatenate 'string
                                                              flags
                                                              (string (char format-string format-index)))
                                             format-index (1+ format-index)))
                                  (let ((width-start format-index)
                                        (precision nil))
                                    (loop while (and (< format-index (length format-string))
                                                     (digit-char-p (char format-string format-index)))
                                          do (incf format-index))
                                    (let ((width (when (> format-index width-start)
                                                   (parse-integer format-string
                                                                  :start width-start
                                                                  :end format-index))))
                                      (when (and (< format-index (length format-string))
                                                 (char= (char format-string format-index) #\.))
                                        (incf format-index)
                                        (let ((precision-start format-index))
                                          (loop while (and (< format-index (length format-string))
                                                           (digit-char-p (char format-string format-index)))
                                                do (incf format-index))
                                          (setf precision
                                                (if (= precision-start format-index)
                                                    0
                                                    (parse-integer format-string
                                                                   :start precision-start
                                                                   :end format-index)))))
                                      (loop while (and (< format-index (length format-string))
                                                       (find (char format-string format-index)
                                                             "hlLjzt"
                                                             :test #'char=))
                                            do (incf format-index))
                                      (if (>= format-index (length format-string))
                                          (progn
                                            (setf valid-p nil)
                                            (return))
                                          (let ((conversion (char format-string format-index)))
                                            (incf format-index)
                                            (setf argument-conversion-p t)
                                            (if (find conversion "sbcdiuoxXeEfFgG"
                                                      :test #'char=)
                                                (let ((argument
                                                        (if (< argument-index (length arguments))
                                                            (nth argument-index arguments)
                                                            "")))
                                                  (incf argument-index)
                                                  (multiple-value-bind (text value-valid-p value-stop-p)
                                                      (%printf-format-value argument conversion flags width precision)
                                                    (write-string text out)
                                                    (unless value-valid-p
                                                      (setf valid-p nil))
                                                    (when value-stop-p
                                                      (setf stop-p t)
                                                      (return))))
                                                (progn
                                                  (setf valid-p nil)
                                                  (return)))))))))))))))
     argument-index
     argument-conversion-p
     valid-p
     stop-p)))

(define-builtin %builtin-printf (context args) (context)
  (let ((arguments (if (and args (string= (first args) "--"))
                       (rest args)
                       args)))
    (if (null arguments)
        (values nil 0)
        (let* ((format-string (first arguments))
              (remaining (rest arguments))
              (valid-p t)
              (output
                (with-output-to-string (out)
                  (loop
                    (multiple-value-bind (text consumed argument-conversion-p once-valid-p stop-p)
                        (%printf-format-once format-string remaining)
                      (write-string text out)
                      (setf valid-p (and valid-p once-valid-p)
                            remaining (nthcdr consumed remaining))
                      (when (or stop-p
                                (not once-valid-p)
                                (null remaining)
                                (not argument-conversion-p))
                        (return)))))))
          (values output (if valid-p 0 1))))))

(define-builtin %builtin-pwd (context args) (args)
  (values (format nil "~a~%" (namestring (funcall (%filesystem-fn context :cwd)))) 0))

(define-builtin %builtin-ls (context args) (args)
  (handler-case
      (values
       (with-output-to-string (out)
         (dolist (file (funcall (%filesystem-fn context :list-dir)
                                (funcall (%filesystem-fn context :cwd))))
           (format out "~a~%" (file-namestring file))))
       0)
    (error (condition)
      (values (format nil "ls: ~a~%" condition) 1))))

(defun %builtin-cd (context args)
  (handler-case
      (progn
        (when (> (length args) 1)
          (return-from %builtin-cd (%builtin-usage "cd" "cd [directory]")))
        (let* ((environment (shell-context-environment context))
               (directory
                 (cond
                   ((null args)
                    (or (and environment
                             (nshell.domain.environment:env-get environment "HOME"))
                        (error "HOME is not set")))
                   ((string= (first args) "-")
                    (if (and environment
                             (nshell.domain.environment:env-defined-p environment "OLDPWD"))
                        (nshell.domain.environment:env-get environment "OLDPWD")
                        (error "OLDPWD is not set")))
                   (t (first args))))
               (old-cwd (funcall (%filesystem-fn context :cwd))))
          (funcall (%filesystem-fn context :chdir) directory)
          (let ((new-cwd (funcall (%filesystem-fn context :cwd))))
            (when environment
              (setf environment
                    (nshell.domain.environment:env-set
                     environment
                     "OLDPWD"
                     (namestring old-cwd)
                     (if (nshell.domain.environment:env-defined-p environment "OLDPWD")
                         (nshell.domain.environment:env-exported-p environment "OLDPWD")
                         t))
                    environment
                    (nshell.domain.environment:env-set
                     environment
                     "PWD"
                     (namestring new-cwd)
                     (if (nshell.domain.environment:env-defined-p environment "PWD")
                         (nshell.domain.environment:env-exported-p environment "PWD")
                         t))
                    (shell-context-environment context) environment))
            (values (when (and args (string= (first args) "-"))
                      (format nil "~a~%" (namestring new-cwd)))
                    0))))
    (error (condition)
      (values (format nil "cd: ~a~%" condition) 1))))

(defun %parse-exit-status (argument)
  (handler-case
      (values (mod (parse-integer argument :junk-allowed nil) 256) t)
    (error ()
      (values nil nil))))

(define-builtin %builtin-exit (context args) ()
  (cond
    ((> (length args) 1)
     (values "exit: too many arguments~%" 1))
    (t
     (multiple-value-bind (status valid-p)
         (if args
             (%parse-exit-status (first args))
             (values (shell-context-last-exit-code context) t))
       (if valid-p
           (progn
             (setf (shell-context-last-exit-code context) status)
             (%stop-shell-context context)
             (values nil status))
           (progn
             (setf (shell-context-last-exit-code context) 2)
             (values "exit: numeric argument required~%" 2)))))))

(define-builtin %builtin-true (context args) (context args)
  (values nil 0))

(define-builtin %builtin-false (context args) (context args)
  (values nil 1))

(defun %invert-status-code (code)
  (if (zerop (or code 0)) 1 0))

(defun %builtin-not (context args)
  (if (null args)
      (%builtin-usage "not" "not command [args...]" 2)
      (let* ((command (first args))
             (command-args (rest args)))
        (multiple-value-bind (output code)
            (%execute-command-by-name-in-context context command command-args)
          (values output (%invert-status-code code))))))

(defun %builtin-exec (context args) (declare (ignore context)) (if args (sb-ext:quit :unix-status (nshell.infrastructure.acl:run-external-exec (first args) (rest args))) (%builtin-usage "exec" "exec command [args...]")))

(defun %contains-usage ()
  (%builtin-usage
   "contains"
   (%builtin-usage-clauses-summary +builtin-contains-usage-clauses+)))

(defun %parse-contains-args (args)
  (let ((index-p nil)
        (remaining args))
    (%with-option-arguments (remaining option)
        (return)
        (return-from %parse-contains-args
          (values nil nil
                  (format nil "contains: unknown option ~a~%" option)))
        (return)
      ((cdr (assoc option +contains-option-specs+ :test #'string=))
       (setf index-p t
             remaining (rest remaining))))
    (values index-p remaining nil)))

(defun %contains-match-indexes (needle values)
  (loop for value in values
        for index from 1
        when (string= needle value)
          collect index))

(defun %builtin-help-entry-output (entry &optional (prefix ""))
  (format nil "~a~a - ~a~%"
          prefix
          (getf entry :synopsis)
          (getf entry :description)))

(defun %builtin-help-overview-output ()
  (with-output-to-string (out)
    (format out "nshell builtin commands:~%")
    (dolist (entry (nshell.domain.completion:builtin-help-entries))
      (write-string (%builtin-help-entry-output entry "  ") out))))

(defun %builtin-contains (context args)
  (declare (ignore context))
  (multiple-value-bind (index-p operands error-output)
      (%parse-contains-args args)
    (cond
      (error-output
       (values error-output 2))
      ((null operands)
      (values (%contains-usage) 2))
      (t
       (let* ((needle (first operands))
              (values (rest operands))
              (indexes (%contains-match-indexes needle values)))
         (values (when index-p
                   (with-output-to-string (out)
                     (dolist (index indexes)
                       (format out "~d~%" index))))
                 (if indexes 0 1)))))))

(defun %builtin-count (context args)
  "Print the number of ARGS (like fish's count). Exit status is 0 when there is
at least one argument, otherwise 1 -- which makes `count $argv` usable in tests."
  (declare (ignore context))
  (let ((n (length args)))
    (values (format nil "~d~%" n) (if (plusp n) 0 1))))

(defun %seq-parse-args (args)
  "Parse seq ARGS into (values FIRST STEP LAST) integers, or NIL on bad input.
Forms: seq LAST | seq FIRST LAST | seq FIRST STEP LAST."
  (handler-case
      (let ((nums (mapcar (lambda (a) (parse-integer a :junk-allowed nil)) args)))
        (case (length nums)
          (1 (values 1 1 (first nums)))
          (2 (values (first nums) 1 (second nums)))
          (3 (values (first nums) (second nums) (third nums)))
          (t nil)))
    (error () nil)))

(defun %seq-values (first step last)
  (cond
    ((zerop step) nil)
    ((plusp step) (loop for i from first to last by step collect i))
    (t (loop for i from first downto last by (- step) collect i))))

(defun %builtin-seq (context args)
  "Print a sequence of integers, one per line (like seq / fish's seq).
Usage: seq LAST | seq FIRST LAST | seq FIRST STEP LAST. Useful with for loops:
`for i in (seq 1 10)`."
  (declare (ignore context))
  (if (or (null args) (> (length args) 3))
      (values (format nil "seq: usage: seq [FIRST [STEP]] LAST~%") 2)
      (multiple-value-bind (first step last) (%seq-parse-args args)
        (cond
          ((null first)
           (values (format nil "seq: arguments must be integers~%") 2))
          ((zerop step)
           (values (format nil "seq: STEP must not be zero~%") 2))
          (t
           (let ((vals (%seq-values first step last)))
             (values (when vals (format nil "~{~d~%~}" vals)) 0)))))))

(defun %builtin-help (context args)
  (declare (ignore context))
  (if args
      (let ((entry (find (first args)
                         (nshell.domain.completion:builtin-help-entries)
                         :key (lambda (entry) (getf entry :command))
                         :test #'string=)))
        (if entry
            (values (%builtin-help-entry-output entry) 0)
            (values (format nil "help: no help for ~a~%" (first args)) 1)))
      (values (%builtin-help-overview-output) 0)))

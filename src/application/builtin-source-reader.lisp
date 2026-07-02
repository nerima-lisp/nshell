(in-package #:nshell.application)

(defun %append-source-here-document-line (text line)
  (concatenate 'string
               text
               (if (and (plusp (length text))
                        (char= (char text (1- (length text))) #\Newline))
                   ""
                   (format nil "~%"))
               line
               (format nil "~%")))

(defun %append-source-continuation (text line result)
  (if (or (nshell.domain.parsing:parse-diagnostic-kind-p
           result :incomplete-here-document)
          (and (nshell.domain.parsing:parse-result-incomplete result)
               (not (nshell.domain.parsing:parse-diagnostic-kind-p
                     result :trailing-continuation))
               (not (nshell.domain.parsing:parse-diagnostic-kind-p
                     result :unclosed-block))))
      (%append-source-here-document-line text line)
      (concatenate 'string
                   text
                   (if (nshell.domain.parsing:parse-diagnostic-kind-p
                       result :trailing-continuation)
                       " "
                       "; ")
                   line)))

(defun %collect-source-lines (stream)
  (loop for line = (read-line stream nil nil)
        while line
        collect line))

(defparameter +source-definition-opening-keywords+
  '("if" "for" "while" "switch" "begin" "function"))

(defparameter +source-definition-end-keyword+ "end")

(defun %source-line-segments (line)
  (multiple-value-bind (tokens)
      (nshell.domain.parsing:tokenize line)
    (let ((segments nil)
          (segment-start 0))
      (loop for token in tokens
            do (when (member (nshell.domain.parsing:token-type token)
                             '(:semicolon :ampersand)
                             :test #'eq)
                 (let ((segment (string-trim '(#\Space #\Tab)
                                             (subseq line
                                                     segment-start
                                                     (nshell.domain.parsing:token-start token)))))
                   (when (plusp (length segment))
                     (push segment segments)))
                 (setf segment-start (nshell.domain.parsing:token-end token)))
            finally
              (let ((segment (string-trim '(#\Space #\Tab)
                                          (subseq line segment-start))))
                (when (plusp (length segment))
                  (push segment segments)))
              (return (nreverse segments))))))

(defun %function-start-p (line)
  (multiple-value-bind (tokens)
      (nshell.domain.parsing:tokenize line)
    (let ((words nil))
      (dolist (token tokens)
        (let ((type (nshell.domain.parsing:token-type token)))
          (when (member type '(:semicolon :ampersand :pipe :and :or)
                        :test #'eq)
            (return))
          (when (eq type :word)
            (push (nshell.domain.parsing:token-value token) words))))
      (let ((words (nreverse words)))
        (when (and (>= (length words) 2)
                   (string= (first words) "function"))
          (second words))))))

(defun %source-definition-line-depth-delta (line)
  (multiple-value-bind (tokens)
      (nshell.domain.parsing:tokenize line)
    (let ((expect-command t)
          (delta 0))
      (dolist (token tokens delta)
        (let ((type (nshell.domain.parsing:token-type token))
              (value (nshell.domain.parsing:token-value token)))
          (cond
            ((and expect-command (eq type :word))
             (when (and (stringp value)
                        (member value +source-definition-opening-keywords+
                                :test #'string=))
               (incf delta))
             (when (and (stringp value)
                        (string= value +source-definition-end-keyword+))
               (decf delta))
             (setf expect-command nil))
            ((member type '(:semicolon :and :or :ampersand :pipe))
             (setf expect-command t))
            ((eq type :redirect))
            ((eq type :word)
             (setf expect-command nil))))))))

(defun %source-function-definition-consume-lines (source depth body)
  (loop while source
        for body-line = (pop source)
        for line-delta = (%source-definition-line-depth-delta body-line)
        do (if (and (= depth 1)
                    (= line-delta -1))
               (return (values t source depth body))
               (progn
                 (push body-line body)
                 (incf depth line-delta)))
        finally (return (values nil source depth body))))

(defun %source-function-definition-finish (context name body inline-lines remaining source-path)
  (let ((function-body (nreverse body))
        (tail (append inline-lines remaining)))
    (setf (gethash name (shell-context-function-table context))
          function-body
          (gethash name (shell-context-function-source-table context))
          source-path)
    (values tail nil 0 nil)))

(defun %source-function-definition-scan (context name body inline-lines remaining depth source-path)
  (let ((closed nil))
    (multiple-value-bind (inline-closed inline-tail inline-depth new-body)
        (%source-function-definition-consume-lines inline-lines depth body)
      (setf closed inline-closed
            inline-lines inline-tail
            depth inline-depth
            body new-body))
    (when (not closed)
      (multiple-value-bind (remaining-closed remaining-tail remaining-depth new-body)
          (%source-function-definition-consume-lines remaining depth body)
        (setf closed remaining-closed
              remaining remaining-tail
              depth remaining-depth
              body new-body)))
    (if closed
        (%source-function-definition-finish context name body inline-lines remaining source-path)
        (values nil (format nil "source: function ~a missing end~%" name) 2 t))))

(defun %source-function-definition (context name line lines source-path)
  (let ((body nil)
        (depth 1)
        (inline-lines (rest (%source-line-segments line))))
    (%source-function-definition-scan context name body inline-lines lines depth source-path)))

(defun %source-lines-handle-function-start (context line remaining source-path output)
  (multiple-value-bind (tail chunk exit-code stop-p)
      (%source-function-definition context (%function-start-p line)
                                   line remaining source-path)
    (values tail
            (%source-lines-add-chunk chunk output)
            exit-code
            stop-p)))

(defun %source-lines-add-chunk (chunk output)
  (if chunk (cons chunk output) output))

(defun %source-line-needs-more-input-p (result)
  (or (nshell.domain.parsing:parse-diagnostic-kind-p
       result :unclosed-block)
      (nshell.domain.parsing:parse-diagnostic-kind-p
       result :trailing-continuation)
      (nshell.domain.parsing:parse-diagnostic-kind-p
       result :incomplete-here-document)
      (and (nshell.domain.parsing:parse-result-incomplete result)
           (not (nshell.domain.parsing:parse-errors result)))))

(defun %source-lines-handle-source-form (context line remaining output)
  (let ((text line)
        (tail remaining)
        (result (nshell.domain.parsing:parse-command-line line)))
    (loop while (and tail (%source-line-needs-more-input-p result))
          do (setf text (%append-source-continuation text (pop tail) result)
                   result (nshell.domain.parsing:parse-command-line text)))
    (if (nshell.domain.parsing:parse-complete-p result)
        (multiple-value-bind (chunk exit-code)
            (%execute-source-line context text)
          (values tail
                  (%source-lines-add-chunk chunk output)
                  exit-code
                  nil))
        (multiple-value-bind (chunk exit-code)
            (%source-line-parse-error-result result)
          (values tail
                  (%source-lines-add-chunk chunk output)
                  exit-code
                  t)))))

(defun %comment-or-blank-source-line-p (line)
  "True for blank lines and whole-line comments (including a leading #! shebang),
which are skipped rather than parsed."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) line)))
    (or (string= trimmed "")
        (char= (char trimmed 0) #\#))))

(defun %source-lines (context lines &optional source-path)
  (let ((output nil)
        (code 0)
        (remaining lines))
    (loop while remaining
          for line = (pop remaining)
          do (cond
               ;; Skip blank lines and whole-line comments / shebangs.
               ((%comment-or-blank-source-line-p line) nil)
               ((%function-start-p line)
                (multiple-value-bind (tail new-output exit-code stop-p)
                    (%source-lines-handle-function-start context line remaining
                                                         source-path output)
                  (setf remaining tail
                        output new-output
                        code exit-code)
                  (when stop-p
                    (return))))
               (t
                (multiple-value-bind (tail new-output exit-code stop-p)
                    (%source-lines-handle-source-form context line remaining output)
                  (setf remaining tail
                        output new-output
                        code exit-code)
                  (when stop-p
                    (return))))))
    (values (apply #'concatenate 'string (nreverse output)) code)))

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

(defun collect-source-lines (stream)
  "Collect source lines from STREAM for application-level batch execution."
  (%collect-source-lines stream))

(defparameter +source-definition-opening-keywords+
  '("if" "for" "while" "switch" "begin" "function"))

(defparameter +source-definition-end-keyword+ "end")

(defstruct (%source-function-consumption
            (:constructor %make-source-function-consumption
                (closed-p remaining-lines depth body-lines)))
  (closed-p nil :type boolean :read-only t)
  (remaining-lines nil :type list :read-only t)
  (depth 0 :type integer :read-only t)
  (body-lines nil :type list :read-only t))

(defstruct (%source-function-definition-result
            (:constructor %make-source-function-definition-result
                (remaining-lines output-chunk exit-code stop-p)))
  (remaining-lines nil :type list :read-only t)
  (output-chunk nil :type (or null string) :read-only t)
  (exit-code 0 :type integer :read-only t)
  (stop-p nil :type boolean :read-only t))

(defstruct (%source-lines-step-result
            (:constructor %make-source-lines-step-result
                (remaining-lines output-chunks exit-code stop-p)))
  (remaining-lines nil :type list :read-only t)
  (output-chunks nil :type list :read-only t)
  (exit-code 0 :type integer :read-only t)
  (stop-p nil :type boolean :read-only t))

(defun %source-line-segments (line)
  (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                 (nshell.domain.parsing:tokenize line))))
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
  (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                 (nshell.domain.parsing:tokenize line))))
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
  (let ((tokens (nshell.domain.parsing:tokenization-result-tokens
                 (nshell.domain.parsing:tokenize line))))
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
               (return (%make-source-function-consumption
                        t source depth body))
               (progn
                 (push body-line body)
                 (incf depth line-delta)))
        finally
           (return (%make-source-function-consumption
                    nil source depth body))))

(defun %source-function-definition-finish (context name body inline-lines remaining source-path)
  (let ((function-body (nreverse body))
        (tail (append inline-lines remaining)))
    (%store-shell-function-definition context name function-body source-path)
    (%make-source-function-definition-result tail nil 0 nil)))

(defun %source-function-definition-scan (context name body inline-lines remaining depth source-path)
  (let* ((inline-consumption
           (%source-function-definition-consume-lines inline-lines depth body))
         (closed (%source-function-consumption-closed-p inline-consumption)))
    (setf inline-lines (%source-function-consumption-remaining-lines
                        inline-consumption)
          depth (%source-function-consumption-depth inline-consumption)
          body (%source-function-consumption-body-lines inline-consumption))
    (when (not closed)
      (let ((remaining-consumption
              (%source-function-definition-consume-lines remaining depth body)))
        (setf closed (%source-function-consumption-closed-p remaining-consumption)
              remaining (%source-function-consumption-remaining-lines
                         remaining-consumption)
              depth (%source-function-consumption-depth remaining-consumption)
              body (%source-function-consumption-body-lines
                    remaining-consumption))))
    (if closed
        (%source-function-definition-finish context name body inline-lines remaining source-path)
        (%make-source-function-definition-result
         nil
         (format nil "source: function ~a missing end~%" name)
         2
         t))))

(defun %source-function-definition (context name line lines source-path)
  (let ((body nil)
        (depth 1)
        (inline-lines (rest (%source-line-segments line))))
    (%source-function-definition-scan context name body inline-lines lines depth source-path)))

(defun %source-lines-handle-function-start (context line remaining source-path output)
  (let ((result (%source-function-definition context (%function-start-p line)
                                             line remaining source-path)))
    (%make-source-lines-step-result
     (%source-function-definition-result-remaining-lines result)
     (%source-lines-add-chunk
      (%source-function-definition-result-output-chunk result)
      output)
     (%source-function-definition-result-exit-code result)
     (%source-function-definition-result-stop-p result))))

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
          (%make-source-lines-step-result
           tail
           (%source-lines-add-chunk chunk output)
           exit-code
           nil))
        (multiple-value-bind (chunk exit-code)
            (%source-line-parse-error-result result)
          (%make-source-lines-step-result
           tail
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
                (let ((step (%source-lines-handle-function-start
                             context line remaining source-path output)))
                  (setf remaining (%source-lines-step-result-remaining-lines step)
                        output (%source-lines-step-result-output-chunks step)
                        code (%source-lines-step-result-exit-code step))
                  (%record-last-exit-code context code)
                  (when (or (%source-lines-step-result-stop-p step)
                            (not (shell-context-running context)))
                    (return))))
               (t
                (let ((step (%source-lines-handle-source-form
                             context line remaining output)))
                  (setf remaining (%source-lines-step-result-remaining-lines step)
                        output (%source-lines-step-result-output-chunks step)
                        code (%source-lines-step-result-exit-code step))
                  (%record-last-exit-code context code)
                  (when (or (%source-lines-step-result-stop-p step)
                            (not (shell-context-running context)))
                    (return))))))
    (values (apply #'concatenate 'string (nreverse output)) code)))

(defun source-lines (context lines &optional source-path)
  "Execute source LINES in CONTEXT through the application source use case."
  (%source-lines context lines source-path))

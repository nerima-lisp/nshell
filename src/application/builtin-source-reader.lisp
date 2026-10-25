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
               ;; A definition that opens after another command on the same
               ;; line: run what came first, then read the definition whole.
               ((and (not (%function-start-p line))
                     (source-line-function-split line))
                (multiple-value-bind (prefix definition)
                    (source-line-function-split line)
                  (setf remaining (list* prefix definition remaining))))
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

(progn
  (defun %source-new-reader-route-enabled-p ()
    (equal "sexp" (uiop:getenv "NSHELL_READER")))

  (defun %source-reader-scan-result (context source)
    (nshell.domain.parsing:scan-input
     source
     :reader-context :auto
     :head-classifier
     (lambda (head-source)
       (classify-sexp-head context head-source))))

  (defun %source-evaluate-reader-submission (context source source-path source-map)
  (labels ((source-span-in-file (span)
             (let* ((start (and (consp span) (first span)))
                    (end (and (consp span) (second span)))
                    (map-length (if (vectorp source-map)
                                    (length source-map)
                                    0)))
               (if (and (vectorp source-map)
                        (integerp start)
                        (integerp end)
                        (<= 0 start end map-length)
                        (or (= start end)
                            (and (consp (aref source-map start))
                                 (consp (aref source-map (1- end))))))
                   (if (= start end)
                       (let ((anchor
                               (if (< start map-length)
                                   (first (aref source-map start))
                                   (if (plusp map-length)
                                       (second (aref source-map
                                                     (1- map-length)))
                                       0))))
                         (list anchor anchor))
                       (list (first (aref source-map start))
                             (second (aref source-map (1- end)))))
                   span))))
    (let* ((scan-result (%source-reader-scan-result context source))
           (reader-results
             (nshell.domain.parsing:read-submission
              source :reader-context :auto :source-path source-path
              :source-map source-map)))
      (unless (eq (nshell.domain.parsing:scan-result-status scan-result) :complete)
        (error "source: incomplete reader input"))
      (let ((code 0))
        (dolist (reader-result reader-results)
          (multiple-value-bind (value result-code)
              (handler-case
                  (evaluate-reader-result-in-context context reader-result)
                (sexp-evaluation-syntax-error (condition)
                  (error
                   (make-condition
                    'sexp-evaluation-syntax-error
                    :source-span
                    (source-span-in-file
                     (sexp-evaluation-syntax-error-source-span condition))
                    :source-path
                    (sexp-evaluation-syntax-error-source-path condition)
                    :cause
                    (sexp-evaluation-syntax-error-cause condition))))
                (command-macro-syntax-error (condition)
                  (error
                   (make-condition
                    'command-macro-syntax-error
                    :source-span
                    (source-span-in-file
                     (command-macro-syntax-error-source-span condition))
                    :source-path
                    (command-macro-syntax-error-source-path condition)
                    :cause
                    (command-macro-syntax-error-cause condition)))))
            (declare (ignore value))
            (setf code result-code)
            (%record-last-exit-code context code))
          (unless (shell-context-running context)
            (return)))
        (values nil code)))))

  (defun %source-lines-with-reader (context lines &optional source-path)
  (labels ((source-map-for-line (line offset)
             (coerce
              (loop for position from offset below (+ offset (length line))
                    collect (list position (1+ position)))
              'vector))
           (append-here-document-source-map
               (source-map text line line-offset source-length)
             (let* ((line-end (+ line-offset (length line)))
                    (added
                      (append
                       (unless (and (plusp (length text))
                                    (char= (char text (1- (length text)))
                                           #\Newline))
                         (list (list (1- line-offset) line-offset)))
                       (loop for position from line-offset below line-end
                             collect (list position (1+ position)))
                       (list (if (< line-end source-length)
                                 (list line-end (1+ line-end))
                                 (list line-end line-end))))))
               (concatenate 'vector source-map (coerce added 'vector))))
           (append-continuation-source-map
               (source-map separator line line-offset)
             (let ((added
                     (append
                      (loop repeat (length separator)
                            collect (list line-offset line-offset))
                      (loop for position from line-offset
                            below (+ line-offset (length line))
                            collect (list position (1+ position))))))
               (concatenate 'vector source-map (coerce added 'vector))))
           (source-line-entries (source-lines)
             (loop with offset = 0
                   for tail on source-lines
                   for source-line = (car tail)
                   collect (prog1 (cons source-line offset)
                             (incf offset (+ (length source-line)
                                             (if (rest tail) 1 0))))))
           (source-tail-index (candidate source-lines)
             (loop for tail on source-lines
                   for index from 0
                   when (eq candidate tail) return index
                   finally
                      (when (null candidate)
                        (return (length source-lines)))))
           (source-function-remaining-entries
               (line line-offset remaining raw-remaining returned)
             (let* ((shared-tail
                      (loop for tail on returned
                            for prefix-count from 0
                            for suffix-index =
                              (source-tail-index tail raw-remaining)
                            when suffix-index
                              return (list prefix-count suffix-index)))
                    (prefix-count
                      (if shared-tail (first shared-tail) (length returned)))
                    (suffix-index
                      (if shared-tail (second shared-tail)
                          (length raw-remaining)))
                    (search-start 0))
               (append
                (loop for inline-line in (subseq returned 0 prefix-count)
                      collect
                      (let* ((found (search inline-line line
                                            :start2 search-start))
                             (start (or found search-start)))
                        (setf search-start (+ start (length inline-line)))
                        (cons inline-line (+ line-offset start))))
                (nthcdr suffix-index remaining)))))
    (let* ((source-length (length (format nil "~{~a~^~%~}" lines)))
           (output nil)
           (code 0)
           (remaining (source-line-entries lines)))
      (loop while remaining
            for entry = (pop remaining)
            for line = (car entry)
            for line-offset = (cdr entry)
            do (cond
                 ((%comment-or-blank-source-line-p line) nil)
                 ((and (not (%function-start-p line))
                       (source-line-function-split line))
                  (multiple-value-bind (prefix definition)
                      (source-line-function-split line)
                    (setf remaining
                          (list* (cons prefix line-offset)
                                 (cons definition
                                       (+ line-offset
                                          (or (search definition line) 0)))
                                 remaining))))
                 ((%function-start-p line)
                  (let* ((raw-remaining (mapcar #'car remaining))
                         (step (%source-lines-handle-function-start
                                context line raw-remaining source-path output)))
                    (setf remaining
                          (source-function-remaining-entries
                           line line-offset remaining raw-remaining
                           (%source-lines-step-result-remaining-lines step))
                          output (%source-lines-step-result-output-chunks step)
                          code (%source-lines-step-result-exit-code step))
                    (%record-last-exit-code context code)
                    (when (or (%source-lines-step-result-stop-p step)
                              (not (shell-context-running context)))
                      (return))))
                 (t
                  (let* ((first-nonwhite
                           (position-if-not
                            (lambda (character)
                              (find character
                                    (list #\Space #\Tab #\Newline #\Return)))
                            line))
                         (sexp-p
                           (and first-nonwhite
                                (char= (char line first-nonwhite)
                                       (code-char 40))))
                         (text line)
                         (source-map (source-map-for-line line line-offset))
                         (scan-result (%source-reader-scan-result context line))
                         (parse-result
                           (and (not sexp-p)
                                (nshell.domain.parsing:parse-command-line line))))
                    (loop while
                          (and remaining
                               (or (eq (nshell.domain.parsing:scan-result-status
                                        scan-result)
                                       :incomplete)
                                   (and parse-result
                                        (%source-line-needs-more-input-p
                                         parse-result))))
                          for next-entry = (pop remaining)
                          for next-line = (car next-entry)
                          for next-line-offset = (cdr next-entry)
                          do (let* ((separator
                                      (and (not sexp-p)
                                           (if (nshell.domain.parsing:parse-diagnostic-kind-p
                                                parse-result :trailing-continuation)
                                               " "
                                               "; ")))
                                    (next-text
                                      (if sexp-p
                                          (%append-source-here-document-line
                                           text next-line)
                                          (%append-source-continuation
                                           text next-line parse-result)))
                                    (next-source-map
                                      (if sexp-p
                                          (append-here-document-source-map
                                           source-map text next-line
                                           next-line-offset source-length)
                                          (append-continuation-source-map
                                           source-map separator next-line
                                           next-line-offset))))
                               (setf text next-text
                                     source-map next-source-map
                                     scan-result
                                     (%source-reader-scan-result context text)
                                     parse-result
                                     (and (not sexp-p)
                                          (nshell.domain.parsing:parse-command-line
                                           text)))))
                    (multiple-value-bind (chunk exit-code)
                        (%source-evaluate-reader-submission
                         context text source-path source-map)
                      (setf output (%source-lines-add-chunk chunk output)
                            code exit-code)
                      (%record-last-exit-code context code)
                      (when (not (shell-context-running context))
                        (return)))))))
      (values (apply #'concatenate 'string (nreverse output)) code))))

    (defun source-lines (context lines &optional source-path)
    "Execute source LINES in CONTEXT through the application source use case."
    (if (and source-path (%source-new-reader-route-enabled-p))
        (%source-lines-with-reader context lines source-path)
        (%source-lines context lines source-path))))

(in-package #:nshell.presentation)
(progn
  (defun %repl-reader-context-for-source (source)
    (if (not (%repl-new-reader-route-enabled-p))
        :bare-line
        (let ((first-nonwhite
                (position-if-not
                 (lambda (character)
                   (find character (list #\Space #\Tab #\Newline #\Return)))
                 source)))
          (if (and first-nonwhite
                   (char= (char source first-nonwhite) (code-char 40)))
              :sexp
              :bare-line))))
  (defun %repl-input-scan-result (source cursor reader-context
                                     &key head-classifier)
    (let* ((context
             (and (null head-classifier)
                  (eq reader-context :sexp)
                  (%make-repl-shell-context)))
           (classifier
             (or head-classifier
                 (and context
                      (lambda (head-source)
                        (nshell.application:classify-sexp-head
                         context head-source))))))
      (nshell.domain.parsing:scan-input
       source
       :cursor cursor
       :reader-context reader-context
       :indent-width +editor-indent-width+
       :head-classifier classifier)))
  (defun %evaluate-repl-reader-submission (source reader-context)
  (let ((context (%make-repl-shell-context))
        (reader-results
          (nshell.domain.parsing:read-submission
           source
           :reader-context reader-context)))
    (loop with status = 0
          for reader-result in reader-results
          do (multiple-value-bind (value result-status)
                 (call-with-command-failure-restarts
                  (lambda ()
                    (nshell.application:evaluate-reader-result-in-context
                     context reader-result)))
               (declare (ignore value))
               (setf status result-status))
          finally (return status)))))

(define-value-struct source-text-request
    ((lines nil :type list :copy :list))
  :documentation
  "Submitted text that the source reader has to assemble itself, such as a
function definition: its `end' closes a block the parser never groups into a
node, so the AST executor cannot run it.")

(defun %split-text-lines (text)
  (loop with start = 0
        for newline = (position #\Newline text :start start)
        collect (subseq text start (or newline (length text)))
        while newline
        do (setf start (1+ newline))))

(defun make-source-text-request (text)
  (%make-source-text-request (%split-text-lines text)))

(defun execute-ast (ast)
  (multiple-value-bind (output code)
      (cond
        ((source-text-request-p ast)
         (%with-repl-shell-context (context)
           (nshell.application:source-lines
            context
            (source-text-request-lines ast))))
        ((nshell.domain.parsing:command-node-p ast)
         (execute-command-node ast))
        ((or (nshell.domain.parsing:sequence-node-p ast)
             (nshell.domain.parsing:pipeline-node-p ast)
             (nshell.domain.parsing:if-node-p ast)
             (nshell.domain.parsing:for-node-p ast)
             (nshell.domain.parsing:while-node-p ast)
             (nshell.domain.parsing:case-node-p ast)
             (nshell.domain.parsing:begin-end-node-p ast))
         (%with-repl-shell-context (context)
           (nshell.application:execute-ast-in-context context ast)))
        (t
         (format t "nshell: cannot execute~%")
         (values nil 1)))
    (setf *last-command-output* output)
    code))

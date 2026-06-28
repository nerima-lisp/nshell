(in-package #:nshell.domain.parsing)

(defun %parse-structural-diagnostics (cmds last-sep last-sep-token input-length)
  (let ((diagnostics nil)
        (structural-incomplete nil))
    (when (%continuation-separator-p last-sep)
      (setf structural-incomplete t)
      (push (if last-sep-token
                (%token-diagnostic
                 :trailing-continuation
                 (format nil "Expected command after '~a'"
                         (%separator-text last-sep))
                 last-sep-token)
                (make-parse-diagnostic
                 :trailing-continuation
                 "Expected command after continuation operator"
                 input-length
                 input-length))
            diagnostics))
    (when (%unclosed-control-flow-p cmds)
      (setf structural-incomplete t)
      (push (make-parse-diagnostic
             :unclosed-block
             "Expected 'end' to close control-flow block"
             input-length
             input-length)
            diagnostics))
    (dolist (diagnostic (%unexpected-control-flow-diagnostics cmds input-length))
      (push diagnostic diagnostics))
    (values structural-incomplete (nreverse diagnostics))))

(defun parse-tokens (tokens incomplete &key (input-length 0))
  (multiple-value-bind (cmd-list errors)
      (%reduce-token-stream tokens)
    (let* ((cmds (mapcar #'first cmd-list))
           (separators (mapcar #'second cmd-list))
           (separator-tokens (mapcar #'third cmd-list))
           (last-sep (car (last separators)))
           (last-sep-token (car (last separator-tokens)))
           (ast (%build-ast-from-command-list cmd-list)))
      (multiple-value-bind (structural-incomplete structural-diagnostics)
          (%parse-structural-diagnostics cmds last-sep last-sep-token input-length)
        (make-parse-result (group-control-flow ast)
                           (nconc (nreverse errors) structural-diagnostics)
                           (or incomplete structural-incomplete))))))

(defun parse-command-line (input &key (cursor-pos nil))
  (multiple-value-bind (tokens cursor-token incomplete)
      (%tokenize-here-doc-aware input cursor-pos)
    (declare (ignore cursor-token))
    (if (null tokens)
        (make-parse-result nil nil incomplete)
        (parse-tokens tokens incomplete :input-length (length input)))))

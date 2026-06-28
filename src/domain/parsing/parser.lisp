(in-package #:nshell.domain.parsing)

(defstruct (%token-reduction-state
            (:constructor %make-token-reduction-state))
  (all-cmds '() :type list)
  (current-args '() :type list)
  (current-cmd nil)
  (current-cmd-token nil)
  (pending-redirect-token nil)
  (pending-sep nil)
  (pending-sep-token nil)
  (errors '() :type list))

(defun %line-end-position (input start)
  (or (position #\Newline input :start start)
      (length input)))

(defun %line-start-after (input line-end)
  (if (< line-end (length input))
      (1+ line-end)
      line-end))

(defun %here-doc-delimiters (tokens)
  (let ((delimiters '()))
    (loop for (tok next) on tokens
          when (and (eq (token-type tok) :redirect)
                    (string= (token-value tok) "<<")
                    next
                    (eq (token-type next) :word))
            do (push (token-value next) delimiters))
    (nreverse delimiters)))

(defun %read-here-doc-line (input start)
  (let* ((end (%line-end-position input start))
         (has-newline (< end (length input))))
    (values (subseq input start end)
            (if has-newline (1+ end) end)
            has-newline)))

(defun %consume-here-doc-body (input start delimiter)
  (with-output-to-string (body)
    (loop with pos = start
          while (< pos (length input))
          do (multiple-value-bind (line next-pos has-newline)
                 (%read-here-doc-line input pos)
               (when (string= line delimiter)
                 (return-from %consume-here-doc-body
                   (values (get-output-stream-string body) next-pos nil)))
               (write-string line body)
               (when has-newline
                 (write-char #\Newline body))
               (setf pos next-pos))
          finally (return-from %consume-here-doc-body
                    (values (get-output-stream-string body) pos t)))))

(defun %consume-here-docs (input start delimiters)
  (let ((bodies '())
        (pos start)
        (incomplete nil))
    (dolist (delimiter delimiters)
      (multiple-value-bind (body next-pos missing-delimiter)
          (%consume-here-doc-body input pos delimiter)
        (push body bodies)
        (setf pos next-pos)
        (when missing-delimiter
          (setf incomplete t)
          (return))))
    (values (nreverse bodies) pos incomplete)))

(defun %replace-here-doc-targets (tokens bodies)
  (let ((remaining-bodies bodies)
        (replace-next-target nil)
        (updated '()))
    (dolist (tok tokens)
      (cond
        ((and replace-next-target remaining-bodies (eq (token-type tok) :word))
        (push (make-token (token-type tok)
                          (pop remaining-bodies)
                          (token-start tok)
                          (token-end tok)
                          (token-quote-style tok))
              updated)
         (setf replace-next-target nil))
        (t
         (push tok updated)
         (setf replace-next-target
               (and (eq (token-type tok) :redirect)
                    (string= (token-value tok) "<<")
                    remaining-bodies)))))
    (nreverse updated)))

(defun %synthetic-newline-token (pos)
  (make-token :newline (string #\Newline) pos pos))

(defun %offset-token (token offset)
  (make-token (token-type token)
              (token-value token)
              (+ offset (token-start token))
              (+ offset (token-end token))
              (token-quote-style token)))

(defun %offset-tokens (tokens offset)
  (mapcar (lambda (token)
            (%offset-token token offset))
          tokens))

(defun %blank-input-from-position-p (input start)
  (or (>= start (length input))
      (shell-input-blank-p (subseq input start))))

(defun %tokenize-here-doc-aware (input cursor-pos)
  (let* ((first-line-end (%line-end-position input 0))
         (first-line (subseq input 0 first-line-end)))
    (multiple-value-bind (first-line-tokens cursor-token first-line-incomplete)
        (tokenize first-line :cursor-pos cursor-pos)
      (let ((delimiters (%here-doc-delimiters first-line-tokens)))
        (if delimiters
            (if (= first-line-end (length input))
                (values first-line-tokens cursor-token t)
                (multiple-value-bind (bodies next-pos here-doc-incomplete)
                    (%consume-here-docs input
                                        (%line-start-after input first-line-end)
                                        delimiters)
                  (let ((tokens (%replace-here-doc-targets first-line-tokens bodies)))
                    (if (%blank-input-from-position-p input next-pos)
                        (values tokens
                                cursor-token
                                (or first-line-incomplete here-doc-incomplete))
                        (multiple-value-bind (tail-tokens tail-cursor-token
                                              tail-incomplete)
                            (%tokenize-here-doc-aware (subseq input next-pos)
                                                      nil)
                          (values (append tokens
                                          (list (%synthetic-newline-token next-pos))
                                          (%offset-tokens tail-tokens next-pos))
                                  (or cursor-token tail-cursor-token)
                                  (or first-line-incomplete
                                      here-doc-incomplete
                                      tail-incomplete)))))))
            (tokenize input :cursor-pos cursor-pos))))))

(defun %record-missing-redirect-target (state)
  (let ((pending-redirect-token (%token-reduction-state-pending-redirect-token state)))
    (when pending-redirect-token
      (push (%token-diagnostic
             :missing-redirection-target
             (format nil "Expected target after '~a'"
                     (token-value pending-redirect-token))
             pending-redirect-token)
            (%token-reduction-state-errors state))
      (setf (%token-reduction-state-pending-redirect-token state) nil))))

(defun %flush-token-reduction-command (state)
  (when (%token-reduction-state-current-cmd state)
    (%record-missing-redirect-target state)
    (push (list (make-command-node
                 (%token-reduction-state-current-cmd state)
                 (nreverse (%token-reduction-state-current-args state))
                 (when (%token-reduction-state-current-cmd-token state)
                   (list (token-start (%token-reduction-state-current-cmd-token state))
                         (token-end (%token-reduction-state-current-cmd-token state))))
                 (when (%token-reduction-state-current-cmd-token state)
                   (token-quote-style (%token-reduction-state-current-cmd-token state))))
                (%token-reduction-state-pending-sep state)
                (%token-reduction-state-pending-sep-token state))
          (%token-reduction-state-all-cmds state))
    (setf (%token-reduction-state-current-cmd state) nil
          (%token-reduction-state-current-cmd-token state) nil
          (%token-reduction-state-current-args state) '()
          (%token-reduction-state-pending-redirect-token state) nil
          (%token-reduction-state-pending-sep state) nil
          (%token-reduction-state-pending-sep-token state) nil)))

(defun %record-token-reduction-separator (state separator token)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%record-missing-redirect-target state)
        (setf (%token-reduction-state-pending-sep state) separator
              (%token-reduction-state-pending-sep-token state) token)
        (%flush-token-reduction-command state))
      (unless (eq (token-type token) :newline)
        (push (%token-diagnostic
               :missing-command
               (format nil "Expected command before '~a'"
                       (%separator-text separator))
               token)
              (%token-reduction-state-errors state)))))

(defun %token-reduction-word (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (let ((style (token-quote-style tok)))
          (push (if style
                    (cons (token-value tok) style)
                    (token-value tok))
                (%token-reduction-state-current-args state)))
        (setf (%token-reduction-state-pending-redirect-token state) nil))
      (setf (%token-reduction-state-current-cmd state) (token-value tok)
            (%token-reduction-state-current-cmd-token state) tok)))

(defun %token-reduction-redirect (state tok)
  (if (%token-reduction-state-current-cmd state)
      (progn
        (%record-missing-redirect-target state)
        (push (cons (token-value tok) nil)
              (%token-reduction-state-current-args state))
        ;; fd-dup redirects (e.g. 2>&1) are self-contained and need no
        ;; following target, so they do not start a pending redirect.
        (let ((spec (assoc (token-value tok) +redirect-specs+ :test #'string=)))
          (unless (and spec (member (cdr spec) +redirect-fd-dup-specs+))
            (setf (%token-reduction-state-pending-redirect-token state) tok))))
      (push (%token-diagnostic
             :missing-command
             (format nil "Expected command before '~a'" (token-value tok))
             tok)
            (%token-reduction-state-errors state))))

(defun %token-reduction-error (state tok)
  (push (cond
          ((string= "\\" (token-value tok))
           (%token-diagnostic
            :trailing-escape
            "Trailing escape requires continuation"
            tok))
          ((and (>= (length (token-value tok)) 2)
                (string= "<(" (subseq (token-value tok) 0 2)))
           (%token-diagnostic
            :unterminated-process-substitution
            "Unterminated process substitution"
            tok))
          (t
           (%token-diagnostic
            :unterminated-quote
            "Unterminated quoted string"
            tok)))
        (%token-reduction-state-errors state)))

(defun %token-reduction-separator (state tok)
  (let ((separator (%separator-from-token-type (token-type tok))))
    (if separator
        (%record-token-reduction-separator state separator tok)
        (push (%token-diagnostic
               :unexpected-token
               (format nil "Unexpected token: ~a" (token-value tok))
               tok)
              (%token-reduction-state-errors state)))))

(defun %reduce-token (state tok)
  (case (token-type tok)
    (:word (%token-reduction-word state tok))
    (:redirect (%token-reduction-redirect state tok))
    (:error (%token-reduction-error state tok))
    (t (%token-reduction-separator state tok))))

(defun %reduce-token-stream (tokens)
  (let ((state (%make-token-reduction-state)))
    (dolist (tok tokens)
      (%reduce-token state tok))
    (%flush-token-reduction-command state)
    (values (nreverse (%token-reduction-state-all-cmds state))
            (nreverse (%token-reduction-state-errors state)))))

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

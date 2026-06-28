; Here-doc and multi-line tokenization: line scanning, body consumption, token patching.
(in-package #:nshell.domain.parsing)

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

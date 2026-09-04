; Here-doc and multi-line tokenization: line scanning, body consumption, token patching.
(in-package #:nshell.domain.parsing)

(defun %here-doc-redirect-token-p (token)
  (and (eq (token-type token) :redirect)
       (member (token-value token) '("<<" "<<-") :test #'string=)))

(defun %empty-here-doc-delimiter-scan ()
  (%make-here-doc-delimiter-scan '()))

(defun %here-doc-delimiter-scan-add (scan delimiter)
  (%make-here-doc-delimiter-scan
   (cons delimiter
         (%here-doc-delimiter-scan-reversed-delimiters scan))))

(defun %here-doc-delimiter-scan-result (scan)
  (nreverse (%here-doc-delimiter-scan-reversed-delimiters scan)))

(defun %here-doc-delimiters (tokens &optional include-redirect-metadata-p)
  (let ((scan (%empty-here-doc-delimiter-scan)))
    (loop for (tok next) on tokens
          when (and (%here-doc-redirect-token-p tok)
                    next
                    (eq (token-type next) :word))
            do (setf scan
                     (%here-doc-delimiter-scan-add scan
                                                   (if include-redirect-metadata-p
                                                       (cons (token-value next)
                                                             (string= (token-value tok)
                                                                      "<<-"))
                                                       (token-value next)))))
    (%here-doc-delimiter-scan-result scan)))

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

(declaim (ftype (function (string t) t)
                %tokenize-here-doc-aware))

(defun %tokenize-here-doc-tail (input next-pos tokens cursor-token incomplete)
  (if (%blank-input-from-position-p input next-pos)
      (%make-tokenization-result tokens cursor-token incomplete)
      (let ((tail (%tokenize-here-doc-aware (subseq input next-pos) nil)))
        (%make-tokenization-result
         (append tokens
                 (list (%synthetic-newline-token next-pos))
                 (%offset-tokens (tokenization-result-tokens tail)
                                  next-pos))
         (or cursor-token
             (tokenization-result-cursor-token tail))
         (or incomplete
             (tokenization-result-incomplete-p tail))))))

(defun %tokenize-here-doc-command-line (input first-line-end first-line-tokens
                                        cursor-token first-line-incomplete
                                        delimiters)
  (if (= first-line-end (length input))
      (%make-tokenization-result first-line-tokens cursor-token t)
      (let ((consumption
              (%consume-here-docs-result input
                                         (%line-start-after input first-line-end)
                                         delimiters)))
        (%tokenize-here-doc-tail
         input
         (%here-doc-consumption-next-position consumption)
         (%replace-here-doc-targets
          first-line-tokens
          (%here-doc-consumption-bodies consumption))
         cursor-token
         (or first-line-incomplete
             (%here-doc-consumption-incomplete-p consumption))))))

(defun %tokenize-here-doc-aware (input cursor-pos)
  (labels
      ((contiguous-word-token-p (left right)
         (and left
              right
              (eq (token-type right) :word)
              (= (token-end left) (token-start right))))
       (merge-target (target remaining)
         (loop with value = (token-value target)
               with fragments = (copy-list (token-fragments target))
               with last-token = target
               with target-tokens = (list target)
               while (and remaining
                          (contiguous-word-token-p
                           last-token
                           (first remaining)))
               do (let ((next (pop remaining)))
                    (setf value (concatenate 'string value (token-value next))
                          fragments (append fragments
                                            (copy-list
                                             (token-fragments next)))
                          target-tokens (append target-tokens (list next))
                          last-token next))
               finally
                  (return
                    (values
                     (if (cdr target-tokens)
                         (make-token :word
                                     value
                                     (token-start target)
                                     (token-end last-token)
                                     nil
                                     fragments)
                         target)
                     remaining
                     target-tokens))))
       (merge-target-fragments (tokens cursor-token)
         (loop with result = nil
               with result-cursor-token = cursor-token
               with remaining = tokens
               while remaining
               do (let ((token (pop remaining)))
                    (push token result)
                    (when (and (%here-doc-redirect-token-p token)
                               remaining
                               (eq (token-type (first remaining)) :word))
                      (multiple-value-bind (target rest target-tokens)
                          (merge-target (pop remaining) remaining)
                        (setf remaining rest)
                        (when (and (cdr target-tokens)
                                   (member cursor-token
                                           target-tokens
                                           :test #'eq))
                          (setf result-cursor-token target))
                        (push target result))))
               finally
                  (return (values (nreverse result)
                                  result-cursor-token)))))
    (let* ((first-line-end (%line-end-position input 0))
           (first-line (subseq input 0 first-line-end))
           (first-line-result
             (tokenize first-line :cursor-pos cursor-pos)))
      (multiple-value-bind
          (first-line-tokens first-line-cursor-token)
          (merge-target-fragments
           (tokenization-result-tokens first-line-result)
           (tokenization-result-cursor-token first-line-result))
        (let ((delimiters (%here-doc-delimiters first-line-tokens t)))
          (if delimiters
              (%tokenize-here-doc-command-line
               input
               first-line-end
               first-line-tokens
               first-line-cursor-token
               (tokenization-result-incomplete-p first-line-result)
               delimiters)
              (tokenize input :cursor-pos cursor-pos)))))))

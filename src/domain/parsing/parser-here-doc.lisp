; Here-doc and multi-line tokenization: line scanning, body consumption, token patching.
(in-package #:nshell.domain.parsing)

(defun %line-end-position (input start)
  (or (position #\Newline input :start start)
      (length input)))

(defun %line-start-after (input line-end)
  (if (< line-end (length input))
      (1+ line-end)
      line-end))

(defun %here-doc-redirect-token-p (token)
  (and (eq (token-type token) :redirect)
       (member (token-value token) '("<<" "<<-") :test #'string=)))

(defstruct (%here-doc-delimiter-scan
            (:constructor %make-here-doc-delimiter-scan
                (reversed-delimiters))
            (:copier nil))
  (reversed-delimiters '() :type list :read-only t))

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

(defstruct (%here-doc-line
            (:constructor %make-here-doc-line
                (text next-position newline-p))
            (:copier nil))
  (text "" :type string :read-only t)
  next-position
  (newline-p nil :type boolean :read-only t))

(defun %read-here-doc-line (input start)
  (let* ((end (%line-end-position input start))
         (has-newline (< end (length input))))
    (%make-here-doc-line (subseq input start end)
                         (if has-newline (1+ end) end)
                         has-newline)))

(defstruct (%here-doc-body
            (:constructor %make-here-doc-body
                (body next-position missing-delimiter-p))
            (:copier nil))
  (body "" :type string :read-only t)
  next-position
  (missing-delimiter-p nil :type boolean :read-only t))

(defun %consume-here-doc-body (input start delimiter &optional strip-tabs-p)
  (let* ((delimiter-text (if (consp delimiter) (car delimiter) delimiter))
         (strip-leading-tabs-p
           (or strip-tabs-p
               (and (consp delimiter) (cdr delimiter)))))
    (with-output-to-string (body)
      (loop with pos = start
            while (< pos (length input))
            do (let* ((line (%read-here-doc-line input pos))
                      (line-text (%here-doc-line-text line))
                      (normalized-line-text
                        (if strip-leading-tabs-p
                            (string-left-trim '(#\Tab) line-text)
                            line-text)))
                 (when (string= normalized-line-text delimiter-text)
                   (return-from %consume-here-doc-body
                     (%make-here-doc-body
                      (get-output-stream-string body)
                      (%here-doc-line-next-position line)
                      nil)))
                 (write-string normalized-line-text body)
                 (when (%here-doc-line-newline-p line)
                   (write-char #\Newline body))
                 (setf pos (%here-doc-line-next-position line)))
            finally (return-from %consume-here-doc-body
                      (%make-here-doc-body
                       (get-output-stream-string body)
                       pos
                       t))))))

(defstruct (%here-doc-consumption
            (:constructor %make-here-doc-consumption
                (bodies next-position incomplete-p))
            (:copier nil))
  (bodies '() :type list :read-only t)
  next-position
  (incomplete-p nil :type boolean :read-only t))

(defstruct (%here-doc-consumption-state
            (:constructor %make-here-doc-consumption-state
                (reversed-bodies next-position incomplete-p))
            (:copier nil))
  (reversed-bodies '() :type list :read-only t)
  next-position
  (incomplete-p nil :type boolean :read-only t))

(defun %empty-here-doc-consumption-state (start)
  (%make-here-doc-consumption-state '() start nil))

(defun %here-doc-consumption-state-add-body (state body)
  (%make-here-doc-consumption-state
   (cons (%here-doc-body-body body)
         (%here-doc-consumption-state-reversed-bodies state))
   (%here-doc-body-next-position body)
   (%here-doc-body-missing-delimiter-p body)))

(defun %here-doc-consumption-state-consume-delimiter (input state delimiter)
  (%here-doc-consumption-state-add-body
   state
   (%consume-here-doc-body
    input
    (%here-doc-consumption-state-next-position state)
    delimiter)))

(defun %here-doc-consumption-from-state (state)
  (%make-here-doc-consumption
   (nreverse (%here-doc-consumption-state-reversed-bodies state))
   (%here-doc-consumption-state-next-position state)
   (%here-doc-consumption-state-incomplete-p state)))

(defun %consume-here-docs-result (input start delimiters)
  (labels ((consume (state remaining-delimiters)
             (if (or (endp remaining-delimiters)
                     (%here-doc-consumption-state-incomplete-p state))
                 (%here-doc-consumption-from-state state)
                 (consume
                  (%here-doc-consumption-state-consume-delimiter
                   input
                   state
                   (first remaining-delimiters))
                  (rest remaining-delimiters)))))
    (consume (%empty-here-doc-consumption-state start) delimiters)))

(defun %here-doc-target-token-p (token)
  (eq (token-type token) :word))

(defun %replace-here-doc-target-token (token body)
  (make-token (token-type token)
              body
              (token-start token)
              (token-end token)
              (token-quote-style token)))

(defstruct (here-doc-target-replacer
            (:constructor %make-here-doc-target-replacer (bodies))
            (:copier nil))
  bodies
  (target-pending-p nil :type boolean))

(defstruct (%here-doc-target-body-cursor
            (:constructor %make-here-doc-target-body-cursor
                (body remaining-bodies))
            (:conc-name %here-doc-target-body-cursor-)
            (:copier nil))
  body
  remaining-bodies)

(defun %here-doc-target-body-cursor (bodies)
  (%make-here-doc-target-body-cursor (first bodies) (rest bodies)))

(defun %here-doc-target-replacer-has-body-p (replacer)
  (not (null (here-doc-target-replacer-bodies replacer))))

(defun %mark-here-doc-target-pending (replacer)
  (when (%here-doc-target-replacer-has-body-p replacer)
    (setf (here-doc-target-replacer-target-pending-p replacer) t))
  replacer)

(defun %consume-next-here-doc-target-body (replacer)
  (let ((cursor (%here-doc-target-body-cursor
                 (here-doc-target-replacer-bodies replacer))))
    (setf (here-doc-target-replacer-bodies replacer)
          (%here-doc-target-body-cursor-remaining-bodies cursor))
    (%here-doc-target-body-cursor-body cursor)))

(defun %here-doc-target-replacer-should-replace-p (replacer token)
  (and (here-doc-target-replacer-target-pending-p replacer)
       (%here-doc-target-replacer-has-body-p replacer)
       (%here-doc-target-token-p token)))

(defun %here-doc-target-replacer-accept (replacer token)
  (cond
    ((%here-doc-target-replacer-should-replace-p replacer token)
     (setf (here-doc-target-replacer-target-pending-p replacer) nil)
     (%replace-here-doc-target-token
      token
      (%consume-next-here-doc-target-body replacer)))
    (t
     (when (%here-doc-redirect-token-p token)
       (%mark-here-doc-target-pending replacer))
     token)))

(defun %replace-here-doc-targets (tokens bodies)
  (let ((replacer (%make-here-doc-target-replacer bodies)))
    (loop for tok in tokens
          collect (%here-doc-target-replacer-accept replacer tok))))

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

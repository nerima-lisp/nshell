;;; `!$` and Alt-. extract the final insertable argument from a recorded
;;; shell line. The extractor uses scanner spans to preserve source spelling
;;; while skipping command words, leading assignments, and redirection targets.
(in-package #:nshell.domain.history)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (define-value-struct history-word
      ((start 0 :type (integer 0 *))
       (end 0 :type (integer 0 *)))
    :constructor %allocate-history-word
    :predicate nil))

(defun %make-history-word (start end)
  (check-type start (integer 0 *))
  (check-type end (integer 0 *))
  (assert (<= start end) (start end)
          "History word start must not exceed end.")
  (%allocate-history-word start end))

(define-value-struct %history-token-window
    ((current nil)
     (next nil))
  :constructor %make-history-token-window
  :predicate nil)

(define-value-struct %history-logical-word-cursor
    ((remaining nil :type list :copy :list))
  :constructor %make-history-logical-word-cursor
  :predicate nil)

(define-value-struct %history-last-argument-scan-state
    ((last-argument nil :type (or null string))
     (skip-redirect-target nil :type boolean)
     (seen-command-word nil :type boolean)
     (logical-word-cursor nil :type %history-logical-word-cursor))
  :constructor %make-history-last-argument-scan-state
  :predicate nil)

(defun %history-token-window-from-remaining (remaining)
  (%make-history-token-window (first remaining) (second remaining)))

(defun %history-word-token-p (token)
  (and (eq (nshell.domain.parsing:scan-token-reader-context token) :bare-line)
       (member (nshell.domain.parsing:scan-token-kind token)
               '(:command-head :argument :string :here-doc-delimiter
                 :process-substitution)
               :test #'eq)))

(defun %history-redirect-token-p (token)
  (eq (nshell.domain.parsing:scan-token-kind token) :redirect))

(defun %history-fd-redirection-designator-p (token next-token)
  (and token next-token
       (%history-word-token-p token)
       (%history-redirect-token-p next-token)
       (= (second (nshell.domain.parsing:scan-token-span token))
          (first (nshell.domain.parsing:scan-token-span next-token)))
       (every #'digit-char-p (nshell.domain.parsing:scan-token-text token))))

(defun %history-logical-words-flush-current (words current)
  (if current
      (values (cons current words) nil)
      (values words nil)))

(defun %history-logical-words (tokens &optional delimiter-pairs)
  ;; Adjacent quoted and unquoted tokens form one shell word, as in "x"y.
  ;; Coalescing their spans preserves the full raw spelling for insertion.
  (let ((words nil)
        (current nil))
    (dolist (token tokens)
      (if (%history-word-token-p token)
          (let* ((span (nshell.domain.parsing:scan-token-span token))
                 (start (first span))
                 (end
                   (if (eq (nshell.domain.parsing:scan-token-kind token)
                           :process-substitution)
                       (let ((pair
                               (find-if
                                (lambda (candidate)
                                  (= (first
                                      (nshell.domain.parsing:delimiter-pair-open-span
                                       candidate))
                                     (second span)))
                                delimiter-pairs)))
                         (if pair
                             (second
                              (nshell.domain.parsing:delimiter-pair-close-span pair))
                             (second span)))
                       (second span))))
            (if (and current (= start (history-word-end current)))
                (setf current (%make-history-word (history-word-start current) end))
                (progn
                  (multiple-value-setq (words current)
                    (%history-logical-words-flush-current words current))
                  (setf current (%make-history-word start end)))))
          (multiple-value-setq (words current)
            (%history-logical-words-flush-current words current))))
    (multiple-value-setq (words current)
      (%history-logical-words-flush-current words current))
    (nreverse words)))

(defun %history-word-source (line word)
  (subseq line (history-word-start word) (history-word-end word)))

(defun %history-logical-word-cursor-current (cursor)
  (first (%history-logical-word-cursor-remaining cursor)))

(defun %history-logical-word-cursor-consume-current (cursor)
  (%make-history-logical-word-cursor
   (rest (%history-logical-word-cursor-remaining cursor))))

(defun %history-logical-word-cursor-consume-matching-token (cursor token)
  (let ((word (%history-logical-word-cursor-current cursor)))
    (when (and word
               (= (first (nshell.domain.parsing:scan-token-span token))
                  (history-word-start word)))
      (values word (%history-logical-word-cursor-consume-current cursor)))))

(defun %history-last-argument-reset-for-separator (state)
  (%make-history-last-argument-scan-state
   nil nil nil
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-note-command-word (state)
  (%make-history-last-argument-scan-state
   (%history-last-argument-scan-state-last-argument state)
   (%history-last-argument-scan-state-skip-redirect-target state)
   t
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-note-argument (state argument)
  (%make-history-last-argument-scan-state
   argument
   (%history-last-argument-scan-state-skip-redirect-target state)
   (%history-last-argument-scan-state-seen-command-word state)
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-clear-redirect-target (state)
  (%make-history-last-argument-scan-state
   (%history-last-argument-scan-state-last-argument state)
   nil
   (%history-last-argument-scan-state-seen-command-word state)
   (%history-last-argument-scan-state-logical-word-cursor state)))

(defun %history-last-argument-handle-word (state line token token-window)
  (multiple-value-bind (word cursor)
      (%history-logical-word-cursor-consume-matching-token
       (%history-last-argument-scan-state-logical-word-cursor state)
       token)
    (if (null word)
        state
        (let ((state
                (%make-history-last-argument-scan-state
                 (%history-last-argument-scan-state-last-argument state)
                 (%history-last-argument-scan-state-skip-redirect-target state)
                 (%history-last-argument-scan-state-seen-command-word state)
                 cursor)))
          (cond
            ((%history-fd-redirection-designator-p
              token
              (%history-token-window-next token-window))
             state)
            ((%history-last-argument-scan-state-skip-redirect-target state)
             (%history-last-argument-clear-redirect-target state))
            ((and (not (%history-last-argument-scan-state-seen-command-word state))
                  (nshell.domain.parsing:shell-assignment-word-p
                   (%history-word-source line word)))
             state)
            ((not (%history-last-argument-scan-state-seen-command-word state))
             (%history-last-argument-note-command-word state))
            (t
             (%history-last-argument-note-argument
              state
              (%history-word-source line word))))))))

(defun %history-last-argument-handle-token (state line token token-window)
  (cond
    ((member (nshell.domain.parsing:scan-token-kind token)
             '(:pipeline :pipeline-stderr :and :or
               :sequence-separator :background)
             :test #'eq)
     (%history-last-argument-reset-for-separator state))
    ((%history-redirect-token-p token)
     (if (string= (nshell.domain.parsing:scan-token-text token) "2>&1")
         state
         (%make-history-last-argument-scan-state
          (%history-last-argument-scan-state-last-argument state)
          t
          (%history-last-argument-scan-state-seen-command-word state)
          (%history-last-argument-scan-state-logical-word-cursor state))))
    ((%history-word-token-p token)
     (%history-last-argument-handle-word state line token token-window))
    (t
     state)))

(declaim (ftype (function (t integer) (or null string))
                history-last-argument-at))

(defun command-line-last-argument (line)
  "Return the source text of the last argument in LINE, or NIL.

Command words and redirection targets are not considered arguments. For
pipelines and command lists, the result is scoped to the final command segment."
  (when (and (stringp line) (plusp (length line)))
    (let* ((scan-result
             (nshell.domain.parsing:scan-input
              line
              :reader-context :auto
              :head-classifier
              ;; Keep S-expression forms in host code; this scan has no
              ;; classifier for shell command islands.
              (lambda (head)
                (declare (ignore head))
                :host-form)))
           (tokens (nshell.domain.parsing:scan-result-tokens scan-result))
           (delimiter-pairs
             (nshell.domain.parsing:scan-result-delimiter-pairs scan-result))
           (state (%make-history-last-argument-scan-state
                   nil nil nil
                   (%make-history-logical-word-cursor
                    (%history-logical-words tokens delimiter-pairs)))))
      (do ((remaining tokens (rest remaining)))
          ((endp remaining)
           (%history-last-argument-scan-state-last-argument state))
        (let* ((token-window (%history-token-window-from-remaining remaining))
               (token (%history-token-window-current token-window)))
          (setf state
                (%history-last-argument-handle-token
                 state line token token-window)))))))

(defun history-last-argument-at (history index)
  "Return the zero-based INDEX-th insertable last argument in HISTORY, or NIL."
  (when (and (integerp index) (not (minusp index)))
    (do ((entries (history-kit:history-entries history) (rest entries)))
        ((endp entries) nil)
      (let ((argument (command-line-last-argument
                        (history-kit:history-entry-text (first entries)))))
        (when argument
          (if (zerop index)
              (return argument)
              (decf index)))))))

;;; Autosuggestion acceptance helpers for the input reducer.

(in-package #:nshell.presentation)


(defun suggestion-word-like-token-p (token)
  (not (null (member (nshell.domain.parsing:token-type token)
                     '(:word :error)
                     :test #'eq))))

(defun suggestion-first-token-at-or-after (tokens position)
  (find-if (lambda (token)
             (>= (nshell.domain.parsing:token-start token) position))
           tokens))

(defun suggestion-token-accept-end (tokens first-token)
  (let ((accept-end (nshell.domain.parsing:token-end first-token)))
    (when (suggestion-word-like-token-p first-token)
      (dolist (token (rest (member first-token tokens)))
        (if (and (suggestion-word-like-token-p token)
                 (= (nshell.domain.parsing:token-start token) accept-end))
            (setf accept-end (nshell.domain.parsing:token-end token))
            (return))))
    accept-end))

(defun suggestion-redirection-operator-end (suggestion position)
  (let ((end (length suggestion)))
    (when (< position end)
      (let ((ch (char suggestion position)))
        (cond
          ((and (char= ch #\&)
                (< (1+ position) end)
                (char= (char suggestion (1+ position)) #\>))
           (+ position 2))
          ((or (char= ch #\<) (char= ch #\>))
           (if (and (char= ch #\>)
                    (< (1+ position) end)
                    (char= (char suggestion (1+ position)) #\>))
               (+ position 2)
               (1+ position))))))))

(defun %suggestion-scan-fd-digits (suggestion position end)
  "Return the index just past the run of file-descriptor digits that begins at
POSITION (POSITION itself when none follow)."
  (loop for index from position below end
        while (digit-char-p (char suggestion index))
        finally (return index)))

(defun %suggestion-redirection-target-end (suggestion operator-end end)
  "Return the end of an `&'-style redirection target -- the fd digits in a form
like \"2>&1\", or a bare \"-\" -- or OPERATOR-END when no such target follows the
ampersand at OPERATOR-END."
  (let ((target-position (1+ operator-end)))
    (if (and (< target-position end)
             (or (digit-char-p (char suggestion target-position))
                 (char= (char suggestion target-position) #\-)))
        (%suggestion-scan-fd-digits suggestion (1+ target-position) end)
        operator-end)))

(defun suggestion-compact-redirection-end (suggestion position)
  "Return the end of a compact redirection starting at POSITION, or NIL.

This keeps autosuggestion word acceptance from splitting shell forms such as
\"2>&1\" and \">out.txt\" into lexer-sized pieces."
  (let* ((end (length suggestion))
         (operator-position (%suggestion-scan-fd-digits suggestion position end)))
    (when (or (= operator-position position)
              (and (< operator-position end)
                   (member (char suggestion operator-position)
                           '(#\< #\>)
                           :test #'char=)))
      (let ((operator-end
              (suggestion-redirection-operator-end suggestion operator-position)))
        (when operator-end
          (cond
            ((and (< operator-end end)
                  (char= (char suggestion operator-end) #\&))
             (%suggestion-redirection-target-end suggestion operator-end end))
            ((and (< operator-end end)
                  (not (nshell.domain.parsing:shell-token-separator-p
                        (char suggestion operator-end))))
             (shell-token-end suggestion operator-end))
            (t operator-end)))))))

(define-value-struct %suggestion-acceptance-segment
    ((end 0 :type fixnum)))

(define-value-struct %suggestion-acceptance
    ((accepted "" :type string)
     (remaining "" :type string)))

(define-value-struct %suggestion-append-plan
    ((splice (error "SPLICE is required.") :type %buffer-splice)))

(define-value-struct %suggestion-append-edit
    ((plan (error "PLAN is required.") :type %suggestion-append-plan)
     (remaining nil :type (or null string))))

(defun suggestion-append-edit-for-state (state accepted remaining)
  (let* ((buffer (input-state-buffer state))
         (end (length buffer)))
    (%make-suggestion-append-edit
     (%make-suggestion-append-plan
      (make-buffer-splice end end accepted))
     (unless (zerop (length remaining))
       remaining))))

(defun suggestion-append-edit-buffer (edit buffer)
  (buffer-splice-result
   (suggestion-append-plan-splice (suggestion-append-edit-plan edit))
   buffer))

(defun suggestion-append-edit-cursor-pos (edit)
  (buffer-splice-cursor-pos
   (suggestion-append-plan-splice (suggestion-append-edit-plan edit))))

(defun commit-suggestion-append-edit (state edit)
  (copy-input-state-clearing-completion
   state
   :buffer (suggestion-append-edit-buffer edit (input-state-buffer state))
   :cursor-pos (suggestion-append-edit-cursor-pos edit)
   :suggestion (or (suggestion-append-edit-remaining edit) :clear)))

(defun suggestion-next-acceptance-segment (suggestion)
  "Return the next autosuggestion acceptance segment.

Leading shell word separators are accepted with the following token, matching
fish-style autosuggestion word acceptance for tails such as \" status --short\"."
  (let ((pos 0)
        (end (length suggestion)))
    (loop while (and (< pos end)
                     (nshell.domain.parsing:shell-word-separator-p
                      (char suggestion pos)))
          do (incf pos))
    (if (= pos end)
        (%make-suggestion-acceptance-segment end)
        (%make-suggestion-acceptance-segment
         (or (suggestion-compact-redirection-end suggestion pos)
             (handler-case
                 (let* ((tokenization
                          (nshell.domain.parsing:tokenize suggestion))
                        (tokens
                          (nshell.domain.parsing:tokenization-result-tokens
                           tokenization))
                        (first-token
                          (suggestion-first-token-at-or-after tokens pos)))
                   (if first-token
                       (suggestion-token-accept-end tokens first-token)
                       end))
               (error ()
                 (shell-token-end suggestion pos))))))))

(defun next-suggestion-acceptance (suggestion)
  (let* ((segment (suggestion-next-acceptance-segment suggestion))
         (accept-end (suggestion-acceptance-segment-end segment))
         (accepted (subseq suggestion 0 accept-end))
         (remaining (subseq suggestion accept-end)))
    (%make-suggestion-acceptance accepted remaining)))

(defun commit-suggestion-acceptance (state acceptance)
  (commit-suggestion-append-edit
   state
   (suggestion-append-edit-for-state
    state
    (suggestion-acceptance-accepted acceptance)
    (suggestion-acceptance-remaining acceptance))))

(defun append-suggestion-to-input-state (state suggestion)
  (commit-suggestion-acceptance
   state
   (%make-suggestion-acceptance suggestion "")))

(defun accept-suggestion-at-eol (state)
  (with-normalized-input-state (state state)
    (let ((suggestion (input-state-suggestion state)))
      (if (and suggestion (input-state-at-eol-p state))
          (values (append-suggestion-to-input-state state suggestion)
                  :suggest-update)
          (move-cursor-clearing-suggestion state 1)))))

(defun accept-suggestion-word-at-eol (state)
  (with-normalized-input-state (state state)
    (let ((suggestion (input-state-suggestion state)))
      (if (and suggestion (input-state-at-eol-p state))
          (let ((acceptance (next-suggestion-acceptance suggestion)))
            (values (commit-suggestion-acceptance state acceptance)
                    :suggest-update))
          (move-word-right state)))))

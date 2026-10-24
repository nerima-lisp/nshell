;;; Autosuggestion acceptance helpers for the input reducer.

(in-package #:nshell.presentation)


(defun suggestion-word-like-token-p (token)
  (not (null (member (nshell.domain.parsing:scan-token-kind token)
                     '(:command-head :argument :string :escaped-symbol
                       :here-doc-delimiter)
                     :test #'eq))))

(defun suggestion-first-token-at-or-after (tokens position)
  (find-if (lambda (token)
             (>= (first (nshell.domain.parsing:scan-token-span token))
                 position))
           tokens))

(defun suggestion-token-accept-end (scan-result first-token)
  (let* ((tokens (nshell.domain.parsing:scan-result-tokens scan-result))
         (first-kind (nshell.domain.parsing:scan-token-kind first-token))
         (first-span (nshell.domain.parsing:scan-token-span first-token))
         (accept-end (second first-span))
         (prefix-p (member first-kind '(:dollar-unquote :process-substitution)
                           :test #'eq)))
    (labels ((paired-end (token)
               (let* ((token-span (nshell.domain.parsing:scan-token-span token))
                      (open-position (second token-span))
                      (open-token
                        (find-if
                         (lambda (candidate)
                           (and (eq (nshell.domain.parsing:scan-token-kind candidate)
                                    :delimiter-open)
                                (= (first (nshell.domain.parsing:scan-token-span candidate))
                                   open-position)))
                         (rest (member token tokens))))
                      (pair
                        (and open-token
                             (find-if
                              (lambda (candidate)
                                (equal (nshell.domain.parsing:scan-token-span open-token)
                                       (nshell.domain.parsing:delimiter-pair-open-span candidate)))
                              (nshell.domain.parsing:scan-result-delimiter-pairs
                               scan-result)))))
                 (and pair
                      (second
                       (nshell.domain.parsing:delimiter-pair-close-span pair))))))
      (when prefix-p
        (setf accept-end (or (paired-end first-token) accept-end)))
      (when (or (suggestion-word-like-token-p first-token)
                prefix-p
                (eq first-kind :redirect))
        (loop for token in (member first-token tokens)
              for span = (nshell.domain.parsing:scan-token-span token)
              for start = (first span)
              for end = (second span)
              do (cond
                   ((<= end accept-end))
                   ((= start accept-end)
                    (let ((kind (nshell.domain.parsing:scan-token-kind token)))
                      (cond
                        ((suggestion-word-like-token-p token)
                         (setf accept-end end))
                        ((member kind '(:dollar-unquote :process-substitution)
                                 :test #'eq)
                         (setf accept-end (or (paired-end token) end)))
                        (t (return)))))
                   (t (return)))))
      accept-end)))

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
  (let* ((end (length suggestion))
         (scan-result
           (handler-case
               (nshell.domain.parsing:scan-input
                suggestion
                :reader-context :bare-line)
             (error () nil))))
    (%make-suggestion-acceptance-segment
     (if scan-result
         (let* ((tokens (nshell.domain.parsing:scan-result-tokens scan-result))
                (position
                  (loop with position = 0
                        for token in tokens
                        while (eq (nshell.domain.parsing:scan-token-kind token)
                                  :whitespace)
                        do (setf position
                                 (second (nshell.domain.parsing:scan-token-span token)))
                        finally (return position)))
                (first-token
                  (suggestion-first-token-at-or-after tokens position)))
           (if first-token
               (suggestion-token-accept-end scan-result first-token)
               end))
         end))))

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

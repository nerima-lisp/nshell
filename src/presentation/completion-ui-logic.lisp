(in-package #:nshell.presentation)


(defun %candidate-text (candidate)
  (if (stringp candidate)
      candidate
      (nshell.domain.completion:candidate-text candidate)))

(defun %candidate-kind (candidate)
  (if (stringp candidate)
      :command
      (or (nshell.domain.completion:candidate-kind candidate) :command)))

(defun %candidate-description (candidate)
  (and (not (stringp candidate))
       (nshell.domain.completion:candidate-description candidate)))

(defun %common-prefix-two (left right)
  (let* ((limit (min (length left) (length right)))
         (index 0))
    (loop while (and (< index limit)
                     (char= (char left index) (char right index)))
          do (incf index))
    (subseq left 0 index)))

(defun completion-common-prefix (candidates)
  (when candidates
    (reduce #'%common-prefix-two
            (mapcar #'%candidate-text candidates))))

(defun %completion-escaped-position-p (input position)
  (let ((count 0)
        (index (1- position)))
    (loop while (and (>= index 0)
                     (char= (char input index) #\\))
          do (incf count)
             (decf index))
    (oddp count)))

(defun %completion-token-separator-at-p (input position)
  (and (nshell.domain.parsing:shell-token-separator-p (char input position))
       (not (%completion-escaped-position-p input position))))

(define-value-struct %completion-token-slice
    ((start 0 :type fixnum)
     (end 0 :type fixnum)))

(define-value-struct %completion-token-context
    ((bounds nil)
     (body-bounds nil)
     (quote-context nil)
     (raw-token "" :type string)))

(defun %completion-token-bounds (input cursor)
  (let* ((limit (length input))
         (cursor (max 0 (min cursor limit))))
    (cond
      ((and (< cursor limit)
            (%completion-token-separator-at-p input cursor))
       (let ((range (shell-token-range-before-position input cursor)))
         (if range
             (%make-completion-token-slice (shell-token-range-start range)
                                           (shell-token-range-end range))
             (%make-completion-token-slice cursor cursor))))
      ((and (= cursor limit)
            (plusp limit)
            (%completion-token-separator-at-p input (1- limit)))
       (%make-completion-token-slice cursor cursor))
      (t
       (let ((range (shell-token-range-at-or-after-cursor input cursor)))
         (if (null range)
             (%make-completion-token-slice cursor cursor)
             (%make-completion-token-slice (shell-token-range-start range)
                                           (shell-token-range-end range))))))))

(defun %completion-token-body-bounds (input bounds)
  (let* ((start (completion-token-slice-start bounds))
         (end (completion-token-slice-end bounds))
         (body-start start)
         (body-end end)
         (quote-char (and (< start end)
                          (member (char input start) '(#\" #\') :test #'char=)
                          (char input start))))
    (when quote-char
      (incf body-start))
    (when (and quote-char
               (< body-start body-end)
               (char= (char input (1- body-end)) quote-char))
      (decf body-end))
    (%make-completion-token-slice body-start body-end)))

(defun %completion-token-context (input cursor)
  (let* ((bounds (%completion-token-bounds input cursor))
         (body-bounds (%completion-token-body-bounds input bounds))
         (start (completion-token-slice-start bounds))
         (end (completion-token-slice-end bounds))
         (body-start (completion-token-slice-start body-bounds))
         (body-end (completion-token-slice-end body-bounds))
         (quote-context (%completion-quote-context input start end))
         (raw-token (%completion-unescape-token
                     (subseq input body-start body-end)
                     :quote-context quote-context)))
    (%make-completion-token-context bounds body-bounds quote-context raw-token)))

(defun %completion-replace-token (input context replacement)
  (let* ((token-bounds (completion-token-context-bounds context))
         (start (completion-token-slice-start token-bounds))
         (end (completion-token-slice-end token-bounds))
         (quote-context (completion-token-context-quote-context context)))
    (%completion-splice-with-quote-context input start end replacement
                                            :quote-context quote-context)))

(defun %completion-prefix-extends-token-p (prefix context)
  (let ((raw-token (completion-token-context-raw-token context)))
    (and (> (length prefix) (length raw-token))
         (string= raw-token (subseq prefix 0 (length raw-token))))))

(defun maybe-extend-completion-common-prefix (state candidates)
  "Apply an unambiguous completion prefix, if CANDIDATES advance the token."
  (with-normalized-input-state (state state)
    (let ((buffer (input-state-buffer state))
          (cursor (input-state-cursor-pos state))
          (prefix (completion-common-prefix candidates)))
      (if (null prefix)
          (values state nil)
          (let ((context (%completion-token-context buffer cursor)))
            (if (%completion-prefix-extends-token-p prefix context)
                (multiple-value-bind (new-buffer new-cursor)
                    (%completion-replace-token
                     buffer
                     context
                     (%completion-insertion-text
                      prefix
                      :quote-context (completion-token-context-quote-context context)))
                  (values (copy-input-state-clearing-completion
                           state
                           :buffer new-buffer
                           :cursor-pos new-cursor)
                          t))
                (values state nil)))))))

(defun apply-completion (input candidate &key (cursor (length input)))
  (let* ((context (%completion-token-context input cursor))
         (text (%completion-insertion-text
                (%candidate-text candidate)
                :quote-context (completion-token-context-quote-context context))))
    (%completion-replace-token input context text)))

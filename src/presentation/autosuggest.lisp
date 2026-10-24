(in-package #:nshell.presentation)


(defun autosuggest-token-prefix (input scan-result)
  (let* ((cursor (length input))
         (role (nshell.domain.parsing:scan-result-cursor-role scan-result))
         (wanted-kinds
           (case role
             (:command-head '(:command-head))
             ((:argument :redirect-target)
              '(:command-head :argument :string :here-doc-delimiter))
             (t nil)))
         (token
           (and wanted-kinds
                (find-if
                 (lambda (candidate)
                   (let ((span (nshell.domain.parsing:scan-token-span candidate)))
                     (and (= (second span) cursor)
                          (member (nshell.domain.parsing:scan-token-kind candidate)
                                  wanted-kinds
                                  :test #'eq))))
                 (nshell.domain.parsing:scan-result-tokens scan-result)
                 :from-end t))))
    (if (null token)
        (values "" nil nil nil)
        (let* ((span (nshell.domain.parsing:scan-token-span token))
               (start (first span))
               (end (second span))
               (kind (nshell.domain.parsing:scan-token-kind token))
               (quote-character
                 (and (eq kind :string)
                      (< start end)
                      (member (char input start) '(#\" #\') :test #'char=)
                      (char input start)))
               (quote-context
                 (and quote-character
                      (if (char= quote-character #\') :single :double)))
               (prefix-start (if quote-context (1+ start) start))
               (raw-prefix (subseq input prefix-start cursor))
               (closed-quoted-p
                 (and quote-context
                      (%autosuggest-closed-quoted-token-p input start end)))
               (unsupported-string-fragment-p
                 (and (eq kind :string) (null quote-context))))
          (values (%completion-unescape-token
                   raw-prefix
                   :quote-context quote-context)
                  quote-context
                  closed-quoted-p
                  unsupported-string-fragment-p)))))

(defun %autosuggest-closed-quoted-token-p (input start end)
  ;; A closed quoted token needs at least two characters: an opening quote and a
  ;; matching closing quote.  A lone quote (end - start = 1) is still open.
  (and (< (1+ start) end)
       (member (char input start) '(#\" #\') :test #'char=)
       (char= (char input start) (char input (1- end)))))

(defun completion-suggestion
    (knowledge-base input scan-result &key path
                                        (filesystem (nshell.infrastructure.acl:make-host-filesystem))
                                        alias-table function-table
                                        variable-names directory home-directory)
  (when (and knowledge-base
             (not (nshell.domain.parsing:shell-input-blank-p input)))
    (ignore-errors
      (multiple-value-bind (prefix quote-context closed-quoted-p
                            unsupported-string-fragment-p)
          (autosuggest-token-prefix input scan-result)
        (unless (or closed-quoted-p unsupported-string-fragment-p)
          (let* ((candidates
                   (remove-if-not
                    (lambda (candidate)
                      (nshell.domain.completion:candidate-prefix-match-p
                       prefix candidate))
                    (nshell.domain.completion:complete
                     knowledge-base
                     input
                     :path path
                     :filesystem filesystem
                     :alias-table alias-table
                     :function-table function-table
                     :variable-names variable-names
                     :directory directory
                     :home-directory home-directory)))
                 (text (if (or (null candidates)
                               (some (lambda (candidate)
                                       (member
                                        (nshell.domain.completion:candidate-kind candidate)
                                        '(:file :directory)
                                        :test #'eq))
                                     candidates))
                           (and candidates
                                (nshell.domain.completion:candidate-text
                                 (first candidates)))
                           (nshell.presentation::completion-common-prefix
                            candidates))))
            (when (and text
                       (<= (length prefix) (length text))
                       (string-equal prefix text :end2 (length prefix))
                       (< (length prefix) (length text)))
              (let ((escaped-prefix
                      (%completion-insertion-text
                       prefix
                       :quote-context quote-context))
                    (escaped-text
                      (%completion-insertion-text
                       text
                       :quote-context quote-context)))
                (subseq escaped-text (length escaped-prefix))))))))))

(defun compute-suggestion
    (history input &key knowledge-base path
                              (filesystem (nshell.infrastructure.acl:make-host-filesystem))
                              alias-table function-table
                              variable-names directory home-directory)
  (unless (nshell.domain.parsing:shell-input-blank-p input)
    (let ((scan-result
            (handler-case
                (nshell.domain.parsing:scan-input input)
              (error () nil))))
      (when (and scan-result
                 (not (eq (nshell.domain.parsing:scan-result-status scan-result)
                          :invalid))
                 (not (some
                       (lambda (token)
                         (let ((span (nshell.domain.parsing:scan-token-span token)))
                           (and (member
                                (nshell.domain.parsing:scan-token-kind token)
                                '(:line-comment :block-comment)
                                :test #'eq)
                                (<= (first span) (length input) (second span)))))
                       (nshell.domain.parsing:scan-result-tokens scan-result)))
                 (member
                  (nshell.domain.parsing:scan-result-cursor-role scan-result)
                  '(:command-head :argument :redirect-target)
                  :test #'eq))
        (or (nshell.application:history-suggestion history input :cwd directory)
            (completion-suggestion knowledge-base
                                   input
                                   scan-result
                                   :path path
                                   :filesystem filesystem
                                   :alias-table alias-table
                                   :function-table function-table
                                   :variable-names variable-names
                                   :directory directory
                                   :home-directory home-directory))))))

(defun accept-suggestion (input suggestion)
  (concatenate 'string input suggestion))

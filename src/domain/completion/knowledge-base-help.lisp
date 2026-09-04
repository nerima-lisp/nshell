(in-package #:nshell.domain.completion)


(defmacro %rebuild-completion-help-scan-state
    (state &key (subcommands nil subcommands-p) (flags nil flags-p)
           (option-values nil option-values-p)
           (option-value-kinds nil option-value-kinds-p)
           (collecting-subcommands-p nil collecting-subcommands-p-p))
  `(%make-completion-help-scan-state
    ,(if subcommands-p subcommands `(%completion-help-scan-state-subcommands ,state))
    ,(if flags-p flags `(%completion-help-scan-state-flags ,state))
    ,(if option-values-p option-values `(%completion-help-scan-state-option-values ,state))
    ,(if option-value-kinds-p option-value-kinds
         `(%completion-help-scan-state-option-value-kinds ,state))
    ,(if collecting-subcommands-p-p collecting-subcommands-p
         `(%completion-help-scan-state-collecting-subcommands-p ,state))))

(defun %completion-help-note-line-kind (state kind facts)
  (ecase kind
    (:heading
     (%rebuild-completion-help-scan-state state :collecting-subcommands-p t))
    (:blank
     (%rebuild-completion-help-scan-state state :collecting-subcommands-p nil))
    (:subcommand
     (%rebuild-completion-help-scan-state
      state
      :subcommands
      (cons (%completion-help-line-facts-subcommand-name facts)
            (%completion-help-scan-state-subcommands state))))
    (:stop-subcommands
     (%rebuild-completion-help-scan-state state :collecting-subcommands-p nil))
    (:other
     state)))

(defun %completion-help-note-option-values (state options values)
  (if (null values)
      state
      (%rebuild-completion-help-scan-state
       state
       :option-values
       (reduce (lambda (result option)
                 (if (%starts-with-p "--" option)
                     (cons (%make-kb-option-value-spec option values) result)
                     result))
               options
               :initial-value
               (%completion-help-scan-state-option-values state)))))
(defun %completion-help-note-options (state options)
  (%rebuild-completion-help-scan-state
   state :flags (append (reverse options)
                        (%completion-help-scan-state-flags state))))

(defun %completion-help-note-option-value-kinds (state kinds)
  (%rebuild-completion-help-scan-state
   state
   :option-value-kinds
   (reduce (lambda (result spec)
             (if (member spec result :test #'equal)
                 result
                 (cons spec result)))
           kinds
           :initial-value
           (%completion-help-scan-state-option-value-kinds state))))

(defmacro %with-completion-help-line-facts ((facts state line) &body body)
  `(let ((,facts (%completion-help-line-facts ,state ,line)))
     ,@body))

(defun %completion-help-update-scan-state (state line)
  (%with-completion-help-line-facts (facts state line)
    (let ((kind (%completion-help-line-facts-kind facts)))
      (let* ((state (%completion-help-note-line-kind state kind facts))
             (state (%completion-help-note-options
                     state (%completion-help-line-facts-options facts)))
             (state (%completion-help-note-option-values
                     state
                     (%completion-help-line-facts-options facts)
                     (%completion-help-line-facts-values facts))))
        (%completion-help-note-option-value-kinds
         state
         (%completion-help-line-facts-option-value-kinds facts))))))

(defun %completion-help-command-facts (help-text)
  (let ((state (%make-completion-help-scan-state nil nil nil nil nil)))
    (dolist (line (%completion-help-lines help-text))
      (setf state (%completion-help-update-scan-state state line)))
    (%make-completion-help-command-facts
     (%unique-string-values
      (nreverse (%completion-help-scan-state-subcommands state)))
     (%unique-string-values
      (nreverse (%completion-help-scan-state-flags state)))
     (nreverse (%completion-help-scan-state-option-values state))
     (remove-duplicates
      (nreverse (%completion-help-scan-state-option-value-kinds state))
      :test #'equal))))

(defun kb-add-command-from-help (kb cmd-name help-text &key description)
  "Add command completion metadata by parsing already-fetched help text."
  (let ((facts (%completion-help-command-facts help-text)))
    (kb-add-command kb cmd-name
                    :subcommands (%completion-help-command-facts-subcommands facts)
                    :flags (%completion-help-command-facts-flags facts)
                    :option-values
                    (%completion-help-command-facts-option-values facts)
                    :option-value-kinds
                    (%completion-help-command-facts-option-value-kinds facts)
                    :description description)))

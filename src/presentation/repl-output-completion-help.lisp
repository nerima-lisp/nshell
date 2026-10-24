;;; Completion help lookup and completion-session warming.
(in-package #:nshell.presentation)

(defparameter *completion-help-timeout* 3
  "Maximum seconds to wait for a dynamic completion help lookup.")

(defparameter *completion-help-max-output-chars* (* 128 1024)
  "Maximum help output size accepted by the completion parser.")

(progn
  (defun %completion-help-command-parts (command)
    (when (and (stringp command)
               (plusp (length command))
               (not (find-if
                     (lambda (character)
                       (member character
                               '(#\; #\| #\& #\< #\> #\` #\$ #\( #\)
                                 #\' #\" #\\ #\Newline #\Return)))
                     command)))
      (let ((parts nil)
            (start nil)
            (length (length command)))
        (labels ((flush (end)
                   (when start
                     (push (subseq command start end) parts)
                     (setf start nil))))
          (loop for index from 0 below length
                for character = (char command index)
                do (if (find character '(#\Space #\Tab))
                       (flush index)
                       (unless start
                         (setf start index))))
          (flush length))
        (nreverse parts))))

  (defun %fetch-completion-help (command)
    (let ((parts (%completion-help-command-parts command)))
      (when parts
        (let ((nshell.infrastructure.acl:*external-command-timeout*
                *completion-help-timeout*))
          (nshell.infrastructure.acl:run-external-capture
           (first parts)
           (append (rest parts) '("--help"))))))))

(defparameter *completion-help-fetcher* #'%fetch-completion-help
  "Function of COMMAND used to fetch help text for dynamic completion.")

(defparameter *completion-help-command-available-p*
  #'%repl-external-command-available-p
  "Predicate that permits dynamic help lookup for COMMAND.")

(defun %completion-help-simple-command-p (command)
  (not (null (%completion-help-command-parts command))))

(defparameter *completion-help-catalog-command-cache*
  (let ((cache (make-hash-table :test #'equal)))
    (dolist (spec (nshell.domain.completion:external-completion-command-specs) cache)
      (when (%completion-help-simple-command-p (first spec))
        (setf (gethash (first spec) cache) t))))
  "Set of catalogued external commands that should be enriched from help output.")

(defun %completion-help-catalogued-command-p (command)
  (gethash command *completion-help-catalog-command-cache*))

(defun %completion-help-text-p (output)
  (and (stringp output)
       (plusp (length output))
       (or (search "usage" output :test #'char-equal)
           (search "options" output :test #'char-equal)
           (search "commands" output :test #'char-equal)
           (search "flags" output :test #'char-equal))))

(defun %completion-help-eligible-command-p (command)
  (let ((parts (%completion-help-command-parts command)))
    (and parts
         (funcall *completion-help-command-available-p* (first parts)))))

(defun %completion-help-cache-primed-p (command)
  (nth-value 1 (gethash command *completion-help-cache*)))

(defun %completion-help-mark-cache-state (command state)
  (setf (gethash command *completion-help-cache*) state))

(defun %completion-help-cache-help-text (command output exit-code)
  (if (and (eql exit-code 0)
           (stringp output)
           (<= (length output) *completion-help-max-output-chars*)
           (%completion-help-text-p output))
      (progn
        (nshell.domain.completion:kb-add-command-from-help
         *kb* command output)
        :loaded)
      :missing))

(defun %completion-help-fetch-cache-state (command)
  (handler-case
      (multiple-value-bind (output exit-code)
          (funcall *completion-help-fetcher* command)
        (%completion-help-cache-help-text command output exit-code))
    (error ()
      :missing)))

(progn
  (defun %warm-command-completion-help (command)
    (when (%completion-help-eligible-command-p command)
      (unless (%completion-help-cache-primed-p command)
        (%completion-help-mark-cache-state command :loading)
        (%completion-help-mark-cache-state
         command
         (%completion-help-fetch-cache-state command)))))
  (defun %warm-command-completion-help-path
      (knowledge-base command argument-words prefix)
    (let ((resolved command))
      (loop
        (%warm-command-completion-help resolved)
        (let ((next
                (nshell.domain.completion:kb-resolve-command-path
                 knowledge-base command argument-words prefix)))
          (if (string= next resolved)
              (return)
              (setf resolved next)))))))

(defun %completion-session-valid-p (state)
  (with-normalized-input-state (state state)
    (let ((candidates (input-state-last-candidates state))
          (selected-index (input-state-completion-index state)))
      (and candidates
           (>= selected-index 0)
           (< selected-index (length candidates))
           (let ((base-buffer (input-state-completion-base-buffer state))
                 (base-cursor (input-state-completion-base-cursor state)))
             (and base-buffer
                  base-cursor
                  (multiple-value-bind (expected-buffer expected-cursor)
                      (apply-completion base-buffer
                                        (nth selected-index candidates)
                                        :cursor base-cursor)
                    (and (string= expected-buffer
                                  (input-state-buffer state))
                         (= expected-cursor
                            (input-state-cursor-pos state))))))))))
(defun %repl-completion-fallback-head-classification (context head-source)
  (let* ((upper-name (string-upcase head-source))
         (package-separator (position #\: upper-name))
         (package-name (and package-separator
                            (subseq upper-name 0 package-separator)))
         (symbol-name (if package-separator
                          (subseq upper-name (1+ package-separator))
                          upper-name))
         (user-package (find-package "NSHELL.USER"))
         (user-symbol (and user-package
                           (find-symbol head-source user-package)))
         (common-lisp-symbol (find-symbol symbol-name "COMMON-LISP"))
         (function-table
           (nshell.application:shell-context-function-table context)))
    (cond
      (package-name :host-form)
      ((nth-value 1 (gethash head-source function-table))
       :command-island)
      ((or (and common-lisp-symbol
                (or (special-operator-p common-lisp-symbol)
                    (macro-function common-lisp-symbol)
                    (fboundp common-lisp-symbol)))
           (and user-symbol (fboundp user-symbol)))
       :host-form)
      (t :command-island))))
(defun %repl-completion-head-classifier (context)
  (lambda (head-source)
    (handler-case
        (nshell.application:classify-sexp-head context head-source)
      (nshell.application:wp-interface-not-implemented (condition)
        (if (and (string= "L02"
                         (nshell.application:wp-interface-not-implemented-owner-wp
                          condition))
                 (eq 'nshell.application:classify-sexp-head
                     (nshell.application:wp-interface-not-implemented-interface
                      condition)))
            (%repl-completion-fallback-head-classification context head-source)
            (error condition))))))

(defun %refresh-completion-session-state (state)
  (with-normalized-input-state (state state)
    (let* ((text (input-state-buffer state))
           (cursor (input-state-cursor-pos state))
           (shell-context (%make-repl-shell-context))
           (scan-result
             (nshell.domain.parsing:scan-input
              text
              :cursor cursor
              :reader-context :auto
              :head-classifier
              (%repl-completion-head-classifier shell-context)))
           (role
             (nshell.domain.parsing:scan-result-cursor-role scan-result))
           (context
             (nshell.domain.completion:completion-context-for-scan
              scan-result cursor))
           (command
             (nshell.domain.completion:completion-context-command context))
           (command-position-p
             (nshell.domain.completion:completion-context-command-position-p
              context))
           (completion-role-p
             (member role '(:command-head :argument :redirect-target)
                     :test #'eq))
           (completion-path
             (nshell.domain.environment:env-get (ensure-environment) "PATH"))
           (filesystem
             (nshell.infrastructure.acl:make-host-filesystem)))
      (when (and (not command-position-p) (plusp (length command)))
        (%warm-command-completion-help-path
         *kb*
         command
         (nshell.domain.completion:completion-context-argument-words context)
         (nshell.domain.completion:completion-context-argument-prefix context)))
      (let ((candidates
              (when (and completion-role-p (plusp (length text)))
                (apply #'nshell.domain.completion:complete-in-context
                       *kb* text context
                       :path completion-path
                       :filesystem filesystem
                       :alias-table *aliases*
                       :function-table *functions*
                       (repl-completion-environment-arguments)))))
        (if candidates
            (multiple-value-bind (extended-state extended-p)
                (maybe-extend-completion-common-prefix state candidates)
              (declare (ignore extended-p))
              (setf (input-state-last-candidates extended-state) candidates)
              (values extended-state candidates))
            (values (clear-completion-session-state state) nil))))))

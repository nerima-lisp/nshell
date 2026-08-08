;;; Completion help lookup and completion-session warming.
(in-package #:nshell.presentation)

(defparameter *completion-help-timeout* 3
  "Maximum seconds to wait for a dynamic completion help lookup.")

(defparameter *completion-help-max-output-chars* (* 128 1024)
  "Maximum help output size accepted by the completion parser.")

(defun %fetch-completion-help (command)
  (let ((nshell.infrastructure.acl::*external-command-timeout*
          *completion-help-timeout*))
    (nshell.infrastructure.acl:run-external-capture command '("--help"))))

(defparameter *completion-help-fetcher* #'%fetch-completion-help
  "Function of COMMAND used to fetch help text for dynamic completion.")

(defparameter *completion-help-command-available-p*
  #'%repl-external-command-available-p
  "Predicate that permits dynamic help lookup for COMMAND.")

(defun %completion-help-simple-command-p (command)
  (and (stringp command)
       (not (find-if (lambda (character)
                       (member character '(#\Space #\Tab #\Newline #\Return)))
                     command))))

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
  (and (stringp command)
       (plusp (length command))
       (%completion-help-catalogued-command-p command)
       (funcall *completion-help-command-available-p* command)))

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

(defun %warm-command-completion-help (command)
  (when (%completion-help-eligible-command-p command)
    (unless (%completion-help-cache-primed-p command)
      (%completion-help-mark-cache-state command :loading)
      (%completion-help-mark-cache-state
       command
       (%completion-help-fetch-cache-state command)))))

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

(defun %refresh-completion-session-state (state)
  (with-normalized-input-state (state state)
    (let* ((text (input-state-buffer state))
           (context (nshell.domain.completion:completion-context-for text))
           (command (nshell.domain.completion:completion-context-command context))
           (command-position-p
             (nshell.domain.completion:completion-context-command-position-p context))
           (completion-path
             (nshell.domain.environment:env-get (ensure-environment) "PATH")))
      (unless command-position-p
        (%warm-command-completion-help command))
      (let ((candidates (when (> (length text) 0)
                          (nshell.domain.completion:complete
                           *kb* text
                           :path completion-path
                           :alias-table *aliases*
                           :function-table *functions*))))
        (if candidates
            (multiple-value-bind (extended-state extended-p)
                (maybe-extend-completion-common-prefix state candidates)
              (declare (ignore extended-p))
              (setf (input-state-last-candidates extended-state) candidates)
              (values extended-state candidates))
            (values (clear-completion-session-state state) nil))))))

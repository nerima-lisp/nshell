;;; REPL completion output helpers
(in-package #:nshell.presentation)

(defun reset-rendered-completion-state ()
  (setf *completion-rendered-lines* 0))

(defun %render-completions-below-prompt (candidates &key selected-index)
  (nshell.infrastructure.terminal:ansi-save-cursor)
  (unwind-protect
       (progn
         (let ((rows (max 0
                          (- (1- *prompt-rendered-lines*)
                             *prompt-rendered-cursor-row*))))
           (when (plusp rows)
             (format t "~C[~dB" #\Esc rows)))
         (render-completions candidates :selected-index selected-index))
    (nshell.infrastructure.terminal:ansi-restore-cursor)))

(defun clear-rendered-completions ()
  (when (> *completion-rendered-lines* 0)
    (nshell.infrastructure.terminal:ansi-save-cursor)
    (unwind-protect
         (progn
           (let ((rows (+ (max 0
                               (- (1- *prompt-rendered-lines*)
                                  *prompt-rendered-cursor-row*))
                          *completion-rendered-lines*
                          1)))
             (when (plusp rows)
               (format t "~C[~dB" #\Esc rows)))
            (format t "~C" #\Return)
            (nshell.infrastructure.terminal:ansi-clear-line)
            (loop repeat *completion-rendered-lines*
                 do
             (format t "~C[A" #\Esc)
             (nshell.infrastructure.terminal:ansi-clear-line)))
      (nshell.infrastructure.terminal:ansi-restore-cursor))
    (reset-rendered-completion-state)))

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
           (completion-path
             (nshell.domain.environment:env-get (ensure-environment) "PATH"))
           (candidates (when (> (length text) 0)
                         (nshell.domain.completion:complete
                          *kb* text :path completion-path))))
      (if candidates
          (multiple-value-bind (extended-state extended-p)
              (maybe-extend-completion-common-prefix state candidates)
            (declare (ignore extended-p))
            (setf (input-state-last-candidates extended-state) candidates)
            (values extended-state candidates))
          (values (clear-completion-session-state state) nil)))))
